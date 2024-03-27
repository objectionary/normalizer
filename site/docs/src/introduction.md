# Normalizer for 𝜑-calculus

Command line normalizer of 𝜑-calculus (`PHI`) expressions (as produced by the [EO compiler](https://github.com/objectionary/eo)).

This project aims to apply term rewriting techniques to "simplify" an input `PHI` expression and prepare it for further optimization passes. The simplification procedure will be a form of partial evaluation and normalization (see [normalizer transform](./commands/normalizer-transform.md)).

Contrary to traditional normalization in λ-calculus, we aim at rewriting rules that would help reduce certain metrics of expressions (see [normalizer metrics](./commands/normalizer-metrics.md)).

See the [report](https://www.objectionary.com/normalizer/report) on our current progress with metrics.

The normalizer package is available on [Hackage](https://hackage.haskell.org/package/eo-phi-normalizer).

The latest package [Haddock documentation](https://www.objectionary.com/normalizer/haddock) is available on our site.
