{-# LANGUAGE BlockArguments #-}

module Language.EO.YamlSpec where

import Language.EO.Test.YamlSpec qualified as Test
import Test.Hspec (Spec)

spec :: Spec
spec =
  Test.spec
    [ "test/eo/phi/rules/yegor.yaml"
    , "test/eo/phi/rules/streams.yaml"
    ]
