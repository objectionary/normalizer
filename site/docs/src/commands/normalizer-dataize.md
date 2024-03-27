# `normalizer dataize`

Dataization is the process through which data is extracted from a given program/object.

## Dataization process

To dataize a given program written in $\varphi$-calculus, the first step is to normalize it according to the process outlined in [`normalize tranform` docs](./normalizer-transform.md).
Then, a single step of dataization is performed according to the following rules in order of priority:
1. If the object is a formation that contains a $\Delta$-binding, the bytes attached to it are returned
2. If the object is a formation that contains a $\lambda$-binding, the attached value is evaluated as a known built-in function and its result is returned. Currently, the following functions are supported:
   - `Times`
   - `Plus`
   - `Package`: this $\lambda$-binding is currently ignored (dataization proceeds as if it was not there) until proper support is added for specifying the path of the object to be dataized.
3. If the object is a formation that contains a $\phi$-binding, the result becomes the dataization of its attached object
4. If the object is an application, the object on which the bindings are applied is dataized and then the application is reapplied on its result. In other words, $\mathbb{D}\left(obj(a \mapsto b, ...)\right) = \mathbb{D}\left(obj\right)(a \mapsto b, ...)$
5. If the object is a dispatch, the object on which the attribute is being dispatched is dataized and then the attribute is dispatched on its result. In other words, $\mathbb{D}\left(obj.\alpha\right) = \mathbb{D}\left(obj\right).\alpha$

The full dataization process is achieved by recursively normalizing and dataizing according to the rules above until bytes are reached or the object does not change (in which case the dataization is considered to have failed).

## Environment

{{#include ../common/celsius.md}}

## CLI

### `--help`

```$ as console
normalizer dataize --help
```

```console
Usage: normalizer dataize (-r|--rules FILE) [FILE] [-o|--output-file FILE]
                          [--recursive] [--chain]

  Dataize a PHI program.

Available options:
  -r,--rules FILE          FILE with user-defined rules. Must be specified.
  FILE                     FILE to read input from. When no FILE is specified,
                           read from stdin.
  -o,--output-file FILE    Output to FILE. When this option is not specified,
                           output to stdout.
  --recursive              Apply dataization + normalization recursively.
  --chain                  Display all the intermediate steps.
  -h,--help                Show this help text
```

### `--rules`

Similar to `--rules` for the `transform` subcommand, this argument accepts the path to a YAML file containing the rules to be used in the normalization phase.

### `--chain`

If the `--chain` argument is passed, all the intermediate steps of normalization + dataization are printed to the console (or the output file if chosen).

```$ as console
normalizer dataize --chain --rules ./eo-phi-normalizer/test/eo/phi/rules/yegor.yaml celsius.phi
```

```console
Normal form: ⟦ σ ↦ Φ, c ↦ Φ.org.eolang.float (Δ ⤍ 19-), φ ↦ ξ.c.times (α0 ↦ ⟦ Δ ⤍ 02- ⟧).plus (α0 ↦ ⟦ Δ ⤍ 20- ⟧), org ↦ ⟦ eolang ↦ ⟦ float ↦ ⟦ Δ ⤍ ∅, times ↦ ⟦ α0 ↦ ∅, λ ⤍ Times ⟧, plus ↦ ⟦ α0 ↦ ∅, λ ⤍ Plus ⟧ ⟧ ⟧ ⟧ ⟧
Dataizing inside phi: ξ.c.times (α0 ↦ ⟦ Δ ⤍ 02- ⟧).plus (α0 ↦ ⟦ Δ ⤍ 20- ⟧)
Dataizing inside application: ξ.c.times (α0 ↦ ⟦ Δ ⤍ 02- ⟧).plus
Dataizing inside dispatch: ξ.c.times (α0 ↦ ⟦ Δ ⤍ 02- ⟧) (α0 ↦ ⟦ Δ ⤍ 20- ⟧)
Dataizing inside application: ξ.c.times.plus (α0 ↦ ⟦ Δ ⤍ 20- ⟧)
Dataizing inside dispatch: ξ.c (α0 ↦ ⟦ Δ ⤍ 02- ⟧).plus (α0 ↦ ⟦ Δ ⤍ 20- ⟧)
Dataizing inside dispatch: ξ.times (α0 ↦ ⟦ Δ ⤍ 02- ⟧).plus (α0 ↦ ⟦ Δ ⤍ 20- ⟧)
Nothing to dataize: ξ.c.times (α0 ↦ ⟦ Δ ⤍ 02- ⟧).plus (α0 ↦ ⟦ Δ ⤍ 20- ⟧)
```

### `--output-file`

Redirects the output to file of the given path instead of `stdout`.

### `--recursive`

Applies the normalization+dataization process recursively until it reaches bytes or no longer modifies the object (stalls).

```$ as console
normalizer dataize --recursive --rules eo-phi-normalizer/test/eo/phi/rules/yegor.yaml celsius.phi
```

```console
52-
```

Can be combined with `--chain` to print all the intermediate steps of both normalization and dataization.

### `FILE` not specified (read from stdin)

If no argument is given for the input file, `stdin` is consumed until `EOF`.

```$ as console
cat celsius.phi | normalizer dataize --recursive --rules ./eo-phi-normalizer/test/eo/phi/rules/yegor.yaml
```

```console
52-
```
