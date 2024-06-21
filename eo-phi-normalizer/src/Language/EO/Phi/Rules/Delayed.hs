{-# LANGUAGE LambdaCase #-}

module Language.EO.Phi.Rules.Delayed where

import Data.List (partition)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Language.EO.Phi.Rules.Common
import Language.EO.Phi.Syntax.Abs

-- $setup
-- >>> :set -XOverloadedStrings

data ObjectClosure
  = FormationC Env [Binding]
  | ApplicationC ObjectClosure [BindingClosure]
  | ObjectDispatchC ObjectClosure Attribute
  | TerminationC

data BindingClosure
  = AlphaBindingC Attribute ObjectClosure
  | DeltaBindingC Bytes

type Env = NonEmpty ObjectClosure

evalContext :: Context -> Env
evalContext ctx = go (outerFormations ctx)
 where
  go :: NonEmpty Object -> NonEmpty ObjectClosure
  go (Formation bindings :| []) = globalClosure :| []
   where
    globalClosure = FormationC (globalClosure :| []) bindings
  go (_ :| []) = error "non-formation as global object"
  go (x :| (y : ys)) = let env = go (y :| ys) in eval env x `NonEmpty.cons` env

delayedYegorInsideOut :: Context -> Object -> Object
delayedYegorInsideOut ctx = quote . eval (evalContext ctx)

delayedYegorInsideOutAsRule :: NamedRule
delayedYegorInsideOutAsRule = ("Yegor's rules (hardcoded, with delayed substitutions)", \ctx obj -> [delayedYegorInsideOut ctx obj])

-- evaluate object into closure
eval :: Env -> Object -> ObjectClosure
eval env = \case
  Formation bindings -> FormationC env bindings
  Application obj args -> applicationClosure (eval env obj) (map (evalBinding env) args)
  ObjectDispatch obj attr -> objectDispatchClosure (eval env obj) attr
  GlobalObject -> NonEmpty.last env
  ThisObject -> NonEmpty.head env
  Termination -> TerminationC
  MetaSubstThis{} -> error "cannot evaluate an object with meta subst"
  MetaObject{} -> error "cannot evaluate an object with metavariables"
  MetaFunction{} -> error "cannot evaluate an object with metafunctions"

evalBinding :: Env -> Binding -> BindingClosure
evalBinding env = \case
  AlphaBinding attr obj -> AlphaBindingC attr (eval env obj)
  DeltaBinding bytes -> DeltaBindingC bytes
  _ -> error "cannot evaluate empty of meta bindings"

-- recover object from closure
quote :: ObjectClosure -> Object
quote = \case
  FormationC _env bindings -> Formation bindings -- is it really that simple?
  ObjectDispatchC objC attr -> ObjectDispatch (quote objC) attr
  ApplicationC obj args -> Application (quote obj) (map quoteBinding args)
  TerminationC -> Termination

quoteBinding :: BindingClosure -> Binding
quoteBinding = \case
  AlphaBindingC attr objC -> AlphaBinding attr (quote objC)
  DeltaBindingC bytes -> DeltaBinding bytes

objectDispatchClosure :: ObjectClosure -> Attribute -> ObjectClosure
objectDispatchClosure objC a =
  case objC of
    FormationC env bindings ->
      case lookupBinding a bindings of
        Just objA -> eval (objC `NonEmpty.cons` env) objA
        Nothing ->
          case lookupBinding Phi bindings of
            Just objPhi -> eval (objC `NonEmpty.cons` env) (ObjectDispatch objPhi a)
            Nothing
              | not (any isLambdaBinding bindings) -> TerminationC
              | otherwise -> ObjectDispatchC objC a
    _ -> ObjectDispatchC objC a

splitPositionalArgs :: [BindingClosure] -> ([ObjectClosure], [BindingClosure])
splitPositionalArgs = go
 where
  go [] = ([], [])
  go (AlphaBindingC (Alpha _) obj : args) = (obj : objs, others)
   where
    (objs, others) = go args
  go (bindingC : args) = (objs, bindingC : others)
   where
    (objs, others) = go args

applicationBindingsClosure :: Env -> [BindingClosure] -> [Binding] -> ObjectClosure
applicationBindingsClosure env args bindings
  | length args > length emptyBindings
      || length leftoverEmptyBindings + length args > length emptyBindings =
      TerminationC
  | otherwise =
      FormationC env $
        concat
          [ zipWith f emptyBindings (map quote positionalArgs)
          , map quoteBinding otherArgs
          , attachedBindings
          ]
 where
  f (EmptyBinding a) = AlphaBinding a
  f _ = error "impossible: not an empty (non-Δ) binding!"

  (positionalArgs, otherArgs) = splitPositionalArgs args
  (emptyBindings, attachedBindings) = partition isEmptyBinding bindings
  leftoverEmptyBindings = filter doesNotHaveArg (drop (length positionalArgs) emptyBindings)
  doesNotHaveArg (EmptyBinding a) =
    a
      `notElem` [argAttr | AlphaBindingC argAttr _ <- otherArgs]
  doesNotHaveArg _ = error "impossible: not an empty (non-Δ) binding"

applicationClosure :: ObjectClosure -> [BindingClosure] -> ObjectClosure
applicationClosure objC args =
  case objC of
    FormationC env bindings -> applicationBindingsClosure env args bindings
    _ -> ApplicationC objC args

isLambdaBinding :: Binding -> Bool
isLambdaBinding LambdaBinding{} = True
isLambdaBinding _ = False
