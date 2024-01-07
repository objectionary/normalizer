{-# LANGUAGE RecordWildCards #-}

module Language.EO.PhiSpec where

import Control.Monad (forM_)
import Data.Char (isSpace)
import Data.List (dropWhileEnd)
import Test.Hspec

import qualified Language.EO.Phi as Phi
import Test.EO.Phi

spec :: Spec
spec = do
  tests <- runIO (allPhiTests "test/eo/phi/")
  describe "Normalizer" $ do
    forM_ tests $ mapM_ $ \PhiTest{..} -> do
      it name $ do
        Phi.printTree (Phi.normalize input) `shouldBe` Phi.printTree normalized
  describe "Prettify" $ do
    forM_ tests $ mapM_ $ \PhiTest{..} -> do
      it name $ do
        Phi.printTree input `shouldBe` dropWhileEnd isSpace prettified
