import Test.HUnit
import CaminoSpec
import ConfigSpec
import WalkingSpec
import PlannerSpec
import GraphSpec
import ProgrammingSpec
import qualified Data.ByteString.Lazy as B
import Data.Aeson
import Camino.Camino
import Camino.Preferences
import Data.Either (fromRight, isLeft)
import Control.Monad (when)

main :: IO ()
main = do
    cf <- B.readFile "lisbon-porto.json"
    let ec = eitherDecode cf :: Either String Camino
    when (isLeft ec) $ putStrLn (show ec)
    let lisbonPorto = fromRight (Camino { }) ec
    pf <- B.readFile "short-preferences.json"
    let ep = eitherDecode pf :: Either String Preferences
    when (isLeft ep) $ putStrLn (show ep)
    let shortPreferences = fromRight (defaultPreferences) ep
    results <- runTestTT (testList shortPreferences lisbonPorto)
    putStrLn $ show results

testList prefs camino = TestList [ 
    TestLabel "Config" testConfig, 
    TestLabel "Camino" testCamino, 
    TestLabel "Walking" testWalking, 
    TestLabel "Graph" testGraph, 
    TestLabel "Programming" testProgramming, 
    TestLabel "Planner" (testPlanner prefs camino) 
  ]