mdsh

mdsh -i site/docs/src/common/sample-program.md --work_dir .
mdsh -i site/docs/src/common/celsius.md --work_dir .
mdsh -i site/docs/src/commands/normalizer.md --work_dir .
mdsh -i site/docs/src/commands/normalizer-transform.md --work_dir .
mdsh -i site/docs/src/commands/normalizer-metrics.md --work_dir .
mdsh -i site/docs/src/commands/normalizer-dataize.md --work_dir .
mdsh -i site/docs/src/commands/normalizer-report.md --work_dir .
mdsh -i site/docs/src/contributing.md --work_dir .

rm program.phi celsius.phi

npm i
npx prettier -w "**/*.md"

