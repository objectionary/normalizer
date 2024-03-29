# normalizer metrics

## Metrics

We count:

- [Object applications](#object-applications)
- [Object formations](#object-formations)
- [Dynamic dispatches](#dynamic-dispatches)
- [Dataless formations](#dataless-formations)

### PHI grammar

![phi-grammar](../media/phi-grammar.png)

### Object formations

- `⟦ d ↦ ∅, c ↦ ∅ ⟧`

### Object applications

- `ξ.b(c ↦ ⟦ ⟧)`

### Dynamic dispatches

- `ξ.ρ.c`

### Dataless formations

- `Primitive formation` - a formation that has a `Δ` attribute.
  - `⟦ Δ ⤍ 00- ⟧`
- `Dataless formation` - not primitive and does not have attributes that map to primitive formations.
  - `⟦ d ↦ ⟦ φ ↦ ξ.ρ.c, ν ↦ ⟦ Δ ⤍ 00- ⟧ ⟧, c ↦ ∅ ⟧`
    - the outermost formation with attributes `d` and `c` is dataless because it is not primitive and its attributes do not map to primitive formations.
    - `d` is not dataless because it has an attribute `ν` that maps to a primitive formation.

## Environment

{{#include ../common/sample-program.md}}

## CLI

### `--help`

```$ as console
normalizer metrics --help
```

```console
Usage: normalizer metrics [FILE] [-o|--output-file FILE]
                          [-b|--bindings-by-path PATH]

  Collect metrics for a PHI program.

Available options:
  FILE                     FILE to read input from. When no FILE is specified,
                           read from stdin.
  -o,--output-file FILE    Output to FILE. When this option is not specified,
                           output to stdout.
  -b,--bindings-by-path PATH
                           Report metrics for bindings of a formation accessible
                           in a program by a PATH. The default PATH is empty.
                           Example of a PATH: 'org.eolang'.
  -h,--help                Show this help text
```

### `FILE`

```$ as json
normalizer metrics program.phi
```

```json
{
  "bindingsByPathMetrics": {
    "bindingsMetrics": [
      {
        "metrics": {
          "applications": 1,
          "dataless": 1,
          "dispatches": 4,
          "formations": 4
        },
        "name": "a"
      }
    ],
    "path": []
  },
  "programMetrics": {
    "applications": 1,
    "dataless": 1,
    "dispatches": 4,
    "formations": 5
  }
}
```

### `FILE` not specified (read from stdin)

```$ as json
cat program.phi | normalizer metrics
```

```json
{
  "bindingsByPathMetrics": {
    "bindingsMetrics": [
      {
        "metrics": {
          "applications": 1,
          "dataless": 1,
          "dispatches": 4,
          "formations": 4
        },
        "name": "a"
      }
    ],
    "path": []
  },
  "programMetrics": {
    "applications": 1,
    "dataless": 1,
    "dispatches": 4,
    "formations": 5
  }
}
```

### `--bindings-by-path`

```$ as console
normalizer metrics --bindings-by-path "a" program.phi
```

```console
{
  "bindingsByPathMetrics": {
    "bindingsMetrics": [
      {
        "metrics": {
          "applications": 0,
          "dataless": 0,
          "dispatches": 2,
          "formations": 2
        },
        "name": "b"
      },
      {
        "metrics": {
          "applications": 1,
          "dataless": 1,
          "dispatches": 2,
          "formations": 1
        },
        "name": "e"
      }
    ],
    "path": [
      "a"
    ]
  },
  "programMetrics": {
    "applications": 1,
    "dataless": 1,
    "dispatches": 4,
    "formations": 5
  }
}
```
