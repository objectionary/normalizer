# Normalizer for \\( \varphi \\)-calculus

Command line normalizer of \\( \varphi \\)-calculus expressions (as produced by the [EO compiler](https://github.com/objectionary/eo)).

Throughout the documentation, we refer to 𝜑-calculus as `PHI`.

This project aims to apply term rewriting techniques to "simplify" an input `PHI` expression and prepare it for further optimization passes. The simplification procedure will be a form of partial evaluation and normalization (see [eo-phi-normalizer transform](./eo-phi-normalizer/transform.md) and [eo-phi-normalizer dataize](./eo-phi-normalizer/dataize.md)).

Contrary to traditional normalization in λ-calculus, we aim at rewriting rules that would help reduce certain metrics of expressions (see [eo-phi-normalizer metrics](./eo-phi-normalizer/metrics.md)).

See the [report](https://www.objectionary.com/normalizer/report) on our current progress with metrics.

The eo-phi-normalizer package is available on [Hackage](https://hackage.haskell.org/package/eo-phi-normalizer).

The latest package [Haddock documentation](https://www.objectionary.com/normalizer/haddock) is available on our site.
