{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Language.EO.YamlSpec where

import Control.Monad (forM_)
import Language.EO.Phi.Dataize.Context (defaultContext)
import Language.EO.Phi.Rules.Common (applyOneRule)
import Language.EO.Phi.Rules.Yaml (Rule (..), RuleSet (..), RuleTest (..), RuleTestOption (..), convertRuleNamed)
import Test.EO.Yaml
import Test.Hspec

spec :: Spec
spec = describe "User-defined rules unit tests" do
  forM_ testPaths $ \path -> do
    ruleset <- runIO $ fileTests path
    describe ruleset.title do
      forM_ ruleset.rules $ \rule -> do
        describe rule.name do
          forM_ rule.tests $ \ruleTest -> do
            it ruleTest.name $
              let rule' = convertRuleNamed rule
                  resultOneStep = applyOneRule (defaultContext [rule'] ruleTest.input) ruleTest.input
                  normalizationResult = maybe resultOneStep (\lst -> if TakeOne True `elem` lst then take 1 resultOneStep else resultOneStep) ruleTest.options
                  expected = ruleTest.output
               in map snd normalizationResult `shouldBe` expected
 where
  testPaths =
    [ "test/eo/phi/rules/yegor.yaml"
    , "test/eo/phi/rules/streams.yaml"
    ]
