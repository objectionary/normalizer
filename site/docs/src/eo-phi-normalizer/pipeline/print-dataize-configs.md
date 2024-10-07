# `eo-phi-normalizer pipeline print-dataize-configs`

## `--config`, `--single-line`, `--strip-phi-prefix`

This commands reads the [pipeline configuration](../../pipeline.md#pipeline-configuration) and prints configurations for the [eo-phi-normalizer dataize](../dataize.md).

```sh
source scripts/lib.sh
eo-phi-normalizer pipeline print-dataize-configs --single-line --strip-phi-prefix "$PIPELINE_PHI_INITIAL_DIR_RELATIVE/" --config "$PIPELINE_CONFIG_FILE"
```
