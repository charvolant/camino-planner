{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-|
Module      : Css
Description : Produce Css styles for HTML and KML display
Copyright   : (c) Doug Palmer, 2023
License     : MIT
Maintainer  : doug@charvolant.org
Stability   : experimental
Portability : POSIX
-}
module Camino.Display.Css (
  caminoCss,
  toCssColour
) where

import Camino.Camino
import Camino.Config
import Camino.Display.Routes
import Data.Char (ord)
import Data.Colour
import Data.Colour.SRGB
import Data.Text ()
import Numeric
import Text.Cassius
import Text.Hamlet (Render)

-- The traditional blue file colour. Used as a primary darkish colour
caminoBlue :: Colour Double
caminoBlue = sRGB24read "1964c0"

-- The traditional blue file colour. Used as a primary darkish colour
caminoYellow :: Colour Double
caminoYellow = sRGB24read "f9b34a"

-- | Create a CSS-able colour
toCssColour :: Colour Double -- ^ The colour to display
 -> String -- ^ A #rrggbb colour triple
toCssColour = sRGB24show

paletteCss :: String -> Palette -> Render CaminoRoute -> Css
paletteCss ident pal = [cassius|
.#{ident}
  h1
    color: #{toCssColour $ paletteColour pal}
  h2
    color: #{toCssColour $ paletteColour pal}
  h3
    color: #{toCssColour $ paletteColour pal}
  h4
    color: #{toCssColour $ paletteColour pal}
  h5
    color: #{toCssColour $ paletteColour pal}
  |]
  
iconCss :: String -> Char -> Render CaminoRoute -> Css
iconCss ident ch = [cassius|
.#{ident}::before
  font-family: "Camino Icons"
  font-weight: normal
  line-height: 1
  text-rendering: auto
  content: "\#{hex $ ord ch}"
|]
  where
    hex c = showHex c ""

iconList :: [(String, Char)]
iconList = [
    ("ca-accessible", '\xe067'),
    ("ca-albergue", '\xe010'),
    ("ca-bank", '\xe042'),
    ("ca-bed-double", '\xe022'),
    ("ca-bed-double-wc", '\xe023'),
    ("ca-bed-quadruple", '\xe026'),
    ("ca-bed-quadruple-wc", '\xe027'),
    ("ca-bed-single", '\xe020'),
    ("ca-bed-triple", '\xe024'),
    ("ca-bed-triple-wc", '\xe025'),
    ("ca-bedlinen", '\xe06c'),
    ("ca-breakfast", '\xe064'),
    ("ca-bicycle-repair", '\xe045'),
    ("ca-bicycle-storage", '\xe06a'),
    ("ca-bridge", '\xe004'),
    ("ca-bus", '\xe047'),
    ("ca-campground", '\xe019'),
    ("ca-camping", '\xe019'),
    ("ca-city", '\xe003'),
    ("ca-cycling", '\xe081'),
    ("ca-dinner", '\xe065'),
    ("ca-dryer", '\xe062'),
    ("ca-ferry", '\xe082'),
    ("ca-globe", '\xe090'),
    ("ca-groceries", '\xe041'),
    ("ca-guesthouse", '\xe012'),
    ("ca-handwash", '\xe063'),
    ("ca-heating", '\xe070'),
    ("ca-heating", '\xe070'),
    ("ca-help", '\xe092'),
    ("ca-homestay", '\xe011'),
    ("ca-hostel", '\xe012'),
    ("ca-hotel", '\xe013'),
    ("ca-house", '\xe011'),
    ("ca-information", '\xe091'),
    ("ca-intersection", '\xe005'),
    ("ca-kitchen", '\xe06b'),
    ("ca-lockers", '\xe066'),
    ("ca-mattress", '\xe028'),
    ("ca-medical", '\xe044'),
    ("ca-monastery", '\xe006'),
    ("ca-peak", '\xe007'),
    ("ca-pets", '\xe069'),
    ("ca-pharmacy", '\xe043'),
    ("ca-poi", '\xe000'),
    ("ca-pool", '\xe06e'),
    ("ca-prayer", '\xe06f'),
    ("ca-restaurant", '\xe040'),
    ("ca-rowing", '\xe083'),
    ("ca-shared", '\xe021'),
    ("ca-sleeping-bag", '\xe028'),
    ("ca-stables", '\xe068'),
    ("ca-tent", '\xe018'),
    ("ca-towels", '\xe06d'),
    ("ca-town", '\xe002'),
    ("ca-train", '\xe046'),
    ("ca-village", '\xe001'),
    ("ca-walking", '\xe080'),
    ("ca-washing-machine", '\xe061'),
    ("ca-wifi", '\xe060')
  ]
  
caminoIconCss :: [Render CaminoRoute -> Css]
caminoIconCss = map (\(ident, ch) -> iconCss ident ch) iconList

caminoFontCss :: AssetConfig -> Render CaminoRoute -> Css
caminoFontCss asset = [cassius|
@font-face
  font-family: "#{ident}"
  font-weight: normal
  font-style: normal
  src: url(@{AssetRoute ident})
|]
  where
    ident = assetId asset

caminoBaseCss :: Render CaminoRoute -> Css
caminoBaseCss = $(cassiusFile "templates/css/base.cassius")

caminoCss :: Config -> [Camino] -> [Render CaminoRoute -> Css]
caminoCss config caminos = (base':default':routes') ++ fonts' ++ icons'
  where
    base' = caminoBaseCss
    default' = paletteCss "location-default" (routePalette $ caminoDefaultRoute (head caminos))
    routes' = concat $ map (\c -> map (\r -> paletteCss ("location-" ++ (routeID r)) (routePalette r)) (caminoRoutes c)) caminos
    fonts' = map caminoFontCss (getAssets Font config)
    icons' = caminoIconCss
