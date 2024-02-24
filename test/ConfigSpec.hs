{-# LANGUAGE OverloadedStrings #-}
module ConfigSpec(testConfig) where

import Test.HUnit
import Camino.Config
import Data.Map as M
import Data.Maybe (fromJust, isJust)
import TestUtils

testConfig1 = Config {
  configParent = Just defaultConfig,
  configWeb = Web {
    webAssets = [
      Asset {
        assetId = "foo",
        assetType = Css,
        assetPath = "bar/baz.css",
        assetIntegrity = Nothing,
        assetCrossOrigin = Unused
      }
    ],
    webLinks = []
  }
}

testConfig2 = Config {
  configParent = Just defaultConfig,
  configWeb = Web {
    webAssets = [],
    webLinks = [
      Link {
        linkId = "foo",
        linkType = Header,
        links = [
          LinkI18n {
            linkLocale = "fr",
            linkLabel = "Feu",
            linkPath = "foo-fr.html"
          }
        ]
      }
    ]
  }
}


testConfig = TestList [
  TestLabel "GetAssets" testGetAssets,
  TestLabel "GetAsset" testGetAsset,
  TestLabel "GetLinks" testGetLinks
  ]
  
testGetAssets = TestList [
  testGetAssets1, testGetAssets2, testGetAssets3
  ]

testGetAssets1 = TestCase (assertEqual "getAssets 1" 3 (length $ getAssets JavaScript testConfig1))

testGetAssets2 = TestCase (assertEqual "getAssets 2" 4 (length $ getAssets Css testConfig1))

testGetAssets3 = TestCase (assertEqual "getAssets 3" 3 (length $ getAssets Css defaultConfig))

  
testGetAsset = TestList [
  testGetAsset1, testGetAsset2, testGetAsset3
  ]

testGetAsset1 = TestCase (do
    assertEqual "getAsset 1 1" True (isJust $ getAsset "leafletJs" testConfig1)
    assertEqual "getAsset 1 2" "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" (assetPath $ fromJust $ getAsset "leafletJs" testConfig1)
    )

testGetAsset2 = TestCase (do
    assertEqual "getAsset 2 1" True (isJust $ getAsset "foo" testConfig1)
    assertEqual "getAsset 2 2" "bar/baz.css" (assetPath $ fromJust $ getAsset "foo" testConfig1)
    )

testGetAsset3 = TestCase (
    assertEqual "getAsset 3" False (isJust $ getAsset "foo" defaultConfig)
    )


  
testGetLinks = TestList [
  testGetLinks1, testGetLinks2
  ]

testGetLinks1 = TestCase (assertEqual "getLinks 1" 1 (length $ getLinks Header testConfig1))

testGetLinks2 = TestCase (assertEqual "getLinks 2" 2 (length $ getLinks Header testConfig2))

