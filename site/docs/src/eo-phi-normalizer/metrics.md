# `eo-phi-normalizer metrics`

## Metrics

See [Metrics](../metrics.md) for the specification of metrics collected by this command.

## Environment

{{#include ../common/celsius.md}}

## CLI

### `--help`

```$ as console
eo-phi-normalizer metrics --help
```

```console
Usage: eo-phi-normalizer metrics [FILE] [-o|--output-file FILE]
                          [-b|--bindings-path PATH]

  Collect metrics for a PHI program.

Available options:
  FILE                     FILE to read input from. When no FILE is specified,
                           read from stdin.
  -o,--output-file FILE    Output to FILE. When this option is not specified,
                           output to stdout.
  -b,--bindings-path PATH  Report metrics for bindings of a formation accessible
                           in a program by the PATH. When this option is not
                           specified, metrics for bindings are not reported.
                           Example of a PATH: 'org.eolang'.
  -h,--help                Show this help text
```

### `FILE`

```$ as json
eo-phi-normalizer metrics celsius.phi
```

```json
{
  "bindings-by-path-metrics": null,
  "program-metrics": {
    "applications": 3,
    "dataless": 6,
    "dispatches": 6,
    "formations": 8
  }
}
```

### `FILE` not specified (read from stdin)

```$ as json
cat celsius.phi | eo-phi-normalizer metrics
```

```json
{
  "bindings-by-path-metrics": null,
  "program-metrics": {
    "applications": 3,
    "dataless": 6,
    "dispatches": 6,
    "formations": 8
  }
}
```

### `--bindings-path`

```$ as console
eo-phi-normalizer metrics --bindings-path org.eolang celsius.phi
```

```console
{
  "bindings-by-path-metrics": {
    "bindings-metrics": [
      {
        "metrics": {
          "applications": 0,
          "dataless": 3,
          "dispatches": 0,
          "formations": 3
        },
        "name": "float"
      }
    ],
    "path": "org.eolang"
  },
  "program-metrics": {
    "applications": 3,
    "dataless": 6,
    "dispatches": 6,
    "formations": 8
  }
}
```
