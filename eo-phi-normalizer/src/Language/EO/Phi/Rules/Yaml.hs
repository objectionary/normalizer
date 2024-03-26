{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-partial-fields #-}

module Language.EO.Phi.Rules.Yaml where

import Control.Lens ((+=))
import Control.Monad (guard)
import Control.Monad.State (State, evalState, gets)
import Data.Aeson (FromJSON (..), Options (sumEncoding), SumEncoding (UntaggedValue), genericParseJSON)
import Data.Aeson.Types (defaultOptions)
import Data.Coerce (coerce)
import Data.List (intercalate)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (fromMaybe)
import Data.String (IsString (..))
import Data.String.Interpolate (i)
import Data.Yaml qualified as Yaml
import GHC.Generics (Generic)
import Language.EO.Phi (printTree)
import Language.EO.Phi.Rules.Common (Context (insideFormation, outerFormations), NamedRule)
import Language.EO.Phi.Rules.Common qualified as Common
import Language.EO.Phi.Syntax.Abs

-- $setup
-- >>> :set -XOverloadedStrings
-- >>> :set -XOverloadedLists

instance FromJSON Object where parseJSON = fmap fromString . parseJSON
instance FromJSON Binding where parseJSON = fmap fromString . parseJSON
instance FromJSON MetaId where parseJSON = fmap MetaId . parseJSON
instance FromJSON Attribute where parseJSON = fmap fromString . parseJSON
instance FromJSON RuleAttribute where parseJSON = fmap fromString . parseJSON

instance FromJSON LabelId
instance FromJSON AlphaIndex

data RuleSet = RuleSet
  { title :: String
  , rules :: [Rule]
  }
  deriving (Generic, FromJSON, Show)

data RuleContext = RuleContext
  { global_object :: Maybe Object
  , current_object :: Maybe Object
  , current_attribute :: Maybe Attribute
  }
  deriving (Generic, FromJSON, Show)

data Rule = Rule
  { name :: String
  , description :: String
  , context :: Maybe RuleContext
  , pattern :: Object
  , result :: Object
  , when :: [Condition]
  , tests :: [RuleTest]
  }
  deriving (Generic, FromJSON, Show)

data RuleTest = RuleTest
  { name :: String
  , input :: Object
  , output :: [Object]
  }
  deriving (Generic, FromJSON, Show)

data AttrsInBindings = AttrsInBindings
  { attrs :: [RuleAttribute]
  , bindings :: [Binding]
  }
  deriving (Generic, Show, FromJSON)
data Condition
  = IsNF {nf :: Object}
  | IsNFInsideFormation {nf_inside_formation :: Object}
  | PresentAttrs {present_attrs :: AttrsInBindings}
  | AbsentAttrs {absent_attrs :: AttrsInBindings}
  | AttrNotEqual {not_equal :: (Attribute, Attribute)}
  | ApplyInSubformations {apply_in_subformations :: Bool}
  deriving (Generic, Show)
instance FromJSON Condition where
  parseJSON = genericParseJSON defaultOptions{sumEncoding = UntaggedValue}

parseRuleSetFromFile :: FilePath -> IO RuleSet
parseRuleSetFromFile = Yaml.decodeFileThrow

convertRule :: Rule -> Common.Rule
convertRule Rule{..} ctx obj = do
  contextSubsts <- matchContext ctx context
  let pattern' = applySubst contextSubsts pattern
      result' = applySubst contextSubsts result
  subst <- matchObject pattern' obj
  guard $ all (\cond -> checkCond ctx cond (contextSubsts <> subst)) when
  let result'' = applySubst (contextSubsts <> subst) result'
      -- TODO #152:30m what context should we pass to evaluate meta funcs?
      obj' = evaluateMetaFuncs obj result''
  guard $ not (objectHasMetavars obj')
  pure obj'

convertRuleNamed :: Rule -> NamedRule
convertRuleNamed rule = (rule.name, convertRule rule)

-- >>> matchContext (Context [] ["⟦ a ↦ ⟦ ⟧, x ↦ ξ.a ⟧"] (Label (LabelId "x"))) (Just (RuleContext Nothing (Just "⟦ !a ↦ !obj, !B ⟧") (Just "!a")))
-- [Subst {
--   objectMetas = [!obj -> 'ξ.a']
--   bindingsMetas = [!B -> 'a ↦ ⟦ ⟧']
--   attributeMetas = [!a -> 'x']
-- }]
matchContext :: Common.Context -> Maybe RuleContext -> [Subst]
matchContext Common.Context{} Nothing = [emptySubst]
matchContext Common.Context{..} (Just (RuleContext{..})) = do
  subst1 <- maybe [emptySubst] (`matchObject` globalObject) global_object
  subst2 <- maybe [emptySubst] ((`matchObject` thisObject) . applySubst subst1) current_object
  subst3 <- maybe [emptySubst] ((`matchAttr` currentAttr) . applySubstAttr (subst1 <> subst2)) current_attribute
  return (subst1 <> subst2 <> subst3)
 where
  globalObject = NonEmpty.last outerFormations
  thisObject = NonEmpty.head outerFormations

objectHasMetavars :: Object -> Bool
objectHasMetavars (Formation bindings) = any bindingHasMetavars bindings
objectHasMetavars (Application object bindings) = objectHasMetavars object || any bindingHasMetavars bindings
objectHasMetavars (ObjectDispatch object attr) = objectHasMetavars object || attrHasMetavars attr
objectHasMetavars GlobalObject = False
objectHasMetavars ThisObject = False
objectHasMetavars Termination = False
objectHasMetavars (MetaObject _) = True
objectHasMetavars (MetaFunction _ _) = True

bindingHasMetavars :: Binding -> Bool
bindingHasMetavars (AlphaBinding attr obj) = attrHasMetavars attr || objectHasMetavars obj
bindingHasMetavars (EmptyBinding attr) = attrHasMetavars attr
bindingHasMetavars (DeltaBinding _) = False
bindingHasMetavars DeltaEmptyBinding = False
bindingHasMetavars (LambdaBinding _) = False
bindingHasMetavars (MetaBindings _) = True
bindingHasMetavars (MetaDeltaBinding _) = True

attrHasMetavars :: Attribute -> Bool
attrHasMetavars Phi = False
attrHasMetavars Rho = False
attrHasMetavars Sigma = False
attrHasMetavars VTX = False
attrHasMetavars (Label _) = False
attrHasMetavars (Alpha _) = False
attrHasMetavars (MetaAttr _) = True

-- | Given a condition, and a substition from object matching
--   tells whether the condition matches the object
checkCond :: Common.Context -> Condition -> Subst -> Bool
checkCond ctx (IsNF obj) subst = Common.isNF ctx $ applySubst subst obj
checkCond ctx (IsNFInsideFormation obj) subst = Common.isNF ctx{insideFormation = True} $ applySubst subst obj
checkCond _ctx (PresentAttrs (AttrsInBindings attrs bindings)) subst = any (`hasAttr` substitutedBindings) substitutedAttrs
 where
  substitutedBindings = concatMap (applySubstBinding subst) bindings
  ruleToNormalAttr :: RuleAttribute -> Attribute
  ruleToNormalAttr (ObjectAttr a) = a
  -- Hack to be able to use applySubstAttr with RuleAttribute.
  -- Should not actually substitute anything anyway since they are not metavariables
  ruleToNormalAttr DeltaAttr = Label (LabelId "Δ")
  ruleToNormalAttr LambdaAttr = Label (LabelId "λ")
  normalToRuleAttr :: Attribute -> RuleAttribute
  normalToRuleAttr (Label (LabelId "Δ")) = DeltaAttr
  normalToRuleAttr (Label (LabelId "λ")) = LambdaAttr
  normalToRuleAttr a = ObjectAttr a
  substitutedAttrs = map (normalToRuleAttr . applySubstAttr subst . ruleToNormalAttr) attrs
checkCond ctx (AbsentAttrs s) subst = not $ checkCond ctx (PresentAttrs s) subst
checkCond _ctx (AttrNotEqual (a1, a2)) subst = applySubstAttr subst a1 /= applySubstAttr subst a2
checkCond ctx (ApplyInSubformations shouldApply) _subst
  | shouldApply = True
  | otherwise = not (insideFormation ctx)

hasAttr :: RuleAttribute -> [Binding] -> Bool
hasAttr attr = any (isAttr attr)
 where
  isAttr (ObjectAttr a) (AlphaBinding a' _) = a == a'
  isAttr (ObjectAttr a) (EmptyBinding a') = a == a'
  isAttr DeltaAttr (DeltaBinding _) = True
  isAttr DeltaAttr DeltaEmptyBinding = True
  isAttr LambdaAttr (LambdaBinding _) = True
  isAttr _ _ = False

-- input: ⟦ a ↦ ⟦ c ↦ ⟦ ⟧ ⟧, b ↦ ⟦ ⟧ ⟧.a

-- pattern:   ⟦ !a ↦ !n, !B ⟧.!a
-- result:    !n(ρ ↦ ⟦ !B ⟧)

-- match pattern input (get substitution):
--  !a = a
--  !n = ⟦ c ↦ ⟦ ⟧ ⟧
--  !B = b ↦ ⟦ ⟧

-- actual result (after applying substitution):
--  ⟦ c ↦ ⟦ ⟧ ⟧(ρ ↦ ⟦ b ↦ ⟦ ⟧ ⟧)

data Subst = Subst
  { objectMetas :: [(MetaId, Object)]
  , bindingsMetas :: [(MetaId, [Binding])]
  , attributeMetas :: [(MetaId, Attribute)]
  , bytesMetas :: [(MetaId, Bytes)]
  }
instance Show Subst where
  show Subst{..} =
    intercalate
      "\n"
      [ "Subst {"
      , "  objectMetas = [" <> showMappings objectMetas <> "]"
      , "  bindingsMetas = [" <> showMappings bindingsMetas <> "]"
      , "  attributeMetas = [" <> showMappings attributeMetas <> "]"
      , "  bytesMetas = [" <> showMappings bytesMetas <> "]"
      , "}"
      ]
   where
    showMappings metas = intercalate "; " $ map (\(MetaId metaId, obj) -> [i|#{metaId} -> '#{printTree obj}'|]) metas

instance Semigroup Subst where
  (<>) = mergeSubst

instance Monoid Subst where
  mempty = emptySubst

emptySubst :: Subst
emptySubst = Subst [] [] [] []

-- >>> putStrLn $ Language.EO.Phi.printTree (applySubst (Subst [("!n", "⟦ c ↦ ⟦ ⟧ ⟧")] [("!B", ["b ↦ ⟦ ⟧"])] [("!a", "a")]) "!n(ρ ↦ ⟦ !B ⟧)" :: Object)
-- ⟦ c ↦ ⟦ ⟧ ⟧ (ρ ↦ ⟦ b ↦ ⟦ ⟧ ⟧)
applySubst :: Subst -> Object -> Object
applySubst subst@Subst{..} = \case
  Formation bindings ->
    Formation (applySubstBindings subst bindings)
  Application obj bindings ->
    Application (applySubst subst obj) (applySubstBindings subst bindings)
  ObjectDispatch obj a ->
    ObjectDispatch (applySubst subst obj) (applySubstAttr subst a)
  GlobalObject -> GlobalObject
  ThisObject -> ThisObject
  obj@(MetaObject x) -> fromMaybe obj $ lookup x objectMetas
  obj -> obj

applySubstAttr :: Subst -> Attribute -> Attribute
applySubstAttr Subst{..} = \case
  attr@(MetaAttr x) -> fromMaybe attr $ lookup x attributeMetas
  attr -> attr

applySubstBindings :: Subst -> [Binding] -> [Binding]
applySubstBindings subst = concatMap (applySubstBinding subst)

applySubstBinding :: Subst -> Binding -> [Binding]
applySubstBinding subst@Subst{..} = \case
  AlphaBinding a obj ->
    [AlphaBinding (applySubstAttr subst a) (applySubst subst obj)]
  EmptyBinding a ->
    [EmptyBinding (applySubstAttr subst a)]
  DeltaBinding bytes -> [DeltaBinding (coerce bytes)]
  DeltaEmptyBinding -> [DeltaEmptyBinding]
  LambdaBinding bytes -> [LambdaBinding (coerce bytes)]
  b@(MetaBindings m) -> fromMaybe [b] (lookup m bindingsMetas)
  b@(MetaDeltaBinding m) -> maybe [b] (pure . DeltaBinding) (lookup m bytesMetas)

mergeSubst :: Subst -> Subst -> Subst
mergeSubst (Subst xs ys zs ws) (Subst xs' ys' zs' ws') =
  Subst (xs ++ xs') (ys ++ ys') (zs ++ zs') (ws ++ ws')

-- 1. need to implement applySubst' :: Subst -> Object -> Object
-- 2. complete the code
matchObject :: Object -> Object -> [Subst]
matchObject (Formation ps) (Formation bs) = matchBindings ps bs
matchObject (Application obj bindings) (Application obj' bindings') = do
  subst1 <- matchObject obj obj'
  subst2 <- matchBindings (applySubstBindings subst1 bindings) bindings'
  pure (subst1 <> subst2)
matchObject (ObjectDispatch pat a) (ObjectDispatch obj a') = do
  subst1 <- matchObject pat obj
  subst2 <- matchAttr (applySubstAttr subst1 a) a'
  pure (subst1 <> subst2)
matchObject (MetaObject m) obj =
  pure emptySubst{objectMetas = [(m, obj)]}
matchObject Termination Termination = [emptySubst]
matchObject ThisObject ThisObject = [emptySubst]
matchObject GlobalObject GlobalObject = [emptySubst]
matchObject _ _ = [] -- ? emptySubst ?

-- | Evaluate meta functions
-- given top-level context as an object
-- and an object
--
-- >>> evaluateMetaFuncs "⟦ a ↦ ⟦ ν ↦ ⟦ Δ ⤍ 03- ⟧ ⟧, b ↦ ⟦ ⟧ ⟧" "⟦ a ↦ ⟦ ν ↦ @T(⟦ a ↦ ⟦ ν ↦ ⟦ Δ ⤍ 03- ⟧ ⟧, b ↦ ⟦ ⟧ ⟧)  ⟧, b ↦ ⟦ ⟧ ⟧"
-- Formation [AlphaBinding (Label (LabelId "a")) (Formation [AlphaBinding VTX (Formation [DeltaBinding (Bytes "04-")])]),AlphaBinding (Label (LabelId "b")) (Formation [])]
evaluateMetaFuncs :: Object -> Object -> Object
evaluateMetaFuncs obj' obj =
  evalState
    (evaluateMetaFuncs' obj)
    MetaState{nuCount = Common.getMaxNu obj' + 1}

newtype MetaState = MetaState
  { nuCount :: Int
  }
  deriving (Generic)

evaluateMetaFuncs' :: Object -> State MetaState Object
evaluateMetaFuncs' (MetaFunction (MetaFunctionName "@T") _) = do
  nuCount' <- gets (Common.intToBytesObject . nuCount)
  #nuCount += 1
  pure nuCount'
evaluateMetaFuncs' (Formation bindings) = Formation <$> mapM evaluateMetaFuncsBinding bindings
evaluateMetaFuncs' (Application obj bindings) = Application <$> evaluateMetaFuncs' obj <*> mapM evaluateMetaFuncsBinding bindings
evaluateMetaFuncs' (ObjectDispatch obj a) = ObjectDispatch <$> evaluateMetaFuncs' obj <*> pure a
evaluateMetaFuncs' obj = pure obj

evaluateMetaFuncsBinding :: Binding -> State MetaState Binding
evaluateMetaFuncsBinding (AlphaBinding attr obj) = AlphaBinding attr <$> evaluateMetaFuncs' obj
evaluateMetaFuncsBinding binding = pure binding

matchBindings :: [Binding] -> [Binding] -> [Subst]
matchBindings [] [] = [emptySubst]
matchBindings [MetaBindings b] bindings =
  pure
    emptySubst
      { bindingsMetas = [(b, bindings)]
      }
matchBindings (p : ps) bs = do
  (bs', subst1) <- matchFindBinding p bs
  subst2 <- matchBindings (applySubstBindings subst1 ps) bs'
  pure (subst1 <> subst2)
matchBindings [] _ = []

-- >>> select [1,2,3,4]
-- [(1,[2,3,4]),(2,[1,3,4]),(3,[1,2,4]),(4,[1,2,3])]
select :: [a] -> [(a, [a])]
select [] = []
select [x] = [(x, [])]
select (x : xs) =
  (x, xs)
    : [ (y, x : ys)
      | (y, ys) <- select xs
      ]

matchFindBinding :: Binding -> [Binding] -> [([Binding], Subst)]
matchFindBinding p bindings =
  [ (leftover, subst)
  | (binding, leftover) <- select bindings
  , subst <- matchBinding p binding
  ]

matchBinding :: Binding -> Binding -> [Subst]
matchBinding MetaBindings{} _ = []
matchBinding (AlphaBinding a obj) (AlphaBinding a' obj') = do
  subst1 <- matchAttr a a'
  subst2 <- matchObject obj obj'
  pure (subst1 <> subst2)
matchBinding (MetaDeltaBinding m) (DeltaBinding bytes) = [emptySubst{bytesMetas = [(m, bytes)]}]
matchBinding (DeltaBinding bytes) (DeltaBinding bytes')
  | bytes == bytes' = [emptySubst]
matchBinding DeltaEmptyBinding DeltaEmptyBinding = [emptySubst]
matchBinding (EmptyBinding a1) (EmptyBinding a2) = matchAttr a1 a2
matchBinding (LambdaBinding f1) (LambdaBinding f2)
  | f1 == f2 = [emptySubst]
matchBinding _ _ = []

matchAttr :: Attribute -> Attribute -> [Subst]
matchAttr l r | l == r = [emptySubst]
matchAttr (MetaAttr metaId) attr =
  [ emptySubst
      { attributeMetas = [(metaId, attr)]
      }
  ]
matchAttr _ _ = []
