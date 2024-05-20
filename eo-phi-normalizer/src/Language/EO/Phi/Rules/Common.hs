{-# HLINT ignore "Use &&" #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

module Language.EO.Phi.Rules.Common where

import Control.Applicative (Alternative ((<|>)), asum)
import Control.Arrow (Arrow (first))
import Control.Monad
import Data.Binary qualified as Binary
import Data.ByteString.Lazy qualified as ByteString
import Data.Char (toUpper)
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
  , dataizePackage :: Bool
  -- ^ Temporary flag to only dataize Package attributes for the top-level formation.
  }

sameContext :: Context -> Context -> Bool
sameContext ctx1 ctx2 =
  and
    [ outerFormations ctx1 == outerFormations ctx2
    , currentAttr ctx1 == currentAttr ctx2
    ]

defaultContext :: [NamedRule] -> Object -> Context
defaultContext rules obj =
  Context
    { allRules = rules
    , outerFormations = NonEmpty.singleton obj
    , currentAttr = Phi
    , insideFormation = False
    , dataizePackage = True
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

isEmptyBinding :: Binding -> Bool
isEmptyBinding EmptyBinding{} = True
isEmptyBinding DeltaEmptyBinding{} = True
isEmptyBinding _ = False

withSubObject :: (Context -> Object -> [(String, Object)]) -> Context -> Object -> [(String, Object)]
withSubObject f ctx root =
  f ctx root
    <|> case root of
      Formation bindings
        | not (any isEmptyBinding bindings) -> propagateName1 Formation <$> withSubObjectBindings f ((extendContextWith root ctx){insideFormation = True}) bindings
        | otherwise -> []
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
      MetaSubstThis _ _ -> []

-- | Given a unary function that operates only on plain objects,
-- converts it to a function that operates on named objects
propagateName1 :: (a -> b) -> (name, a) -> (name, b)
propagateName1 f (name, obj) = (name, f obj)

-- | Given a binary function that operates only on plain objects,
-- converts it to a function that operates on named objects
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
  MetaSubstThis{} -> 1 -- should be impossible

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
        , obj'' <-
            if objectSize obj' < maxTermSize
              then applyRulesWith limits{maxDepth = maxDepth - 1} ctx obj'
              else [obj']
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
equalBinding (AlphaBinding attr1 obj1) (AlphaBinding attr2 obj2) = attr1 == attr2 && equalObject obj1 obj2
equalBinding b1 b2 = b1 == b2

-- * Chain variants

newtype Chain log result = Chain
  {runChain :: Context -> [([(String, log)], result)]}
  deriving (Functor)

type NormalizeChain = Chain Object
type DataizeChain = Chain (Either Object Bytes)

instance Applicative (Chain a) where
  pure x = Chain (const [([], x)])
  (<*>) = ap

instance Monad (Chain a) where
  return = pure
  Chain dx >>= f = Chain $ \ctx ->
    [ (steps <> steps', y)
    | (steps, x) <- dx ctx
    , (steps', y) <- runChain (f x) ctx
    ]

instance MonadFail (Chain a) where
  fail _msg = Chain (const [])

logStep :: String -> info -> Chain info ()
logStep msg info = Chain $ const [([(msg, info)], ())]

choose :: [a] -> Chain log a
choose xs = Chain $ \_ctx -> [(mempty, x) | x <- xs]

msplit :: Chain log a -> Chain log (Maybe (a, Chain log a))
msplit (Chain m) = Chain $ \ctx ->
  case m ctx of
    [] -> runChain (return Nothing) ctx
    (logs, x) : xs -> [(logs, Just (x, Chain (const xs)))]

transformLogs :: (log1 -> log2) -> Chain log1 a -> Chain log2 a
transformLogs f (Chain normChain) = Chain $ map (first (map (fmap f))) . normChain

transformNormLogs :: NormalizeChain a -> DataizeChain a
transformNormLogs = transformLogs Left

getContext :: Chain a Context
getContext = Chain $ \ctx -> [([], ctx)]

withContext :: Context -> Chain log a -> Chain log a
withContext = modifyContext . const

modifyContext :: (Context -> Context) -> Chain log a -> Chain log a
modifyContext g (Chain f) = Chain (f . g)

applyRulesChain' :: Context -> Object -> [([(String, Object)], Object)]
applyRulesChain' ctx obj = applyRulesChainWith' (defaultApplicationLimits (objectSize obj)) ctx obj

-- | Apply the rules until the object is normalized, preserving the history (chain) of applications.
applyRulesChain :: Object -> NormalizeChain Object
applyRulesChain obj = applyRulesChainWith (defaultApplicationLimits (objectSize obj)) obj

applyRulesChainWith' :: ApplicationLimits -> Context -> Object -> [([(String, Object)], Object)]
applyRulesChainWith' limits ctx obj = runChain (applyRulesChainWith limits obj) ctx

-- | A variant of `applyRulesChain` with a maximum application depth.
applyRulesChainWith :: ApplicationLimits -> Object -> NormalizeChain Object
applyRulesChainWith limits@ApplicationLimits{..} obj
  | maxDepth <= 0 = do
      logStep "Max depth hit" obj
      return obj
  | otherwise = do
      ctx <- getContext
      if isNF ctx obj
        then do
          logStep "Normal form" obj
          return obj
        else do
          (ruleName, obj') <- choose (applyOneRule ctx obj)
          logStep ruleName obj'
          if objectSize obj' < maxTermSize
            then applyRulesChainWith limits{maxDepth = maxDepth - 1} obj'
            else do
              logStep "Max term size hit" obj'
              return obj'

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

padLeft :: Int -> [Char] -> [Char]
padLeft n s = replicate (n - length s) '0' ++ s

normalizeBytes :: String -> String
normalizeBytes = map toUpper . insertDashes . padLeft 2
 where
  insertDashes s
    | length s <= 2 = s ++ "-"
    | otherwise =
        let go = \case
              [] -> []
              [x] -> [x]
              [x, y] -> [x, y]
              (x : y : xs) -> x : y : '-' : go xs
         in go s

intToBytes :: Int -> Bytes
intToBytes n = Bytes $ normalizeBytes $ foldMap (padLeft 2 . (`showHex` "")) $ ByteString.unpack $ Binary.encode n

-- | Assuming the bytes are well-formed (otherwise crashes)
bytesToInt :: Bytes -> Int
bytesToInt (Bytes (filter (/= '-') . dropWhile (== '0') -> bytes))
  | null bytes = 0
  | otherwise = fst $ head $ readHex bytes

boolToBytes :: Bool -> Bytes
boolToBytes True = intToBytes 1
boolToBytes False = intToBytes 0

bytesToBool :: Bytes -> Bool
bytesToBool (Bytes "00-") = False
bytesToBool _ = True -- TODO: verify that anything (not just 01-) can be interpreted as true

stringToBytes :: String -> Bytes
stringToBytes s = Bytes $ normalizeBytes $ foldMap (padLeft 2 . (`showHex` "") . fromEnum) s

bytesToString :: Bytes -> String
bytesToString (Bytes bytes) = map (toEnum . fst . head . readHex) $ words (map dashToSpace bytes)
 where
  dashToSpace '-' = ' '
  dashToSpace c = c

-- It is called "float" in EO, but it actually occupies 8 bytes so it's a double
floatToBytes :: Double -> Bytes
floatToBytes f = Bytes $ normalizeBytes $ foldMap (padLeft 2 . (`showHex` "")) $ ByteString.unpack $ Binary.encode f

bytesToFloat :: Bytes -> Double
bytesToFloat (Bytes bytes) = Binary.decode $ ByteString.pack $ map (fst . head . readHex) $ words (map dashToSpace bytes)
 where
  dashToSpace '-' = ' '
  dashToSpace c = c
