{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

module Language.EO.Phi.Rules.Common where

import Control.Applicative (Alternative ((<|>)), asum)
import Data.List (nubBy, sortOn)
import Data.List.NonEmpty (NonEmpty (..), (<|))
import Data.List.NonEmpty qualified as NonEmpty
import Data.String (IsString (..))
import Language.EO.Phi.Syntax.Abs
import Language.EO.Phi.Syntax.Lex (Token)
import Language.EO.Phi.Syntax.Par
import Numeric (readHex, showHex)

-- $setup
-- >>> :set -XOverloadedStrings
-- >>> :set -XOverloadedLists
-- >>> import Language.EO.Phi.Syntax

instance IsString Program where fromString = unsafeParseWith pProgram
instance IsString Object where fromString = unsafeParseWith pObject
instance IsString Binding where fromString = unsafeParseWith pBinding
instance IsString Attribute where fromString = unsafeParseWith pAttribute
instance IsString RuleAttribute where fromString = unsafeParseWith pRuleAttribute
instance IsString PeeledObject where fromString = unsafeParseWith pPeeledObject
instance IsString ObjectHead where fromString = unsafeParseWith pObjectHead

parseWith :: ([Token] -> Either String a) -> String -> Either String a
parseWith parser input = parser tokens
 where
  tokens = myLexer input

-- | Parse a 'Object' from a 'String'.
-- May throw an 'error` if input has a syntactical or lexical errors.
unsafeParseWith :: ([Token] -> Either String a) -> String -> a
unsafeParseWith parser input =
  case parseWith parser input of
    Left parseError -> error parseError
    Right object -> object

type NamedRule = (String, Rule)

data Context = Context
  { allRules :: [NamedRule]
  , outerFormations :: NonEmpty Object
  , currentAttr :: Attribute
  , insideFormation :: Bool
  -- ^ Temporary hack for applying Ksi and Phi rules when dataizing
  }

defaultContext :: [NamedRule] -> Object -> Context
defaultContext rules obj =
  Context
    { allRules = rules
    , outerFormations = NonEmpty.singleton obj
    , currentAttr = Sigma
    , insideFormation = False
    }

-- | A rule tries to apply a transformation to the root object, if possible.
type Rule = Context -> Object -> [Object]

applyOneRuleAtRoot :: Context -> Object -> [(String, Object)]
applyOneRuleAtRoot ctx@Context{..} obj =
  nubBy
    equalObjectNamed
    [ (ruleName, obj')
    | (ruleName, rule) <- allRules
    , obj' <- rule ctx obj
    ]

extendContextWith :: Object -> Context -> Context
extendContextWith obj ctx =
  ctx
    { outerFormations = obj <| outerFormations ctx
    }

withSubObject :: (Context -> Object -> [(String, Object)]) -> Context -> Object -> [(String, Object)]
withSubObject f ctx root =
  f ctx root
    <|> case root of
      Formation bindings ->
        propagateName1 Formation <$> withSubObjectBindings f ((extendContextWith root ctx){insideFormation = True}) bindings
      Application obj bindings ->
        asum
          [ propagateName2 Application <$> withSubObject f ctx obj <*> pure bindings
          , propagateName1 (Application obj) <$> withSubObjectBindings f ctx bindings
          ]
      ObjectDispatch obj a -> propagateName2 ObjectDispatch <$> withSubObject f ctx obj <*> pure a
      GlobalObject{} -> []
      ThisObject{} -> []
      Termination -> []
      MetaObject _ -> []
      MetaFunction _ _ -> []

-- | Given a unary function that operates only on plain objects,
-- converts it to a function that operates on name objects
propagateName1 :: (a -> b) -> (name, a) -> (name, b)
propagateName1 f (name, obj) = (name, f obj)

-- | Given a binary function that operates only on plain objects,
-- converts it to a function that operates on name objects
propagateName2 :: (a -> b -> c) -> (name, a) -> b -> (name, c)
propagateName2 f (name, obj) bs = (name, f obj bs)

withSubObjectBindings :: (Context -> Object -> [(String, Object)]) -> Context -> [Binding] -> [(String, [Binding])]
withSubObjectBindings _ _ [] = []
withSubObjectBindings f ctx (b : bs) =
  asum
    [ [(name, b' : bs) | (name, b') <- withSubObjectBinding f ctx b]
    , [(name, b : bs') | (name, bs') <- withSubObjectBindings f ctx bs]
    ]

withSubObjectBinding :: (Context -> Object -> [(String, Object)]) -> Context -> Binding -> [(String, Binding)]
withSubObjectBinding f ctx = \case
  AlphaBinding a obj -> propagateName1 (AlphaBinding a) <$> withSubObject f (ctx{currentAttr = a}) obj
  EmptyBinding{} -> []
  DeltaBinding{} -> []
  DeltaEmptyBinding{} -> []
  MetaDeltaBinding{} -> []
  LambdaBinding{} -> []
  MetaBindings _ -> []

applyOneRule :: Context -> Object -> [(String, Object)]
applyOneRule = withSubObject applyOneRuleAtRoot

isNF :: Context -> Object -> Bool
isNF ctx = null . applyOneRule ctx

-- | Apply rules until we get a normal form.
--
-- >>> mapM_ (putStrLn . Language.EO.Phi.printTree) (applyRules (Context [rule6] ["⟦ a ↦ ⟦ b ↦ ⟦ ⟧ ⟧.b ⟧"]) "⟦ a ↦ ⟦ b ↦ ⟦ ⟧ ⟧.b ⟧.a")
applyRules :: Context -> Object -> [Object]
applyRules ctx obj = applyRulesWith (defaultApplicationLimits (objectSize obj)) ctx obj

data ApplicationLimits = ApplicationLimits
  { maxDepth :: Int
  , maxTermSize :: Int
  }

defaultApplicationLimits :: Int -> ApplicationLimits
defaultApplicationLimits sourceTermSize =
  ApplicationLimits
    { maxDepth = 13
    , maxTermSize = sourceTermSize * 10
    }

objectSize :: Object -> Int
objectSize = \case
  Formation bindings -> 1 + sum (map bindingSize bindings)
  Application obj bindings -> 1 + objectSize obj + sum (map bindingSize bindings)
  ObjectDispatch obj _attr -> 1 + objectSize obj
  GlobalObject -> 1
  ThisObject -> 1
  Termination -> 1
  MetaObject{} -> 1 -- should be impossible
  MetaFunction{} -> 1 -- should be impossible

bindingSize :: Binding -> Int
bindingSize = \case
  AlphaBinding _attr obj -> objectSize obj
  EmptyBinding _attr -> 1
  DeltaBinding _bytes -> 1
  DeltaEmptyBinding -> 1
  LambdaBinding _lam -> 1
  MetaDeltaBinding{} -> 1 -- should be impossible
  MetaBindings{} -> 1 -- should be impossible

-- | A variant of `applyRules` with a maximum application depth.
applyRulesWith :: ApplicationLimits -> Context -> Object -> [Object]
applyRulesWith limits@ApplicationLimits{..} ctx obj
  | maxDepth <= 0 = [obj]
  | isNF ctx obj = [obj]
  | otherwise =
      nubBy
        equalObject
        [ obj''
        | (_ruleName, obj') <- applyOneRule ctx obj
        , objectSize obj' < maxTermSize
        , obj'' <- applyRulesWith limits{maxDepth = maxDepth - 1} ctx obj'
        ]

equalProgram :: Program -> Program -> Bool
equalProgram (Program bindings1) (Program bindings2) = equalObject (Formation bindings1) (Formation bindings2)

equalObject :: Object -> Object -> Bool
equalObject (Formation bindings1) (Formation bindings2) =
  length bindings1 == length bindings2 && equalBindings bindings1 bindings2
equalObject (Application obj1 bindings1) (Application obj2 bindings2) =
  equalObject obj1 obj2 && equalBindings bindings1 bindings2
equalObject (ObjectDispatch obj1 attr1) (ObjectDispatch obj2 attr2) =
  equalObject obj1 obj2 && attr1 == attr2
equalObject obj1 obj2 = obj1 == obj2

equalObjectNamed :: (String, Object) -> (String, Object) -> Bool
equalObjectNamed x y = snd x `equalObject` snd y

equalBindings :: [Binding] -> [Binding] -> Bool
equalBindings bindings1 bindings2 = and (zipWith equalBinding (sortOn attr bindings1) (sortOn attr bindings2))
 where
  attr (AlphaBinding a _) = a
  attr (EmptyBinding a) = a
  attr (DeltaBinding _) = Label (LabelId "Δ")
  attr DeltaEmptyBinding = Label (LabelId "Δ")
  attr (MetaDeltaBinding _) = Label (LabelId "Δ")
  attr (LambdaBinding _) = Label (LabelId "λ")
  attr (MetaBindings metaId) = MetaAttr metaId

equalBinding :: Binding -> Binding -> Bool
equalBinding (AlphaBinding Vertex _) (AlphaBinding Vertex _) = True -- TODO #166:15min Renumerate vertices uniformly instead of ignoring them
equalBinding (AlphaBinding attr1 obj1) (AlphaBinding attr2 obj2) = attr1 == attr2 && equalObject obj1 obj2
-- Ignore deltas for now while comparing since different normalization paths can lead to different vertex data
-- TODO #120:30m normalize the deltas instead of ignoring since this actually suppresses problems
equalBinding (DeltaBinding _) (DeltaBinding _) = True
equalBinding b1 b2 = b1 == b2

-- | Apply the rules until the object is normalized, preserving the history (chain) of applications.
applyRulesChain :: Context -> Object -> [[(String, Object)]]
applyRulesChain ctx obj = applyRulesChainWith (defaultApplicationLimits (objectSize obj)) ctx obj

-- | A variant of `applyRulesChain` with a maximum application depth.
applyRulesChainWith :: ApplicationLimits -> Context -> Object -> [[(String, Object)]]
applyRulesChainWith limits@ApplicationLimits{..} ctx obj
  | maxDepth <= 0 = [[("Max depth hit", obj)]]
  | isNF ctx obj = [[("Normal form", obj)]]
  | otherwise =
      [ (ruleName, obj) : chain
      | (ruleName, obj') <- applyOneRule ctx obj
      , objectSize obj' < maxTermSize
      , chain <- applyRulesChainWith limits{maxDepth = maxDepth - 1} ctx obj'
      ]

-- * Helpers

-- | Lookup a binding by the attribute name.
lookupBinding :: Attribute -> [Binding] -> Maybe Object
lookupBinding _ [] = Nothing
lookupBinding a (AlphaBinding a' object : bindings)
  | a == a' = Just object
  | otherwise = lookupBinding a bindings
lookupBinding _ _ = Nothing

objectBindings :: Object -> [Binding]
objectBindings (Formation bs) = bs
objectBindings (Application obj bs) = objectBindings obj ++ bs
objectBindings (ObjectDispatch obj _attr) = objectBindings obj
objectBindings _ = []

intToBytes :: Int -> Bytes
intToBytes n = Bytes $ insertDashes $ pad $ showHex n ""
 where
  pad s = (if even (length s) then "" else "0") ++ s
  insertDashes s
    | length s <= 2 = s ++ "-"
    | otherwise =
        let go = \case
              [] -> []
              [x] -> [x]
              [x, y] -> [x, y, '-']
              (x : y : xs) -> x : y : '-' : go xs
         in go s

-- | Assuming the bytes are well-formed (otherwise crashes)
bytesToInt :: Bytes -> Int
bytesToInt (Bytes (filter (/= '-') . dropWhile (== '0') -> bytes))
  | null bytes = 0
  | otherwise = fst $ head $ readHex bytes

minNu :: Int
minNu = -1

class HasMaxNu a where
  -- | get maximum vertex index
  --
  -- >>> getMaxNu @Object "⟦ a ↦ ⟦ ν ↦ ⟦ Δ ⤍ 03- ⟧ ⟧, b ↦ ⟦ ⟧ ⟧"
  -- 3
  getMaxNu :: a -> Int

instance HasMaxNu Program where
  getMaxNu :: Program -> Int
  getMaxNu (Program bindings) = getMaxNu (Formation bindings)

instance HasMaxNu Object where
  getMaxNu :: Object -> Int
  getMaxNu = \case
    Formation bindings -> maximum (minNu : (getMaxNu <$> bindings))
    Application obj bindings -> maximum (minNu : getMaxNu obj : (getMaxNu <$> bindings))
    ObjectDispatch obj _ -> getMaxNu obj
    _ -> minNu

instance HasMaxNu Binding where
  getMaxNu :: Binding -> Int
  getMaxNu = \case
    AlphaBinding Vertex (Formation [DeltaBinding (Bytes bs)]) ->
      case readHex [x | x <- bs, x /= '-'] of
        [(val, "")] -> val
        _ -> error "Vertex number is incorrect"
    AlphaBinding _ obj -> getMaxNu obj
    _ -> minNu

intToBytesObject :: Int -> Object
intToBytesObject n = Formation [DeltaBinding $ intToBytes n]

nuCountAsDataObj :: Object -> Object
nuCountAsDataObj = intToBytesObject . getMaxNu
