{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Language.EO.Test.Yaml where

import Control.Monad (forM)
import Data.List (sort)
import Language.EO.Phi.Rules.Yaml (RuleSet, parseRuleSetFromFile)
import System.Directory (listDirectory)
import System.FilePath ((</>))

fileTests :: FilePath -> IO RuleSet
fileTests = parseRuleSetFromFile

directoryTests :: FilePath -> IO [RuleSet]
directoryTests dir = do
  paths <- listDirectory dir
  forM (sort paths) $ \path ->
    fileTests (dir </> path)
