# shellcheck disable=SC2148

mdsh

mdsh -i site/docs/src/common/celsius.md --work_dir .
mdsh -i site/docs/src/eo-phi-normalizer.md --work_dir .
mdsh -i site/docs/src/pipeline.md --work_dir .
mdsh -i site/docs/src/quick-start.md --work_dir .
mdsh -i site/docs/src/eo-phi-normalizer/dataize.md --work_dir .
mdsh -i site/docs/src/eo-phi-normalizer/metrics.md --work_dir .
mdsh -i site/docs/src/eo-phi-normalizer/transform.md --work_dir .
mdsh -i site/docs/src/eo-phi-normalizer/print-rules.md --work_dir .
mdsh -i site/docs/src/contributing.md --work_dir .

rm celsius.phi

npm i
npx prettier -w "**/*.md"
