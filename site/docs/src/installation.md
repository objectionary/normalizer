# Installation

## Environment requirements

- OS: `Ubuntu 22.04` or `macOS 12`.
- `stack` is installable.
- `eo-phi-normalizer` is installable.

## Install `stack`

{{#include ./common/install-stack.md}}

## Install `eo-phi-normalizer`

Install the `eo-phi-normalizer` executable globally via [stack](https://docs.haskellstack.org/en/stable).
Then, the `eo-phi-normalizer` executable will be available on `PATH`.

### Install `eo-phi-normalizer` from the repository

{{#include ./common/enter-repository.md}}

{{#include ./common/install.md}}

### Install `eo-phi-normalizer` from Hackage

```sh
stack update
export LC_ALL=C.UTF-8
stack install --resolver lts-22.16 eo-phi-normalizer
```

## Update `eo-phi-normalizer`

Run `stack install ...` as in one of the methods above.

## Uninstall `eo-phi-normalizer`

Learn where `stack` installs programs.

```sh
stack path --programs
```

Learn how to uninstall a program.

```sh
stack uninstall
```
