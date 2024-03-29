{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE QuasiQuotes           #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE ViewPatterns          #-}
{-|
Module      : Application
Description : De Calixtinus yesod application
Copyright   : (c) Doug Palmer, 2023
License     : MIT
Maintainer  : doug@charvolant.org
Stability   : experimental
Portability : POSIX

Yesod application that allows the user to enter preferences and have a route generated.
-}

module Camino.Server.Application where

import GHC.Generics (Generic)
import Data.Aeson
import Camino.Camino
import qualified Camino.Config as C
import Camino.Planner (Trip)
import Camino.Preferences
import Camino.Util
import Camino.Display.Html
import Camino.Display.I18n
import Camino.Display.KML
import Camino.Display.Routes
import Camino.Server.Fields
import Camino.Server.Forms
import Camino.Server.Foundation
import Camino.Server.Settings
import Control.Monad (when)
import qualified Data.Map as M (fromList)
import qualified Data.ByteString.Lazy as LB (fromStrict, toStrict)
import Data.Default.Class
import Data.Either (isLeft, fromLeft, fromRight, lefts, rights)
import Data.List (any, find, elem, isPrefixOf, partition, sortOn)
import Data.Maybe (fromJust, fromMaybe, isJust, isNothing)
import qualified Data.Map as M
import qualified Data.Set as S
import Data.Text (Text, cons, intercalate, pack, snoc, splitOn, unpack)
import Data.Text.Lazy (toStrict)
import Text.Hamlet
import Text.Julius (RawJS(..))
import Text.Blaze (ToMarkup (toMarkup))
import Text.Blaze.Html.Renderer.Text (renderHtml)
import Text.Read (readMaybe)
import Text.XML
import Yesod
import Yesod.Form.Functions
import Debug.Trace
import Camino.Planner (planCamino)


mkYesodDispatch "CaminoApp" resourcesCaminoApp

data PreferenceStep =
    FitnessStep
  | RangeStep
  | ServicesStep
  | CaminoStep
  | RoutesStep
  | StartStep
  | StopsStep
  | ShowPreferencesStep
  deriving (Eq, Ord, Enum, Bounded, Show, Read)

homeP :: Handler Html
homeP =
  defaultLayout $ do
    setTitleI MsgAppName
    $(widgetFile "homepage")

getHelpR :: Handler Html
getHelpR = do
  master <- getYesod
  langs <- languages
  let config = caminoAppConfig master
  let router = renderCaminoRoute config langs
  let messages = renderCaminoMsg config
  defaultLayout $ do
    setTitleI MsgHelpTitle
    toWidget ((helpWidget langs) messages router)

-- | Help for the languages that we have
helpWidget :: [Text] -> HtmlUrlI18n CaminoMsg CaminoRoute
helpWidget [] = helpWidget ["en"]
helpWidget ("en":_) = $(ihamletFile "templates/help/help-en.hamlet")
helpWidget (_:other) = helpWidget other

getHomeR :: Handler Html
getHomeR = homeP

postPlanR :: Handler Html
postPlanR = do
  ((result, widget), enctype) <- runFormPost $ (stepForm ShowPreferencesStep) Nothing
  case result of
      FormSuccess prefs -> do
         encodeToSession "preference-data" prefs
         planPage prefs
      FormFailure errs -> do
        setMessage [shamlet|
          $forall err <- errs
            <div .text-danger>#{err}
        |]
        stepPage ShowPreferencesStep Nothing widget enctype
      _ ->
        getHomeR

postPlanKmlR :: Handler TypedContent
postPlanKmlR = do
  ((result, widget), enctype) <- runFormPost $ (stepForm ShowPreferencesStep) Nothing
  case result of
      FormSuccess prefs -> do
         encodeToSession "preference-data" prefs
         planKml prefs
      _ ->
        invalidArgs ["Bad preferences data"]


getPreferencesR :: Handler Html
getPreferencesR = do
    master <- getYesod
    prefs <- decodeFromSession "preference-data"
    let prefs' = Just $ maybe (defaultPreferenceData master) id prefs
    ((_result, widget), enctype) <- runFormPost $ chooseFitnessForm prefs'
    stepPage FitnessStep Nothing widget enctype

postPreferencesR :: Handler Html
postPreferencesR = do
  step <- lookupPostParam "_step"
  next <- lookupPostParam "_next"
  params <- getPostParams
  -- traceM ("Params = " ++ show params)
  let step' = maybe Nothing (readMaybe . unpack) step
  let next' = maybe FitnessStep id $ maybe Nothing (readMaybe . unpack) next
  case step' of
    Nothing ->
      getPreferencesR
    Just step'' ->
      nextStep step'' next'

nextStep step next = do
      ((result, widget), enctype) <- runFormPost $ (stepForm step) Nothing
      case result of
          FormSuccess prefs -> do
             encodeToSession "preference-data" prefs
             (widget', enctype') <- generateFormPost $ (stepForm next) (Just prefs)
             stepPage next (Just prefs) widget' enctype'
          FormFailure errs -> do
            setMessage [shamlet|
              $forall err <- errs
                <div .text-danger>#{err}
            |]
            stepPage step Nothing widget enctype
          _ ->
            getHomeR

stepForm :: PreferenceStep -> Maybe PreferenceData -> (Html -> MForm Handler (FormResult PreferenceData, Widget))
stepForm FitnessStep prefs = chooseFitnessForm prefs
stepForm RangeStep prefs = chooseRangeForm prefs
stepForm ServicesStep prefs = chooseServicesForm prefs
stepForm CaminoStep prefs = chooseCaminoForm prefs
stepForm RoutesStep prefs = chooseRoutesForm prefs
stepForm StartStep prefs = chooseStartForm prefs
stepForm StopsStep prefs = chooseStopsForm prefs
stepForm ShowPreferencesStep prefs = confirmPreferencesForm prefs

stepPage' :: CaminoAppMessage -> CaminoAppMessage -> Maybe CaminoAppMessage -> PreferenceStep -> PreferenceStep -> PreferenceStep -> Widget -> Enctype -> Handler Html
stepPage' title top bottom step prev next widget enctype = do
  (embedded, help) <- helpPopup step
  defaultLayout $ do
    setTitleI title
    $(widgetFile "step")

stepPage :: PreferenceStep -> Maybe PreferenceData -> Widget -> Enctype -> Handler Html
stepPage FitnessStep _ widget enctype = stepPage' MsgFitnessTitle MsgFitnessText (Just MsgFitnessBottom) FitnessStep FitnessStep RangeStep widget enctype
stepPage RangeStep _ widget enctype = stepPage' MsgRangeTitle MsgRangeText Nothing RangeStep FitnessStep ServicesStep widget enctype
stepPage ServicesStep _ widget enctype = stepPage' MsgServicesTitle MsgServicesText Nothing ServicesStep RangeStep CaminoStep widget enctype
stepPage CaminoStep _ widget enctype = stepPage' MsgCaminoTitle MsgCaminoText Nothing CaminoStep ServicesStep RoutesStep widget enctype
stepPage RoutesStep _ widget enctype = stepPage' MsgRoutesTitle MsgRoutesText Nothing RoutesStep CaminoStep StartStep widget enctype
stepPage StartStep _ widget enctype = stepPage' MsgStartTitle MsgStartText Nothing StartStep RoutesStep StopsStep widget enctype
stepPage StopsStep _ widget enctype = stepPage' MsgStopsTitle MsgStopsText Nothing StopsStep StartStep ShowPreferencesStep widget enctype
stepPage ShowPreferencesStep (Just prefs) widget enctype = let
    preferences = travelPreferencesFrom prefs
    camino = caminoPreferencesFrom prefs
  in
    defaultLayout $ do
      master <- getYesod
      langs <- languages
      let config = caminoAppConfig master
      let router = renderCaminoRoute config langs
      let messages = renderCaminoMsg config
      setTitleI MsgShowPreferencesTitle
      $(widgetFile "show-preferences")
stepPage ShowPreferencesStep _ widget enctype = stepPage' MsgShowPreferencesTitle MsgShowPreferencesText Nothing ShowPreferencesStep StopsStep ShowPreferencesStep widget enctype

helpPopup' :: PreferenceStep -> [Lang] -> Maybe (HtmlUrlI18n CaminoMsg CaminoRoute)
helpPopup' FitnessStep _ = Just $(ihamletFile "templates/help/fitness-help-en.hamlet")
helpPopup' RangeStep _ = Just $(ihamletFile "templates/help/range-help-en.hamlet")
helpPopup' ServicesStep _ = Just $(ihamletFile "templates/help/services-help-en.hamlet")
helpPopup' RoutesStep _ = Just $(ihamletFile "templates/help/routes-help-en.hamlet")
helpPopup' StartStep _ = Just $(ihamletFile "templates/help/start-help-en.hamlet")
helpPopup' StopsStep _ = Just $(ihamletFile "templates/help/stops-help-en.hamlet")
helpPopup' _ _ = Nothing

helpPopup :: PreferenceStep -> Handler (Widget, Widget)
helpPopup step = do
  master <- getYesod
  langs <- languages
  let config = caminoAppConfig master
  let router = renderCaminoRoute config langs
  let messages = renderCaminoMsg config
  let help' = (\h -> h messages router) <$> helpPopup' step langs
  return $ case help' of
    Nothing -> (
         [whamlet| |]
       , [whamlet| |]
      )
    Just help -> (
           [whamlet|
            <a .fs-2 .text-primary href="#" onclick="showHelpPopup()" title="_{MsgMoreInformation}">
              <span .ca-help>
           |]
        , $(widgetFile "help-popup")
      )

addError :: Either Location Trip -> Handler ()
addError (Left loc) = do
  setMessage [shamlet|
    <div ..alert .alert-warning role="alert">
      Break at #{locationID loc} #{locationName loc}
    |]
  return ()
addError _ = do
  return ()

planPage :: PreferenceData -> Handler Html
planPage prefs = do
    master <- getYesod
    langs <- languages
    let tprefs = travelPreferencesFrom prefs
    let cprefs = caminoPreferencesFrom prefs
    let trip = planCamino tprefs cprefs
    let trip' = either (const Nothing) Just trip
    let config = caminoAppConfig master
    let router = renderCaminoRoute config langs
    let messages = renderCaminoMsg config
    let html = (caminoHtmlBase config tprefs cprefs trip') messages router
    addError trip
    defaultLayout $ do
      setTitle [shamlet|#{locationName (preferenceStart cprefs)} - #{locationName (preferenceFinish cprefs)}|]
      (toWidget html)

-- | The MIME type for KML
kmlType :: ContentType
kmlType = "application/vnd.google-earth.kml+xml"

-- | Generate a file name for this
kmlFileName :: CaminoPreferences -> Maybe Trip -> Text
kmlFileName camino Nothing = (toFileName $ caminoName $ preferenceCamino camino) <> ".kml"
kmlFileName camino (Just trip) = (toFileName $ caminoName $ preferenceCamino camino) <> "-" <> (toFileName $ locationName $ start trip) <> "-" <> (toFileName $ locationName $ finish trip) <> ".kml"

planKml :: PreferenceData -> Handler TypedContent
planKml prefs = do
    master <- getYesod
    langs <- languages
    let tprefs = travelPreferencesFrom prefs
    let cprefs = caminoPreferencesFrom prefs
    let trip = planCamino tprefs cprefs
    let trip' = either (const Nothing) Just trip
    let config = caminoAppConfig master
    let router = renderCaminoRoute config langs
    let messages = renderCaminoMsg config
    let kml = createCaminoDoc config tprefs cprefs trip'
    let result = renderLBS (def { rsPretty = True, rsUseCDATA = useCDATA }) kml
    addHeader "content-disposition" ("attachment; filename=\"" <> kmlFileName cprefs trip' <> "\"")
    return $ TypedContent kmlType (toContent result)

runCaminoApp :: CaminoApp -> IO ()
runCaminoApp app = warp (caminoAppPort app) app