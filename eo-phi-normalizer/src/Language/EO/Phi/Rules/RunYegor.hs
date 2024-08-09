module Language.EO.Phi.Rules.RunYegor where

import Language.EO.Phi.Dataize.Context
import Language.EO.Phi.Rules.Common
import Language.EO.Phi.Rules.Yaml qualified as Yaml
import Language.EO.Phi.Syntax (printTree)
import Language.EO.Phi.Syntax.Abs
import System.IO.Unsafe (unsafePerformIO)

runWithYegorRules :: (Context -> Object -> Object) -> Object -> IO ()
runWithYegorRules f obj = putStrLn (printTree (f (defaultContext yegorRules obj) obj))

yegorRuleSet :: Yaml.RuleSet
{-# NOINLINE yegorRuleSet #-}
yegorRuleSet =
  unsafePerformIO $
    Yaml.parseRuleSetFromFile "eo-phi-normalizer/test/eo/phi/rules/yegor.yaml"

yegorRules :: [NamedRule]
yegorRules = map Yaml.convertRuleNamed (Yaml.rules yegorRuleSet)
