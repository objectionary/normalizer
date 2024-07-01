{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Redundant fmap" #-}

module Language.EO.Phi.Dataize where

import Data.Bits
import Data.HashSet qualified as HashSet
import Data.List (singleton)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (listToMaybe)
import Language.EO.Phi (printTree)
import Language.EO.Phi.Rules.Common
import Language.EO.Phi.Rules.Fast (fastYegorInsideOut)
import Language.EO.Phi.Rules.Yaml (substThis)
import Language.EO.Phi.Syntax.Abs
import PyF (fmt)
import System.IO.Unsafe (unsafePerformIO)

-- | Perform one step of dataization to the object (if possible).
dataizeStep :: Context -> Object -> (Context, Either Object Bytes)
dataizeStep ctx obj = snd $ head $ runChain (dataizeStepChain obj) ctx -- FIXME: head is bad

dataizeStep' :: Context -> Object -> Either Object Bytes
dataizeStep' ctx obj = snd (dataizeStep ctx obj)

-- | State of evaluation is not needed yet, but it might be in the future
type EvaluationState = ()

-- | Recursively perform normalization and dataization until we get bytes in the end.
dataizeRecursively :: Context -> Object -> Either Object Bytes
dataizeRecursively ctx obj = snd $ dataizeRecursivelyChain' ctx obj

dataizeStepChain' :: Context -> Object -> ([LogEntry (Either Object Bytes)], Either Object Bytes)
dataizeStepChain' ctx obj = snd <$> head (runChain (dataizeStepChain obj) ctx) -- FIXME: head is bad

-- | Perform one step of dataization to the object (if possible), reporting back individiual steps.
dataizeStepChain :: Object -> DataizeChain (Context, Either Object Bytes)
dataizeStepChain obj@(Formation bs)
  | Just (DeltaBinding bytes) <- listToMaybe [b | b@(DeltaBinding _) <- bs]
  , not hasEmpty = do
      logStep "Found bytes" (Right bytes)
      ctx <- getContext
      return (ctx, Right bytes)
  | Just (LambdaBinding (Function funcName)) <- listToMaybe [b | b@(LambdaBinding _) <- bs]
  , not hasEmpty = do
      logStep ("Evaluating lambda '" <> funcName <> "'") (Left obj)
      msplit (evaluateBuiltinFunChain funcName obj ()) >>= \case
        Nothing -> do
          ctx <- getContext
          return (ctx, Left obj)
        Just ((obj', _state), _alts) -> do
          ctx <- getContext
          return (ctx, Left obj')
  | Just (AlphaBinding Phi decoratee) <- listToMaybe [b | b@(AlphaBinding Phi _) <- bs]
  , not hasEmpty = do
      let decoratee' = substThis obj decoratee
      logStep "Dataizing inside phi" (Left decoratee')
      ctx <- getContext
      let extendedContext = (extendContextWith obj ctx){currentAttr = Phi}
      return (extendedContext, Left decoratee')
  | otherwise = do
      logStep "No change to formation" (Left obj)
      ctx <- getContext
      return (ctx, Left obj)
 where
  isEmpty (EmptyBinding _) = True
  isEmpty DeltaEmptyBinding = True
  isEmpty _ = False
  hasEmpty = any isEmpty bs
-- IMPORTANT: dataize the object being copied IF normalization is stuck on it!
dataizeStepChain (Application obj bindings) = incLogLevel $ do
  logStep "Dataizing inside application" (Left obj)
  modifyContext (\c -> c{dataizePackage = False}) $ do
    (ctx, obj') <- dataizeStepChain obj
    case obj' of
      Left obj'' -> return (ctx, Left (obj'' `Application` bindings))
      Right bytes -> return (ctx, Left (Formation [DeltaBinding bytes] `Application` bindings))
-- IMPORTANT: dataize the object being dispatched IF normalization is stuck on it!
dataizeStepChain (ObjectDispatch obj attr) = incLogLevel $ do
  logStep "Dataizing inside dispatch" (Left obj)
  modifyContext (\c -> c{dataizePackage = False}) $ do
    (ctx, obj') <- dataizeStepChain obj
    case obj' of
      Left obj'' -> return (ctx, Left (obj'' `ObjectDispatch` attr))
      Right bytes -> return (ctx, Left (Formation [DeltaBinding bytes] `ObjectDispatch` attr))
dataizeStepChain obj = do
  logStep "Nothing to dataize" (Left obj)
  ctx <- getContext
  return (ctx, Left obj)

dataizeRecursivelyChain' :: Context -> Object -> ([LogEntry (Either Object Bytes)], Either Object Bytes)
dataizeRecursivelyChain' ctx obj = head (runChain (dataizeRecursivelyChain False obj) ctx)

-- | Recursively perform normalization and dataization until we get bytes in the end,
-- reporting intermediate steps
dataizeRecursivelyChain :: Bool -> Object -> DataizeChain (Either Object Bytes)
dataizeRecursivelyChain = fmap minimizeObject' . go
 where
  go normalizeRequired obj = do
    logStep "Dataizing" (Left obj)
    ctx <- getContext
    let globalObject = NonEmpty.last (outerFormations ctx)
    let limits = defaultApplicationLimits (objectSize globalObject)
    let normalizedObj
          | builtinRules ctx = do
              let obj' = fastYegorInsideOut ctx obj
              logStep "Normalized" obj'
              return obj'
          | otherwise = applyRulesChainWith limits obj
    msplit (transformNormLogs normalizedObj) >>= \case
      Nothing -> do
        logStep "No rules applied" (Left obj)
        return (Left obj)
      -- We trust that all chains lead to the same result due to confluence
      Just (normObj, _alternatives)
        | normObj == obj && normalizeRequired -> return (Left obj)
        | otherwise -> do
            (ctx', step) <- dataizeStepChain normObj
            case step of
              (Left stillObj)
                | stillObj == normObj && ctx `sameContext` ctx' -> do
                    logStep "Dataization changed nothing" (Left stillObj)
                    return step -- dataization changed nothing
                | otherwise -> do
                    logStep "Dataization changed something" (Left stillObj)
                    withContext ctx' $ go False stillObj -- partially dataized
              bytes -> return bytes

-- | Given converters between Bytes and some data type, a binary function on this data type, an object,
-- and the current state of evaluation, returns the new object and a possibly modified state along with intermediate steps.
evaluateDataizationFunChain ::
  -- | How to convert the result back to bytes
  (res -> Bytes) ->
  -- | How to interpret the bytes in terms of the given data type
  (Bytes -> a) ->
  -- | How to wrap the bytes in an object
  (Bytes -> Object) ->
  -- | A binary function on the data
  (a -> a -> res) ->
  Object ->
  EvaluationState ->
  DataizeChain (Object, EvaluationState)
evaluateDataizationFunChain resultToBytes bytesToParam wrapBytes func obj _state = do
  let o_rho = ObjectDispatch obj Rho
  let o_a0 = ObjectDispatch obj (Alpha (AlphaIndex "α0"))
  lhs <- incLogLevel $ do
    logStep "Evaluating LHS" (Left o_rho)
    dataizeRecursivelyChain True o_rho
  rhs <- incLogLevel $ do
    logStep "Evaluating RHS" (Left o_a0)
    dataizeRecursivelyChain True o_a0
  result <- case (lhs, rhs) of
    (Right l, Right r) -> do
      let bytes = resultToBytes (bytesToParam r `func` bytesToParam l)
          resultObj = wrapBytes bytes
      logStep "Evaluated function" (Left resultObj)
      return resultObj
    _ -> fail "Couldn't find bytes in one or both of LHS and RHS"
  return (result, ())

evaluateBinaryDataizationFunChain ::
  -- | Name of the atom.
  String ->
  -- | How to convert the result back to bytes
  (res -> Bytes) ->
  -- | How to interpret the bytes in terms of the given data type
  (Bytes -> a) ->
  -- | How to wrap the bytes in an object
  (Bytes -> Object) ->
  -- | Extract the 1st argument to be dataized
  (Object -> Object) ->
  -- | Extract the 2nd argument to be dataized
  (Object -> Object) ->
  -- | A binary function on the argument
  (a -> a -> res) ->
  Object ->
  EvaluationState ->
  DataizeChain (Object, EvaluationState)
evaluateBinaryDataizationFunChain name resultToBytes bytesToParam wrapBytes arg1 arg2 func obj _state = do
  ctx <- getContext
  if HashSet.member (DisabledAtomName name) ctx.disabledAtomNames
    then do
      logStep [fmt|Not evaluating the atom '{name}' since it's disabled.|] (Left obj)
      pure (obj, ())
    else do
      let lhsArg = arg1 obj
      let rhsArg = arg2 obj
      lhs <- incLogLevel $ do
        logStep "Evaluating LHS" (Left lhsArg)
        dataizeRecursivelyChain True lhsArg
      rhs <- incLogLevel $ do
        logStep "Evaluating RHS" (Left rhsArg)
        dataizeRecursivelyChain True rhsArg
      result <- case (lhs, rhs) of
        (Right l, Right r) -> do
          let bytes = resultToBytes (bytesToParam l `func` bytesToParam r)
              resultObj = wrapBytes bytes
          logStep "Evaluated function" (Left resultObj)
          return resultObj
        (Left _l, Left _r) ->
          fail (name <> ": Couldn't find bytes in both LHS and RHS")
        (Left l, _) -> do
          fail (name <> ": Couldn't find bytes in LHS: " <> printTree (hideRho l))
        (_, Left r) -> do
          fail (name <> ": Couldn't find bytes in RHS: " <> printTree (hideRho r))
      return (result, ())

-- | Unary functions operate on the given object without any additional parameters
evaluateUnaryDataizationFunChain ::
  String ->
  -- | How to convert the result back to bytes
  (res -> Bytes) ->
  -- | How to interpret the bytes in terms of the given data type
  (Bytes -> a) ->
  -- | How to wrap the bytes in an object
  (Bytes -> Object) ->
  -- | Extract the argument to be dataized
  (Object -> Object) ->
  -- | A unary function on the argument
  (a -> res) ->
  Object ->
  EvaluationState ->
  DataizeChain (Object, EvaluationState)
evaluateUnaryDataizationFunChain name resultToBytes bytesToParam wrapBytes extractArg func =
  evaluateBinaryDataizationFunChain name resultToBytes bytesToParam wrapBytes extractArg extractArg (const . func)

evaluateIODataizationFunChain :: IO String -> Object -> EvaluationState -> DataizeChain (Object, EvaluationState)
evaluateIODataizationFunChain action _obj state =
  return (Formation [DeltaBinding (stringToBytes (unsafePerformIO action))], state)

extractRho :: Object -> Object
extractRho = (`ObjectDispatch` Rho)
extractAlpha0 :: Object -> Object
extractAlpha0 = (`ObjectDispatch` Alpha (AlphaIndex "α0"))
extractLabel :: String -> Object -> Object
extractLabel attrName = (`ObjectDispatch` Label (LabelId attrName))
wrapBytesInInt :: Bytes -> Object
wrapBytesInInt (Bytes bytes) = [fmt|Φ.org.eolang.int(as-bytes ↦ Φ.org.eolang.bytes(Δ ⤍ {bytes}))|]
wrapBytesInFloat :: Bytes -> Object
wrapBytesInFloat (Bytes bytes) = [fmt|Φ.org.eolang.float(as-bytes ↦ Φ.org.eolang.bytes(Δ ⤍ {bytes}))|]
wrapBytesInString :: Bytes -> Object
wrapBytesInString (Bytes bytes) = [fmt|Φ.org.eolang.string(as-bytes ↦ Φ.org.eolang.bytes(Δ ⤍ {bytes}))|]
wrapBytesInBytes :: Bytes -> Object
wrapBytesInBytes (Bytes bytes) = [fmt|Φ.org.eolang.bytes(Δ ⤍ {bytes})|]
wrapTermination :: Object
wrapTermination = [fmt|Φ.org.eolang.error(α0 ↦ Φ.org.eolang.string(as-bytes ↦ Φ.org.eolang.bytes(Δ ⤍ {bytes})))|]
 where
  Bytes bytes = stringToBytes "unknown error"

wrapBytesAsBool :: Bytes -> Object
wrapBytesAsBool bytes
  | bytesToInt bytes == 0 = [fmt|Φ.org.eolang.false|]
  | otherwise = [fmt|Φ.org.eolang.true|]

-- This should maybe get converted to a type class and some instances?
evaluateIntIntIntFunChain :: String -> (Int -> Int -> Int) -> Object -> EvaluationState -> DataizeChain (Object, EvaluationState)
evaluateIntIntIntFunChain name = evaluateBinaryDataizationFunChain name intToBytes bytesToInt wrapBytesInInt extractRho (extractLabel "x")

evaluateIntIntBoolFunChain :: String -> (Int -> Int -> Bool) -> Object -> EvaluationState -> DataizeChain (Object, EvaluationState)
evaluateIntIntBoolFunChain name = evaluateBinaryDataizationFunChain name boolToBytes bytesToInt wrapBytesAsBool extractRho (extractLabel "x")

-- Int because Bytes are just a string, but Int has a Bits instance
evaluateBytesBytesBytesFunChain :: String -> (Int -> Int -> Int) -> Object -> EvaluationState -> DataizeChain (Object, EvaluationState)
evaluateBytesBytesBytesFunChain name = evaluateBinaryDataizationFunChain name intToBytes bytesToInt wrapBytesInBytes extractRho (extractLabel "b")

evaluateBytesBytesFunChain :: String -> (Int -> Int) -> Object -> EvaluationState -> DataizeChain (Object, EvaluationState)
evaluateBytesBytesFunChain name = evaluateUnaryDataizationFunChain name intToBytes bytesToInt wrapBytesInBytes extractRho

evaluateFloatFloatFloatFunChain :: String -> (Double -> Double -> Double) -> Object -> EvaluationState -> DataizeChain (Object, EvaluationState)
evaluateFloatFloatFloatFunChain name = evaluateBinaryDataizationFunChain name floatToBytes bytesToFloat wrapBytesInFloat extractRho (extractLabel "x")

-- | Like `evaluateDataizationFunChain` but specifically for the built-in functions.
-- This function is not safe. It returns undefined for unknown functions
evaluateBuiltinFunChain :: String -> Object -> EvaluationState -> DataizeChain (Object, EvaluationState)
-- int
evaluateBuiltinFunChain name@"Lorg_eolang_int_gt" obj = evaluateIntIntBoolFunChain name (>) obj
evaluateBuiltinFunChain name@"Lorg_eolang_int_plus" obj = evaluateIntIntIntFunChain name (+) obj
evaluateBuiltinFunChain name@"Lorg_eolang_int_times" obj = evaluateIntIntIntFunChain name (*) obj
evaluateBuiltinFunChain name@"Lorg_eolang_int_div" obj = evaluateIntIntIntFunChain name quot obj
-- bytes
evaluateBuiltinFunChain name@"Lorg_eolang_bytes_eq" obj = evaluateBinaryDataizationFunChain name boolToBytes bytesToInt wrapBytesAsBool extractRho (extractLabel "b") (==) obj
evaluateBuiltinFunChain name@"Lorg_eolang_bytes_size" obj = evaluateUnaryDataizationFunChain name intToBytes id wrapBytesInBytes extractRho (\(Bytes bytes) -> length (words (map dashToSpace bytes))) obj
 where
  dashToSpace '-' = ' '
  dashToSpace c = c
evaluateBuiltinFunChain name@"Lorg_eolang_bytes_slice" obj = \state -> do
  thisStr <- incLogLevel $ dataizeRecursivelyChain True (extractRho obj)
  bytes <- case thisStr of
    Right bytes -> pure bytes
    Left _ -> fail "Couldn't find bytes"
  evaluateBinaryDataizationFunChain name id bytesToInt wrapBytesInBytes (extractLabel "start") (extractLabel "len") (sliceBytes bytes) obj state
evaluateBuiltinFunChain name@"Lorg_eolang_bytes_and" obj = evaluateBytesBytesBytesFunChain name (.&.) obj
evaluateBuiltinFunChain name@"Lorg_eolang_bytes_or" obj = evaluateBytesBytesBytesFunChain name (.|.) obj
evaluateBuiltinFunChain name@"Lorg_eolang_bytes_xor" obj = evaluateBytesBytesBytesFunChain name (.^.) obj
evaluateBuiltinFunChain name@"Lorg_eolang_bytes_not" obj = evaluateBytesBytesFunChain name complement obj
evaluateBuiltinFunChain name@"Lorg_eolang_bytes_right" obj = evaluateBinaryDataizationFunChain name intToBytes bytesToInt wrapBytesInBytes extractRho (extractLabel "x") (\x i -> shift x (-i)) obj
evaluateBuiltinFunChain name@"Lorg_eolang_bytes_concat" obj = evaluateBinaryDataizationFunChain name id id wrapBytesInBytes extractRho (extractLabel "b") concatBytes obj
-- float
evaluateBuiltinFunChain name@"Lorg_eolang_float_gt" obj = evaluateBinaryDataizationFunChain name boolToBytes bytesToFloat wrapBytesInBytes extractRho (extractLabel "x") (>) obj
evaluateBuiltinFunChain name@"Lorg_eolang_float_times" obj = evaluateFloatFloatFloatFunChain name (*) obj
evaluateBuiltinFunChain name@"Lorg_eolang_float_plus" obj = evaluateFloatFloatFloatFunChain name (+) obj
evaluateBuiltinFunChain name@"Lorg_eolang_float_div" obj = evaluateFloatFloatFloatFunChain name (/) obj
-- string
evaluateBuiltinFunChain name@"Lorg_eolang_string_length" obj = evaluateUnaryDataizationFunChain name intToBytes bytesToString wrapBytesInInt extractRho length obj
evaluateBuiltinFunChain name@"Lorg_eolang_string_slice" obj = \state -> do
  thisStr <- incLogLevel $ dataizeRecursivelyChain True (extractRho obj)
  string <- case thisStr of
    Right bytes -> pure $ bytesToString bytes
    Left _ -> fail "Couldn't find bytes"
  evaluateBinaryDataizationFunChain name stringToBytes bytesToInt wrapBytesInString (extractLabel "start") (extractLabel "len") (\start len -> take len (drop start string)) obj state
-- malloc
-- evaluateBuiltinFunChain name@"Lorg_eolang_malloc_φ" obj = _ -- TODO
-- evaluateBuiltinFunChain name@"Lorg_eolang_malloc_memory_block_pointer_read" obj = _ -- TODO
-- evaluateBuiltinFunChain name@"Lorg_eolang_malloc_memory_block_pointer_write" obj = _ -- TODO
-- evaluateBuiltinFunChain name@"Lorg_eolang_malloc_memory_block_pointer_free" obj = _ -- TODO
-- cage
-- evaluateBuiltinFunChain name@"Lorg_eolang_cage_φ" obj = _ -- TODO
-- evaluateBuiltinFunChain name@"Lorg_eolang_cage_encaged_φ" obj = _ -- TODO
-- evaluateBuiltinFunChain name@"Lorg_eolang_cage_encaged_encage" obj = _ -- TODO
-- I/O
-- evaluateBuiltinFunChain name@"Lorg_eolang_io_stdin_next_line" obj = evaluateIODataizationFunChain getLine obj
-- evaluateBuiltinFunChain name@"Lorg_eolang_io_stdin_φ" obj = evaluateIODataizationFunChain getContents obj
-- evaluateBuiltinFunChain name@"Lorg_eolang_io_stdout" obj = evaluateUnaryDataizationFunChain boolToBytes bytesToString wrapBytesInBytes (extractLabel "text") ((`seq` True) . unsafePerformIO . putStrLn) obj
-- others
evaluateBuiltinFunChain name@"Lorg_eolang_dataized" obj =
  evaluateUnaryDataizationFunChain name id id wrapBytesInBytes (extractLabel "target") id obj
evaluateBuiltinFunChain name@"Lorg_eolang_error" obj = evaluateUnaryDataizationFunChain name stringToBytes bytesToString wrapBytesInBytes (extractLabel "message") error obj
-- evaluateBuiltinFunChain name@"Lorg_eolang_seq" obj = _ -- TODO
-- evaluateBuiltinFunChain name@"Lorg_eolang_as_phi" obj = _ -- TODO
-- evaluateBuiltinFunChain name@"Lorg_eolang_rust" obj = _ -- TODO
-- evaluateBuiltinFunChain name@"Lorg_eolang_try" obj = _ -- TODO
evaluateBuiltinFunChain "Package" obj@(Formation bindings) = do
  \state -> do
    fmap dataizePackage getContext >>= \case
      True -> do
        let (packageBindings, restBindings) = span isPackage bindings
        bs <- mapM dataizeBindingChain restBindings
        logStep "Dataized 'Package' siblings" (Left $ Formation (bs ++ packageBindings))
        return (Formation (bs ++ packageBindings), state)
      False ->
        return (Formation bindings, state)
 where
  isPackage (LambdaBinding (Function "Package")) = True
  isPackage _ = False
  dataizeBindingChain (AlphaBinding attr o) = do
    ctx <- getContext
    let extendedContext = (extendContextWith obj ctx){currentAttr = attr}
    dataizationResult <- incLogLevel $ withContext extendedContext $ dataizeRecursivelyChain False o
    return (AlphaBinding attr (either id (Formation . singleton . DeltaBinding) dataizationResult))
  dataizeBindingChain b = return b
evaluateBuiltinFunChain atomName obj = \state -> do
  logStep ("[WARNING]: unknown atom (" <> atomName <> ")") (Left obj)
  return (obj, state)

-- | Like `evaluateDataizationFun` but specifically for the built-in functions.
-- This function is not safe. It returns undefined for unknown functions
evaluateBuiltinFun :: Context -> String -> Object -> EvaluationState -> (Object, EvaluationState)
evaluateBuiltinFun ctx name obj state = snd $ head $ runChain (evaluateBuiltinFunChain name obj state) ctx -- FIXME: head is bad
