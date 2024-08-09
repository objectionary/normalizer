# Pipeline

## Install `stack`

{{#include ./common/install-stack.md}}

## Enter the repository

{{ #include ./common/enter-repository.md }}

## Install `normalizer`

{{ #include ./common/install.md }}

## Install dependencies

Install [yq](https://github.com/mikefarah/yq).

```$ as console
yq --version
```

```console
yq (https://github.com/mikefarah/yq/) version v4.44.1
```

Install [NodeJS](https://nodejs.org/en).

```$ as console
node --version
```

```console
v20.16.0
```

Install [Java](https://www.java.com/en/download/help/download_options.html).

```$ as console
java --version
```

```console
openjdk 21.0.4 2024-07-16 LTS
OpenJDK Runtime Environment Zulu21.36+19-CRaC-CA (build 21.0.4+7-LTS)
OpenJDK 64-Bit Server VM Zulu21.36+19-CRaC-CA (build 21.0.4+7-LTS, mixed mode, sharing)
```

### Windows

Install [Cygwin](https://www.cygwin.com/install.html).

Make `cygpath` available on `PATH`.

## Learn about the pipeline

### Pipeline stages

The pipeline has several important stages:

- Transform original `EO` programs into filtered `EO` programs, leaving only the specified top-level objects (tests).
- Translate filtered `EO` programs to initial `PHI` programs.
- Translate initial `PHI` programs to initial `EO` programs.
- Test initial `EO` programs.
- Normalize initial `PHI` programs and get normalized `PHI` programs.
- Report metrics on initial `PHI` programs and normalized `PHI` programs (See [Metrics](./metrics.md)).
- Translate normalized `PHI` programs to normalized `EO` programs.
- Test normalized `EO` programs.

### Pipeline configuration

The pipeline is configured via the [pipeline/config.yaml](https://github.com/objectionary/normalizer/blob/master/pipeline/config.yaml) file.

The configuration file specifies the following:

- `report` - Pipeline report configuration.
  - `js` - Optional path to a `JavaScript` file that should be inlined into the `HTML` report.
    - If no path is specified, `normalizer` will use [report/main.js](https://github.com/objectionary/normalizer/blob/master/eo-phi-normalizer/report/main.js).
  - `css` - Optional path to a `CSS` file that should be inlined into the `HTML` report.
    - If no path is specified, `normalizer` will use [report/styles.css](https://github.com/objectionary/normalizer/blob/master/eo-phi-normalizer/report/styles.css).
  - `output` - Where to write report versions.
    - `html` - The file path of the `HTML` version.
    - `json` - The file path of the `JSON` version.
    - `markdown` - The file path of the `GitHub Flavored Markdown` version.
  - `expected-metrics-change` - The expected relative change in metrics w.r.t the initial metrics.
    - `dataless` - For dataless formations.
    - `applications` - For applications.
    - `formations` - For formations.
    - `dispatches` - For dispatches.
  - `expected-improved-programs-percentage` - Expected percentage of programs where all metrics changed as expected.
- `test-sets` - A list of configurations for sets of test objects (tests).
  - `eo` - The configuration of the `EO` part of the test set.
    - `original` - The file path of the original `EO` program.
    - `enable` - A flag to enable tests in the original `EO` program.
    - `include` - A list of names of tests in the original `EO` program that should be included into the filtered `EO` program.
    - `exclude` - A list of names of tests in the original `EO` program that shouldn't be included into the filtered `EO` program.
    - `filtered` - The file path of the filtered original `EO` program.
    - `yaml` - The file path of the original `EO` program in the `YAML` format.
  - `phi` - The configuration of the `PHI` part of the test set.
    - `initial` - The file path of the initial `PHI` program.
    - `normalized` - The file path of the normalized `PHI` program.
    - `bindings-path-initial` - The path to tests via bindings in the initial `PHI` program.
    - `bindings-path-normalized` - The path to tests via bindings in the normalized `PHI` program.
  - `atoms` - The configuration of atoms in the test set. The set of enabled atoms is the difference of sets constructed from the `enable` and `disable` lists.
    - `enable` - The list of names of atoms to enable. An empty list is equivalent to a list of all known atoms.
    - `disable` - The list of names of atoms to disable.

## Run the pipeline script

```sh
bash ./scripts/pipeline.sh
```

## Explore the pipeline directory

The script will run for several minutes and write the following entries to the `pipeline` directory:

- `eo-filtered` - Filtered `EO` programs.
- `eo-initial` - Initial `EO` programs.
  - `.eoc/4-pull/org/eolang` - `org.eolang` objects ([link](https://github.com/objectionary/eo/tree/master/eo-runtime/src/main/eo/org/eolang)).
- `eo-normalized` - Normalized `EO` programs.
- `eo-yaml` - Filtered `EO` programs in the `YAML` format.
- `logs` - Logs of some pipeline stages.
- `phi-initial` - Initial `PHI` programs.
  - `.eoc/phi/org/eolang` - `org.eolang` objects translated to `PHI`.
- `phi-normalized` - Normalized `PHI` programs.
- `report` - Pipeline reports.
  - `report.html` - The report in the `HTML` format.
  - `report.json` - The report in the `JSON` format.
  - `report.md` - The report in the `GitHub Flavored Markdown` format.
