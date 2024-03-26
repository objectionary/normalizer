# CHANGELOG

## Unreleased

## v0.3.2.1 (2023-04-25)

+ Added support for GHC 9.6
+ Updated dependency versions for HSpec and template-haskell

## v0.3.2.0 (2022-12-12)

+ Added support for GHC 9.4

## v0.3.1.2 (2022-05-15)

+ Updated dependency versions for HSpec and template-haskell

## v0.3.1.1 (2021-05-21)

+ Updated dependency versions for HSpec and template-haskell

## v0.3.1.0 (2021-02-12)

+ Added variant interpolators, `__i'E`, `__i'L`, `iii'E`, `iii'L`, that handle
  surrounding newlines in a different way based on suffix.

## v0.3.0.2 (2020-10-01)

+ Removed upper bounds on `base16-bytestring`. Safe to do so now that
  `text-converions` has added upper bounds. This change should not affect any
  users of `string-interpolate`.

## v0.3.0.1 (2020-09-19)

+ Downgraded version of `base16-bytestring` to avoid breaking API changes in new
  versions. (We would just upgrade the version ourselves, but it's one of our
  dependencies `text-conversions` that's not building due to the API changes,
  not us.)

## v0.3.0.0 (2020-06-30)

+ Changed the behavior of `iii` to only collapse statically-available whitespace,
  which also removes the performance penalty of using `iii`.
+ Removed noise on compile errors if quasiquoters are misused
+ Changed behavior of backslash escapes to error on unknown escape characters

## v0.2.1.0 (2020-05-04)

+ Added `__i` interpolator for stripping indentation in multiline strings
+ Added benchmarks for lazy Text and lazy ByteString
+ Changed default behavior for Text and ByteString to use the actual types
  themselves as intermediate objects rather than construct Builders. This
  should give significant speedups in the common case of interpolating
  smaller outputs. Old behavior can be reenabled using Cabal
  flags `-ftext-builder` and `-fbytestring-builder`
+ Gated benchmarks for `Interpolation` and `interpolatedstring-perl6` behind
  a Cabal flag so that we can still be in Stackage without needing to remove
  these dependencies

## v0.2.0.3 (2020-04-26)

+ Commented out `interpolatedstring-perl6` benchmarks, since that library
  does not build on GHC 8.8.2

## v0.2.0.2 (2020-04-25)

+ Updated interpolation parser to use enabled language extensions
  (Thanks Cary Robbins!)

## v0.2.0.1 (2020-04-09)

+ Fixed bug caused when escaping a backslash right before an interpolation
  (Thanks Vladimir Stepchenko!)
+ Fixed behavior of `iii` (Thanks Vladimir Stepchenko!)

## v0.2.0.0 (2019-12-16)

+ Added `iii` interpolator for collapsing whitespace/newlines into
  single spaces
+ Added feature comparison to/benchmark with `neat-interpolation`
+ Just generally make the documentation better
+ Add homepage info to cabal file/Haddock documentation

## v0.1.0.1 (2019-05-06)

+ Remove Interpolation from the default benchmarks because it's not
  on Stackage

## v0.1.0.0 (2019-03-17)

+ Add support for using Text and ByteString `Builder`s as both sinks
  and sources
+ Add support for interpolating Chars without the surrounding quotes

## v0.0.1.0 (2019-03-10)

+ Initial release
