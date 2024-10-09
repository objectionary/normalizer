# Contributing

## Issues

Check open issues ([link](https://github.com/objectionary/normalizer/issues)).

### Issue labels

- `priority N` - an issue with the priority `N`.
  - `1` - The highest priority (the most important issues).
  - `5` - The lowest priority (the least important issues).
- `(scope)` - An issue concerning a particular part of the project. Note the parentheses.
- `[non-functional requirement]` - An issue concerning a non-functional requirement. Note the square brackets.

## Enter the repository

{{#include ./common/enter-repository.md}}

## Install stack

We recommend using [stack](https://docs.haskellstack.org/en/stable) for quick local development and testing.

## Build

Build the project using `stack`.

```sh
export LC_ALL=C.UTF-8
stack build
```

## Test

Run all tests

```sh
export LC_ALL=C.UTF-8
stack test
```

## Run

Run the `normalizer` executable via `stack run`.

```$ as console
stack run normalizer -- --help
```

```console
Usage: normalizer COMMAND

  Work with PHI expressions.

Available options:
  -h,--help                Show this help text

Available commands:
  transform                Transform a PHI program.
  metrics                  Collect metrics for a PHI program.
  dataize                  Dataize a PHI program.
  pipeline                 Run pipeline-related commands.
  print-rules              Print rules in LaTeX format.
  test                     Run unit tests in given files with user-defined
                           rules.
```

Or, omit the executable name.

```$ as console
stack run -- --help
```

```console
Usage: normalizer COMMAND

  Work with PHI expressions.

Available options:
  -h,--help                Show this help text

Available commands:
  transform                Transform a PHI program.
  metrics                  Collect metrics for a PHI program.
  dataize                  Dataize a PHI program.
  pipeline                 Run pipeline-related commands.
  print-rules              Print rules in LaTeX format.
  test                     Run unit tests in given files with user-defined
                           rules.
```

## Docs

### Math expressions

Use the syntax supported by `mdBook` - see [docs](https://rust-lang.github.io/mdBook/format/mathjax.html).

### mdsh

We use [mdsh](https://github.com/zimbatm/mdsh) to document command outputs (see [Multiline Shell Code](https://github.com/zimbatm/mdsh#multiline-shell-code)).

You can install `mdsh` via `cargo` or `nix` ([link](https://github.com/zimbatm/mdsh#installation)).

### prettier

We format docs with [prettier](https://prettier.io/).

Run `npm i` to locally install the `prettier` version that we use.

### Automatic updates

In CI, on the `master` branch, we run a [script](https://github.com/objectionary/normalizer/blob/master/scripts/update-markdown.sh) to update Markdown files and then we commit changes.

So, no worries if you haven't run `mdsh` in your PR!

## Code quality

### Checks in CI

We run `fourmolu` and `hlint` checks in CI.

These checks are also implemented as pre-commit hooks.

## pre-commit hooks

We use [pre-commit](https://pre-commit.com/) hooks to ensure code quality.

Collaborators **MUST** set up the hooks before commiting any code to our repository.

### Set up pre-commit

#### Single command

```console
pip3 install
pre-commit install
stack install fourmolu
chmod +x scripts/run-fourmolu.sh
```

#### Step by step

1. Install [Python 3](https://www.python.org/downloads/) (e.g., Python 3.10).
1. [Install pre-commit](https://pre-commit.com/#1-install-pre-commit).
   - Alternatively, run `pip3 install`.
1. [Install the git hook scripts](https://pre-commit.com/#3-install-the-git-hook-scripts).
1. Install [fourmolu](https://github.com/fourmolu/fourmolu).

   ```console
   stack install fourmolu
   ```

   - You can remove `fourmolu` later (see [SO post](https://stackoverflow.com/a/38639959))

1. Make a script executable.

   ```console
   chmod +x scripts/run-fourmolu.sh
   ```

### pre-commit configs

See [docs](https://pre-commit.com/#adding-pre-commit-plugins-to-your-project).

See [.pre-commit-config.yaml](https://github.com/objectionary/normalizer/blob/master/.pre-commit-config.yaml).

You can run a specific hook (see [docs](https://pre-commit.com/#pre-commit-run)):

```console
pre-commit run -c .pre-commit-config.yaml fourmolu-format --all
```

### pre-commit workflow

- `pre-commit` runs before a commit (at the [pre-commit phase](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks#_committing_workflow_hooks))

  > The pre-commit hook is run first, before you even type in a commit message. It's used to inspect the snapshot that's about to be committed, to see if you've forgotten something, to make sure tests run, or to examine whatever you need to inspect in the code. Exiting non-zero from this hook aborts the commit ...

- `pre-commit` stashes ([link](https://git-scm.com/docs/git-stash)) unstaged ([link](https://git-scm.com/book/en/v2/Getting-Started-What-is-Git%3F#_the_three_states)) files.

  ```console
  [WARNING] Unstaged files detected.
  [INFO] Stashing unstaged files to /home/eyjafjallajokull/.cache/pre-commit/patch1705090051-437857.
  ```

- `pre-commit` runs hooks.
- A hook may exit with an error, e.g.:

  ```md
  Format Haskell (.hs) files...............................................Failed

  - hook id: fourmolu
  - exit code: 102
  - files were modified by this hook
  ```

  - In case of the [fourmolu](https://github.com/fourmolu/fourmolu) formatter,
    it's assumed that formatting a formatted `Haskell` file doesn't modify it.
    However, `pre-commit` runs the `fourmolu` hook and reports that it has modified some files.
    This error won't allow you to commit.

- `pre-commit` unstashes files.

- You should stage all changes so that `pre-commit` does not complain.

  - In case of `fourmolu`, stage the formatted code regions.

- Now, you can commit.
