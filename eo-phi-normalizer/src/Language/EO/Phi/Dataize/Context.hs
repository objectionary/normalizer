module Language.EO.Phi.Dataize.Context where

import Data.HashMap.Strict qualified as HashMap
import Data.HashSet as HashSet (difference, fromList, intersection, member)
import Data.List.NonEmpty qualified as NonEmpty
import Language.EO.Phi.Dataize.Atoms as Atoms
import Language.EO.Phi.Rules.Common
import Language.EO.Phi.Syntax.Abs

knownAtomsMap :: Atoms
knownAtomsMap = HashMap.fromList knownAtomsList

defaultContext :: [NamedRule] -> Object -> Context
defaultContext rules obj =
  Context
    { builtinRules = False
    , allRules = rules
    , enabledAtoms = mkEnabledAtoms [] []
    , knownAtoms = knownAtomsMap
    , outerFormations = NonEmpty.singleton obj
    , currentAttr = Phi
    , insideFormation = False
    , insideAbstractFormation = False
    , dataizePackage = True
    , minimizeTerms = False
    , insideSubObject = False
    }

mkEnabledAtoms :: [String] -> [String] -> Atoms
mkEnabledAtoms enabled disabled = enabledAtoms'
 where
  knownAtomsSet = HashSet.fromList (HashMap.keys knownAtomsMap)
  disabledSet = HashSet.fromList disabled
  enabledSet =
    case enabled of
      [] -> knownAtomsSet
      _ -> HashSet.fromList enabled
  enabled' = HashSet.intersection (HashSet.difference enabledSet disabledSet) knownAtomsSet
  enabledAtoms' = HashMap.filterWithKey (\k _ -> k `HashSet.member` enabled') knownAtomsMap
