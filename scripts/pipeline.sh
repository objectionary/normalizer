# shellcheck disable=SC2148

set -euo pipefail

if ! [ -d node_modules ]; then npm i; fi

export LC_ALL=C.UTF-8
shopt -s extglob

IMPORT_DIR="$PWD/scripts"
source "$IMPORT_DIR/lib.sh"

EO="$(get_eo_version)"
print_message "EO version: $EO"

function generate_eo_tests {
    print_message "Generate EO test files"

    mkdir_clean "$PIPELINE_EO_YAML_DIR"
    mkdir_clean "$PIPELINE_EO_FILTERED_DIR"

    normalizer prepare-pipeline-tests --config "$PIPELINE_CONFIG_FILE"
}

function convert_eo_to_phi {

    print_message "Convert EO to PHI"

    mkdir_clean "$PIPELINE_PHI_INITIAL_DIR"

    cd "$PIPELINE_EO_FILTERED_DIR"
    eo clean
    eo phi
    cp -r .eoc/phi/!(org) "$PIPELINE_PHI_INITIAL_DIR"
    cd "$PIPELINE_DIR"
}

function update_normalizer_phi_files {

    print_message "Update .phi data files in eo-phi-normalizer"

    cd "$PIPELINE_EO_FILTERED_DIR"
    local data_directory="$PIPELINE_NORMALIZER_DIR/data/$EO"
    mkdir_clean "$data_directory"
    cp -r .eoc/phi/org "$data_directory"
    cd "$PIPELINE_DIR"
}

function convert_phi_to_eo {

    print_message "Convert PHI to EO without normalization"

    mkdir_clean "$PIPELINE_EO_INITIAL_DIR"

    cd "$PIPELINE_PHI_INITIAL_DIR"
    cp -r "$PIPELINE_EO_FILTERED_DIR/.eoc" .
    eo unphi --tests
    cp -r .eoc/unphi/!(org) .eoc/2-optimize
    eo print
    cp -r .eoc/print/!(org) "$PIPELINE_EO_INITIAL_DIR"
    cd "$PIPELINE_DIR"

}

function test_with_logs {
    local logs="$1"

    local fail=false

    eo test | tee "$logs" || fail=true

    if [[ "$fail" = true ]]; then
        perl -i -pe 's/\x1b\[[0-9;]*[mGKHF]//g' "$logs"
        perl -i -pe 's/\x0//g' "$logs"

        exit 1
    fi
}

function test_without_normalization {

    print_message "Test EO without normalization"

    cd "$PIPELINE_EO_INITIAL_DIR"
    test_with_logs "$PIPELINE_TEST_EO_INITIAL_LOGS"
    cd "$PIPELINE_DIR"
}

function normalize {

    print_message "Normalize PHI"

    mkdir_clean "$PIPELINE_PHI_NORMALIZED_DIR"

    cd "$PIPELINE_PHI_INITIAL_DIR"

    local phi_files
    phi_files="$(find -- * -type f)"

    local dependency_files
    dependency_files="$(find "$PIPELINE_EO_FILTERED_DIR"/.eoc/phi/org/eolang -type f)"

    export dependency_files
    export PIPELINE_PHI_NORMALIZED_DIR
    export PIPELINE_NORMALIZER_DIR

    function normalize_file {
        local f="$1"
        destination="$PIPELINE_PHI_NORMALIZED_DIR/$f"
        mkdir -p "$(dirname "$destination")"

        dependency_file_options="$(printf "%s" "$dependency_files" | xargs -I {} printf "%s" " --dependency-file {} ")"

        set -x
        # shellcheck disable=SC2086
        normalizer dataize \
            --minimize-stuck-terms \
            --as-package \
            --recursive \
            $dependency_file_options \
            "$f" \
            > "$destination" \
            || set +x
        set +x
    }

    export -f normalize_file

    time printf "%s" "$phi_files" \
        | xargs -I {} bash -c 'normalize_file {}'
    cd "$PIPELINE_DIR"
}

function generate_report {

    print_message "Generate a report"

    cd "$PWD_DIR"

    normalizer report --config "$PIPELINE_CONFIG_FILE"
}

function convert_normalized_phi_to_eo {
    print_message "Convert normalized PHI to EO"

    cd "$PIPELINE_PHI_NORMALIZED_DIR"
    cp -r "$PIPELINE_EO_FILTERED_DIR/.eoc" .
    cp -r ./!(.eoc) .eoc/phi
    eo unphi --tests
    cp -r .eoc/unphi/!(org) .eoc/2-optimize
    eo print
    cd "$PIPELINE_DIR"
}

function test_with_normalization {

    print_message "Test EO with normalization"

    mkdir_clean "$PIPELINE_EO_NORMALIZED_DIR"

    cd "$PIPELINE_EO_NORMALIZED_DIR"
    cp -r "$PIPELINE_PHI_NORMALIZED_DIR"/.eoc/print/!(org) .
    test_with_logs "$PIPELINE_TEST_EO_NORMALIZED_LOGS"
    cd "$PIPELINE_DIR"
}

update_pipeline_lock
install_normalizer

if [[ "$PIPELINE_LOCK_CHANGED" = true ]]; then
    generate_eo_tests
    convert_eo_to_phi
    update_normalizer_phi_files
    convert_phi_to_eo
    test_without_normalization
fi

normalize
generate_report
convert_normalized_phi_to_eo
test_with_normalization
