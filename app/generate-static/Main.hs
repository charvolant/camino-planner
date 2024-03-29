{-# LANGUAGE OverloadedStrings #-}
{-|
Module      : Main
Description : Generate static files
Copyright   : (c) Doug Palmer, 2024
License     : MIT
Maintainer  : doug@charvolant.org
Stability   : experimental
Portability : POSIX
-}
module Main (main) where

import Camino.Camino
import Camino.Display.Static
import Camino.Config
import Control.Monad (mapM)
import Options.Applicative
import System.FilePath
import System.Directory
import Debug.Trace

data Generate = Generate {
  config :: FilePath,
  templates :: FilePath,
  output :: FilePath,
  caminos :: [FilePath]
}

arguments :: Parser Generate
arguments =  Generate
    <$> (strOption (long "config" <> short 'c' <> value "./config.yaml" <> metavar "CONFIG" <> help "Configuration file"))
    <*> (strOption (long "templates" <> short 't' <> value "./templates" <> metavar "TEMPLATERDIR" <> help "Template directory"))
    <*> (strOption (long "output" <> short 'o' <> value "./static" <> metavar "OUTPUTDIR" <> help "Output directory"))
    <*> some (argument str (metavar "CAMINO-FILE"))

generate :: Generate -> IO ()
generate opts = do
    caminos' <- mapM readCamino (caminos opts) 
    config' <- readConfigFile (config opts)
    let output' = output opts
    let templates' = templates opts
    createDirectoryIfMissing True output'
    createCssFiles config' caminos' (output' </> "css")
    createHelpFiles config' (output' </> "help")

main :: IO ()
main = do
    opts <- execParser $ info (arguments <**> helper) (fullDesc <> progDesc "Create static files")
    generate opts