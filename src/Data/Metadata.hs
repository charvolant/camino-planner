{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-|
Module      : Metadata
Description : Dublin-core style metadata for data sources
Copyright   : (c) Doug Palmer, 2024
License     : MIT
Maintainer  : doug@charvolant.org
Stability   : experimental
Portability : POSIX

A module that handles lists of metadata-style statements using URI-based terms.
The expection is that this can be embedded in other data types that use JSON-style
-}
module Data.Metadata (
  Metadata(..),
  Namespace(..),
  Statement(..),

  decodeTerm,
  encodeTerm,
  statementLabel,
  statementLang,
  statementTerm,
  statementValue
) where

import Data.Aeson
import Data.Default.Class
import Data.List (find)
import Data.Localised (Tagged(..), TaggedText(..), localeLanguageTag)
import Data.Maybe (fromJust)
import qualified Data.Text as T (Text, concat, isPrefixOf, null, split, stripPrefix, stripSuffix, unpack, pack)
import Network.URI

data Namespace = Namespace {
  namespacePrefix :: T.Text, -- ^ The prefix to use
  namespaceUri :: T.Text -- ^ The corresponding namespace URI
} deriving (Show)

instance FromJSON Namespace where
  parseJSON (Object v) = do
    prefix' <- v .: "prefix"
    namespace' <- v .: "namespace"
    return (Namespace (T.concat [prefix', ":"]) namespace')
  parseJSON v = error ("Unable to parse namespace " ++ show v)

instance ToJSON Namespace where
  toJSON (Namespace prefix' namespace') = object [ "prefix" .= (fromJust $ T.stripSuffix ":" prefix'), "namespace" .= namespace' ]

decodeTerm :: [Namespace] -> T.Text -> Maybe URI
decodeTerm namespaces term =
  let
    namespace = find (\ns -> T.isPrefixOf (namespacePrefix ns) term) namespaces
    normalised = maybe term (\ns -> T.concat [(namespaceUri ns), (fromJust $ T.stripPrefix (namespacePrefix ns) term)]) namespace
  in
    parseURI $ T.unpack normalised

encodeTerm :: [Namespace] -> URI -> T.Text
encodeTerm namespaces term =
  let
    term' = T.pack $ (uriToString id term) ""
    namespace = find (\ns -> T.isPrefixOf (namespaceUri ns) term') namespaces
  in
    maybe term' (\ns -> T.concat [(namespacePrefix ns), (fromJust $ T.stripPrefix (namespaceUri ns) term')]) namespace

data Statement =
  Statement URI TaggedText -- ^ A proper statement
  | RawStatement T.Text TaggedText -- ^ A statement that needs to be decoded
  deriving (Show)

instance FromJSON Statement where
  parseJSON (Object v) = do
    term' <- v .: "term"
    value' <- v .: "value"
    return (RawStatement term' value')
  parseJSON v = error ("Unable to parse namespace " ++ show v)

instance ToJSON Statement where
  toJSON (RawStatement term' value') = object [ "term" .= term', "value" .= value' ]
  toJSON (Statement term' value') = object [ "term" .= (uriToString id term') "", "value" .= value' ]

fromRawStatement _namespaces s@(Statement _ _) = s
fromRawStatement namespaces (RawStatement term value) = Statement (fromJust $ decodeTerm namespaces term) value

toRawStatement :: [Namespace] -> Statement -> Statement
toRawStatement _namespaces r@(RawStatement _ _) = r
toRawStatement namespaces (Statement term value) = RawStatement (encodeTerm namespaces term) value

statementTerm :: Statement -> URI
statementTerm (RawStatement term _value) = maybe nullURI id (parseURI $ T.unpack term)
statementTerm (Statement term _value) = term

statementValue :: Statement -> T.Text
statementValue (RawStatement _term value) = plainText value
statementValue (Statement _term value) = plainText value

statementLang :: Statement -> Maybe T.Text
statementLang (RawStatement _term value) = if T.null lang then Nothing else Just lang where lang = localeLanguageTag $ locale value
statementLang  (Statement _term value) = if T.null lang then Nothing else Just lang where lang = localeLanguageTag $ locale value

statementLabel :: Statement -> T.Text
statementLabel statement =
  let
    url = case statement of
      (RawStatement term _) -> term
      (Statement term _) -> T.pack $ (uriToString id term) ""
    broken = dropWhile T.null (T.split (\c -> c == '#' || c == '/') url)
  in
    if length broken == 0 then url else last broken

data Metadata = Metadata {
  metadataNamespaces :: [Namespace], -- ^ The list of namespaces
  metadataStatements :: [Statement] -- ^ The list of metadata statements
} deriving (Show)

instance FromJSON Metadata where
  parseJSON (Object v) = do
    namespaces' <- v .:? "namespaces" .!= []
    statements' <- v .: "statements"
    let statements'' =  map (fromRawStatement namespaces') statements'
    return (Metadata { metadataNamespaces = namespaces', metadataStatements = statements'' })
  parseJSON v = error ("Unable to parse metadata object " ++ show v)

instance ToJSON Metadata where
  toJSON (Metadata namespaces' statements') =
    let
      statements'' = map (toRawStatement namespaces') statements'
    in
      object [ "namespaces" .= namespaces', "statements" .= statements'' ]

-- | A default, empty metadata container with the dc: and dcterms: namespaces
instance Default Metadata where
  def = Metadata {
    metadataNamespaces = [
      Namespace "dc:" "http://purl.org/dc/elements/1.1/",
      Namespace "dcterms:" "http://purl.org/dc/terms/"
    ],
    metadataStatements = []
  }
