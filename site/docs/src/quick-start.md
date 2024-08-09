# Quick start

{{#include common/enter-repository.md}}

Install `normalizer` - see [Installation](./installation.md).

{{#include common/celsius.md}}

Dataize the program recursively.

```$ as console
normalizer dataize --recursive --rules eo-phi-normalizer/test/eo/phi/rules/yegor.yaml \
  --dependency-file 'eo-phi-normalizer/data/0.38.0/org/eolang/float.phi' \
  --dependency-file 'eo-phi-normalizer/data/0.38.0/org/eolang/bytes.phi' \
  celsius.phi
```

```console
{⟦
  c ↦ ⟦
    Δ ⤍ 40-39-00-00-00-00-00-00
  ⟧,
  result ↦ ⟦
    Δ ⤍ 40-53-40-00-00-00-00-00
  ⟧,
  λ ⤍ Package
⟧}
```
