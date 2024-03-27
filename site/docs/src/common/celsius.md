Save a `PHI` program to a file.
This program will be used in subsequent commands.

```$
cat > celsius.phi <<EOM
{⟦
  σ ↦ Φ,
  c ↦ Φ.org.eolang.float(Δ ⤍ 19-), // 0x19 = 25
  // The 02- should technically be 1.8 (or its float representation in bytes), but only integers are supported for now
  φ ↦ ξ.c.times(α0 ↦ ⟦ Δ ⤍ 02- ⟧)
          .plus(α0 ↦ ⟦ Δ ⤍ 20- ⟧), // 0x20 = 32
  org ↦ ⟦
    eolang ↦ ⟦
      float ↦ ⟦
        Δ ⤍ ∅,
        times ↦ ⟦ α0 ↦ ∅, λ ⤍ Times ⟧,
        plus ↦ ⟦ α0 ↦ ∅, λ ⤍ Plus ⟧
      ⟧
    ⟧
  ⟧
⟧}
EOM
```
