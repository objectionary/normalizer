{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TupleSections #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Language.EO.Rules.PhiPaperSpec where

import Control.Monad (forM_, guard)
import Data.Aeson (FromJSON)
import Data.Data (Data (toConstr))
import Data.List (intercalate)
import Data.List qualified as List
import Data.Yaml qualified as Yaml
import GHC.Generics (Generic)
import Language.EO.Phi.Rules.Common (ApplicationLimits (..), NamedRule, applyOneRule, defaultApplicationLimits, defaultContext, equalObject, intToBytes, objectSize)
import Language.EO.Phi.Rules.Yaml (convertRuleNamed, parseRuleSetFromFile, rules)
import Language.EO.Phi.Syntax (printTree)
import Language.EO.Phi.Syntax.Abs as Phi
import Test.Hspec
import Test.QuickCheck

arbitraryNonEmptyString :: Gen String
arbitraryNonEmptyString = do
  x <- elements ['a' .. 'z']
  n <- choose (1, 9 :: Int)
  return (x : show n)

instance Arbitrary Attribute where
  arbitrary =
    oneof
      [ pure Phi
      , pure Rho
      , pure Sigma
      , pure Vertex
      , Label <$> arbitrary
      ]

instance Arbitrary LabelId where
  arbitrary = LabelId <$> arbitraryNonEmptyString
  shrink = genericShrink
instance Arbitrary AlphaIndex where
  arbitrary = AlphaIndex <$> arbitraryNonEmptyString
instance Arbitrary Bytes where
  arbitrary = intToBytes <$> arbitrarySizedNatural
instance Arbitrary Phi.Function where
  arbitrary = Phi.Function <$> arbitraryNonEmptyString
instance Arbitrary Phi.MetaId where
  arbitrary = Phi.MetaId . ("!" ++) <$> arbitraryNonEmptyString
instance Arbitrary Phi.MetaFunctionName where
  arbitrary = Phi.MetaFunctionName . ("@" ++) <$> arbitraryNonEmptyString

instance Arbitrary Binding where
  arbitrary =
    oneof
      [ EmptyBinding . Label <$> arbitrary
      , do
          attr <- arbitrary
          obj <- case attr of
            Vertex ->
              Formation <$> do
                bytes <- arbitrary
                return [DeltaBinding bytes]
            _ -> arbitrary
          return (AlphaBinding attr obj)
      , DeltaBinding <$> arbitrary
      , LambdaBinding <$> arbitrary
      , pure DeltaEmptyBinding
      ]
  shrink (AlphaBinding Vertex _) = [] -- do not shrink vertex bindings
  shrink (AlphaBinding attr obj) = AlphaBinding attr <$> shrink obj
  shrink _ = [] -- do not shrink deltas and lambdas

instance Arbitrary Object where
  arbitrary = sized $ \n -> do
    let arbitraryBinding = resize (n `div` 2) arbitrary
        arbitraryAttr = resize (n `div` 2) arbitrary
        arbitraryObj = resize (n `div` 2) arbitrary
        sameAttr (AlphaBinding attr1 _) (AlphaBinding attr2 _) = attr1 == attr2
        sameAttr (EmptyBinding attr1) (EmptyBinding attr2) = attr1 == attr2
        sameAttr b1 b2 = toConstr b1 == toConstr b2
        arbitraryBindings = List.nubBy sameAttr <$> listOf arbitraryBinding
        arbitraryAlphaLabelBinding =
          resize (n `div` 2) $
            AlphaBinding <$> (Label <$> arbitrary) <*> arbitrary
        arbitraryAlphaLabelBindings = List.nubBy sameAttr <$> listOf arbitraryAlphaLabelBinding
    if n > 0
      then
        oneof
          [ Formation <$> arbitraryBindings
          , liftA2 Application arbitraryObj arbitraryAlphaLabelBindings
          , liftA2 ObjectDispatch arbitraryObj arbitraryAttr
          , ObjectDispatch GlobalObject <$> arbitraryAttr
          , pure ThisObject
          , pure Termination
          ]
      else pure $ Formation []
  shrink = genericShrink

data CriticalPair = CriticalPair
  { sourceTerm :: Object
  , criticalPair :: (Object, Object)
  , rulesApplied :: (String, String)
  }

genCriticalPair :: [NamedRule] -> Gen CriticalPair
genCriticalPair rules = do
  (sourceTerm, results) <- fan `suchThat` \(_, rs) -> length rs > 1
  case results of
    (rule1, x) : (rule2, y) : _ ->
      return
        CriticalPair
          { sourceTerm = sourceTerm
          , criticalPair = (x, y)
          , rulesApplied = (rule1, rule2)
          }
    _ -> error "IMPOSSIBLE HAPPENED"
 where
  fan = do
    obj <- Formation . List.nubBy sameAttr <$> listOf arbitrary
    return (obj, applyOneRule (defaultContext rules obj) obj)

  sameAttr (AlphaBinding attr1 _) (AlphaBinding attr2 _) = attr1 == attr2
  sameAttr (EmptyBinding attr1) (EmptyBinding attr2) = attr1 == attr2
  sameAttr b1 b2 = toConstr b1 == toConstr b2

findCriticalPairs :: [NamedRule] -> Object -> [CriticalPair]
findCriticalPairs rules obj = do
  let ctx = defaultContext rules obj
  let results = applyOneRule ctx obj
  guard (length results > 1)
  case results of
    (rule1, x) : (rule2, y) : _ ->
      return
        CriticalPair
          { sourceTerm = obj
          , criticalPair = (x, y)
          , rulesApplied = (rule1, rule2)
          }
    _ -> error "IMPOSSIBLE HAPPENED"

shrinkCriticalPair :: [NamedRule] -> CriticalPair -> [CriticalPair]
shrinkCriticalPair rules CriticalPair{..} =
  [ CriticalPair
    { sourceTerm = sourceTerm'
    , criticalPair = (x, y)
    , rulesApplied = (rule1, rule2)
    }
  | sourceTerm'@Formation{} <- shrink sourceTerm
  , (rule1, x) : (rule2, y) : _ <- [applyOneRule (defaultContext rules sourceTerm') sourceTerm']
  ]

type SearchLimits = ApplicationLimits

descendantsN :: SearchLimits -> [NamedRule] -> [Object] -> [[Object]]
descendantsN ApplicationLimits{..} rules objs
  | maxDepth <= 0 = [objs]
  | otherwise =
      objs
        : descendantsN
          ApplicationLimits{maxDepth = maxDepth - 1, ..}
          rules
          [ obj'
          | obj <- objs
          , objectSize obj < maxTermSize
          , (_name, obj') <- applyOneRule (defaultContext rules obj) obj
          ]

-- | Pair items from two lists with all combinations,
-- but order them lexicographically according to their original indices.
-- This makes sure that we check pairs that are early in both lists
-- before checking pairs later.
--
-- >>> pairByLevel [1..3] "abc"
-- [(1,'a'),(2,'a'),(1,'b'),(2,'b'),(3,'a'),(3,'b'),(1,'c'),(2,'c'),(3,'c')]
--
-- Works for infinite lists as well:
--
-- >>> take 10 $ pairByLevel [1..] [1..]
-- [(1,1),(2,1),(1,2),(2,2),(3,1),(3,2),(1,3),(2,3),(3,3),(4,1)]
pairByLevel :: [a] -> [b] -> [(a, b)]
pairByLevel = go [] []
 where
  go :: [a] -> [b] -> [a] -> [b] -> [(a, b)]
  go _xs _ys [] _ = []
  go _xs _ys _ [] = []
  go xs ys (a : as) (b : bs) =
    map (a,) ys
      ++ map (,b) xs
      ++ (a, b)
      : go (xs ++ [a]) (ys ++ [b]) as bs

-- | Find intersection of two lists, represented as lists of groups.
-- Intersection of groups with lower indicies is considered before
-- moving on to groups with larger index.
intersectByLevelBy :: (a -> a -> Bool) -> [[a]] -> [[a]] -> [a]
intersectByLevelBy eq xs ys =
  concat
    [ List.intersectBy eq l r
    | (l, r) <- pairByLevel xs ys
    ]

confluentCriticalPairN :: SearchLimits -> [NamedRule] -> CriticalPair -> Bool
confluentCriticalPairN limits rules CriticalPair{..} =
  -- should normalize the VTXs before checking
  -- NOTE: we are using intersectByLevelBy to ensure that we first check
  -- terms generated after one rule application, then include terms after two rules applications, etc.
  -- This helps find the confluence points without having to compute all terms up to depth N,
  -- \**if** the term is confluent.
  -- We expect confluence to be satisfied at depth 1 in practice for most terms,
  -- since most critical pairs apply non-overlapping rules.
  -- However, if the term is NOT confluent, we will still check all options, which may take some time.
  not (null (intersectByLevelBy equalObject (descendantsN limits rules [x]) (descendantsN limits rules [y])))
 where
  (x, y) = criticalPair

instance Show CriticalPair where
  show CriticalPair{criticalPair = (x, y), rulesApplied = (rule1, rule2), ..} =
    intercalate
      "\n"
      [ "Source term:"
      , "  " <> printTree sourceTerm
      , "Critical pair:"
      , "  Using rule '" <> rule1 <> "': " <> printTree x
      , "  Using rule '" <> rule2 <> "': " <> printTree y
      ]

defaultSearchLimits :: Int -> SearchLimits
defaultSearchLimits = defaultApplicationLimits

confluent :: [NamedRule] -> Property
confluent rulesFromYaml = withMaxSuccess 1_000 $
  forAllShrink (resize 40 $ genCriticalPair rulesFromYaml) (shrinkCriticalPair rulesFromYaml) $
    \pair@CriticalPair{..} ->
      within 100_000 $ -- 0.1 second timeout per test
        confluentCriticalPairN (defaultSearchLimits (objectSize sourceTerm)) rulesFromYaml pair

confluentOnObject :: [NamedRule] -> Object -> Bool
confluentOnObject rules obj = all (confluentCriticalPairN (defaultSearchLimits (objectSize obj)) rules) (findCriticalPairs rules obj)

data ConfluenceTests = ConfluenceTests
  { title :: String
  , tests :: [Object]
  }
  deriving (Generic, FromJSON, Show)

parseTests :: String -> IO ConfluenceTests
parseTests = Yaml.decodeFileThrow

spec :: Spec
spec = do
  ruleset <- runIO $ parseRuleSetFromFile "./test/eo/phi/rules/yegor.yaml"
  let rulesFromYaml = map convertRuleNamed (rules ruleset)
  inputs <- runIO $ parseTests "./test/eo/phi/confluence.yaml"
  describe "Yegor's rules" $ do
    it "Are confluent (via QuickCheck)" (confluent rulesFromYaml)
    describe
      "Are confluent (regression tests)"
      $ forM_ (tests inputs)
      $ \input -> do
        it (printTree input) (input `shouldSatisfy` confluentOnObject rulesFromYaml)
