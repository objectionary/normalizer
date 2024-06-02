# `normalizer dataize`

Dataization is the process through which data is extracted from a given program/object.

## Dataization process

To dataize a given program written in \\( \varphi \\)-calculus, the first step is to normalize it according to the process outlined in [normalizer rewrite](./rewrite.md) docs.
Then, a single step of dataization is performed according to the following rules in order of priority:

1. If the object is a formation that contains a \\( \Delta \\)-binding and no empty bindings, the bytes attached to it are returned
2. If the object is a formation that contains a \\( \lambda \\)-binding and no empty bindings, the attached value is evaluated as a known built-in function and its result is returned. Currently, the following functions are supported:
   - `Times`
   - `Plus`
   - `Package`: the existence of this \\( \lambda \\)-binding is interpreted to mean that all its sibling attributes should be dataized in-place.
3. If the object is a formation that contains a \\( \phi \\)-binding and no empty bindings, the result becomes the dataization of its attached object
4. If the object is an application, the object on which the bindings are applied is dataized and then the application is reapplied on its result. In other words, \\( \mathbb{D}\left(obj(a \mapsto b, ...)\right) = \mathbb{D}\left(obj\right)(a \mapsto b, ...) \\)
5. If the object is a dispatch, the object on which the attribute is being dispatched is dataized and then the attribute is dispatched on its result. In other words, \\( \mathbb{D}\left(obj.\alpha\right) = \mathbb{D}\left(obj\right).\alpha \\)

The full dataization process is achieved by recursively normalizing and dataizing according to the rules above until bytes are reached or the object does not change (in which case the dataization is considered to have failed).
Note that dataization assumes that the given set of normalization rules are already proven to be confluent and does not verify claim.

## Environment

{{#include ../common/celsius.md}}

## CLI

### `--help`

```$ as console
normalizer dataize --help
```

```console
Usage: normalizer dataize (-r|--rules FILE) [FILE] [-d|--dependency-file FILE]
                          [-o|--output-file FILE] [--recursive] [--chain]
                          [--tex]

  Dataize a PHI program.

Available options:
  -r,--rules FILE          FILE with user-defined rules. Must be specified.
  FILE                     FILE to read input from. When no FILE is specified,
                           read from stdin.
  -d,--dependency-file FILE
                           FILE to read dependencies from (zero or more
                           dependency files allowed).
  -o,--output-file FILE    Output to FILE. When this option is not specified,
                           output to stdout.
  --recursive              Apply dataization + normalization recursively.
  --chain                  Display all the intermediate steps.
  --tex                    Output LaTeX.
  -h,--help                Show this help text
```

### `--rules FILE`

Similar to `--rules` for the `rewrite` subcommand, this argument accepts the path to a YAML file containing the rules to be used in the normalization phase.

### `--chain`

If the `--chain` argument is passed, all the intermediate steps of normalization + dataization are printed to the console (or the output file if chosen).

```$ as console
normalizer dataize --chain --rules ./eo-phi-normalizer/test/eo/phi/rules/yegor.yaml celsius.phi
```

```console
Dataizing inside phi: ξ.c.times (x ↦ ⟦ Δ ⤍ 01-01-00-00-00-00-00-00-00-07-CD-CC-CC-CC-CC-CC-1C-FF-FF-FF-FF-FF-FF-FF-CC ⟧).plus (x ↦ ⟦ Δ ⤍ 01-01-00-00-00-00-00-00-00-07-00-00-00-00-00-00-10-FF-FF-FF-FF-FF-FF-FF-D1 ⟧)
Dataizing inside application: ξ.c.times (x ↦ ⟦ Δ ⤍ 01-01-00-00-00-00-00-00-00-07-CD-CC-CC-CC-CC-CC-1C-FF-FF-FF-FF-FF-FF-FF-CC ⟧).plus
Dataizing inside dispatch: ξ.c.times (x ↦ ⟦ Δ ⤍ 01-01-00-00-00-00-00-00-00-07-CD-CC-CC-CC-CC-CC-1C-FF-FF-FF-FF-FF-FF-FF-CC ⟧)
Dataizing inside application: ξ.c.times
Dataizing inside dispatch: ξ.c
Dataizing inside dispatch: ξ
Nothing to dataize: ξ
```

### `--output-file FILE`

Redirects the output to file of the given path instead of `stdout`.

### `--dependency-file FILE`

Injects package dependencies from a given file into the context when dataizing the input.
Can be used multiple times to inject multiple dependencies.

### `--recursive`

Applies the normalization+dataization process recursively until it reaches bytes or no longer modifies the object (stalls).

```$ as console
normalizer dataize --recursive --rules eo-phi-normalizer/test/eo/phi/rules/yegor.yaml celsius.phi
```

```console
Φ.org.eolang.float (as-bytes ↦ Φ.org.eolang.bytes (Δ ⤍ 01-01-00-00-00-00-00-00-00-07-00-00-00-00-00-00-19-FF-FF-FF-FF-FF-FF-FF-D0)).times (x ↦ ⟦ Δ ⤍ 01-01-00-00-00-00-00-00-00-07-CD-CC-CC-CC-CC-CC-1C-FF-FF-FF-FF-FF-FF-FF-CC ⟧).plus (x ↦ ⟦ Δ ⤍ 01-01-00-00-00-00-00-00-00-07-00-00-00-00-00-00-10-FF-FF-FF-FF-FF-FF-FF-D1 ⟧)
```

Can be combined with `--chain` to print all the intermediate steps of both normalization and dataization.

### `FILE` not specified (read from stdin)

If no argument is given for the input file, `stdin` is consumed until `EOF`.

```$ as console
cat celsius.phi | normalizer dataize --recursive --rules ./eo-phi-normalizer/test/eo/phi/rules/yegor.yaml
```

```console
Φ.org.eolang.float (as-bytes ↦ Φ.org.eolang.bytes (Δ ⤍ 01-01-00-00-00-00-00-00-00-07-00-00-00-00-00-00-19-FF-FF-FF-FF-FF-FF-FF-D0)).times (x ↦ ⟦ Δ ⤍ 01-01-00-00-00-00-00-00-00-07-CD-CC-CC-CC-CC-CC-1C-FF-FF-FF-FF-FF-FF-FF-CC ⟧).plus (x ↦ ⟦ Δ ⤍ 01-01-00-00-00-00-00-00-00-07-00-00-00-00-00-00-10-FF-FF-FF-FF-FF-FF-FF-D1 ⟧)
```
