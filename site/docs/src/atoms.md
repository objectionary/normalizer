# Atoms

The `normalizer` uses atoms implemented in Haskell.
The sections below explain how to update them.

## Enter the repository

{{#include ./common/enter-repository.md}}

## Install `stack`

{{#include ./common/install-stack.md}}

## Update atom definitions

Edit definitions in the list `knownAtomsList` in the module `eo-phi-normalizer/src/Language/EO/Phi/Dataize/Atoms.hs`.

## Test

{{#include ./common/run-tests.md}}
