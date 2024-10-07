# shellcheck disable=SC2148

set -uo pipefail

PWD_DIR="$PWD"
PIPELINE_DIR_RELATIVE="pipeline"
PIPELINE_DIR="$PWD/$PIPELINE_DIR_RELATIVE"
PIPELINE_PHI_INITIAL_DIR="$PIPELINE_DIR/phi-initial"
PIPELINE_PHI_INITIAL_DIR_RELATIVE="$PIPELINE_DIR_RELATIVE/phi-initial"
PIPELINE_EO_FILTERED_DIR="$PIPELINE_DIR/eo-filtered"
PIPELINE_EO_INITIAL_DIR="$PIPELINE_DIR/eo-initial"
PIPELINE_EO_NORMALIZED_DIR="$PIPELINE_DIR/eo-normalized"
PIPELINE_PHI_NORMALIZED_DIR="$PIPELINE_DIR/phi-normalized"
PIPELINE_EO_PHI_NORMALIZER_DIR="$PWD/eo-phi-normalizer"
PIPELINE_EO_PHI_NORMALIZER_DATA_DIR="$PIPELINE_EO_PHI_NORMALIZER_DIR/data"
PIPELINE_REPORT_DIR="$PWD/report"
PIPELINE_EO_YAML_DIR="$PIPELINE_DIR/eo-yaml"

SCRIPTS_DIR="$PWD_DIR/scripts"
PIPELINE_SCRIPT="$SCRIPTS_DIR/pipeline.sh"

PIPELINE_CONFIG_FILE="$PIPELINE_DIR/config.yaml"

PIPELINE_LOCK_FILE_NAME="pipeline.lock"
PIPELINE_LOCK_FILE="$PIPELINE_DIR/$PIPELINE_LOCK_FILE_NAME"

PIPELINE_LOCK_FILE_NEW_NAME="pipeline_new.lock"
PIPELINE_LOCK_FILE_NEW="$PIPELINE_DIR/$PIPELINE_LOCK_FILE_NEW_NAME"

PIPELINE_LOCK_FILE_RELATIVE="$PIPELINE_DIR_RELATIVE/$PIPELINE_LOCK_FILE_NAME"
PIPELINE_LOCK_FILE_NEW_RELATIVE="$PIPELINE_DIR_RELATIVE/$PIPELINE_LOCK_FILE_NEW_NAME"

EO_PHI_NORMALIZER_INSTALLED="${EO_PHI_NORMALIZER_INSTALLED:-false}"

PIPELINE_LOGS_DIR="$PIPELINE_DIR/logs"
PIPELINE_TEST_EO_INITIAL_LOGS="$PIPELINE_LOGS_DIR/test-initial-logs.txt"
PIPELINE_TEST_EO_NORMALIZED_LOGS="$PIPELINE_LOGS_DIR/test-normalized-logs.txt"

SYNTAX_DIR="$PIPELINE_EO_PHI_NORMALIZER_DIR/src/Language/EO/Phi/Syntax"

function init_logs {
    mkdir -p "$PIPELINE_LOGS_DIR"
    touch "$PIPELINE_TEST_EO_INITIAL_LOGS"
    touch "$PIPELINE_TEST_EO_NORMALIZED_LOGS"
}

export -f init_logs

init_logs

function print_message {
    printf "\n\n\n[[[%s]]]\n\n\n" "$1"
}

export -f print_message

function set_is_windows {
    # check whether the current platform is Windows
    # https://stackoverflow.com/a/3466183
    local unameOut
    unameOut="$(uname -s)"

    IS_WINDOWS=false

    case "${unameOut}" in
        Linux*)     IS_WINDOWS=false;;
        Darwin*)    IS_WINDOWS=false;;
        CYGWIN*)    IS_WINDOWS=true;;
        MINGW*)     IS_WINDOWS=true;;
        MSYS_NT*)   IS_WINDOWS=true;;
        *)          IS_WINDOWS=false
    esac
}

set_is_windows

# Set UTF-8
if [[ "$IS_WINDOWS" = "true" ]]; then
    chcp.com 65001
fi

function set_installation_path {
    INSTALLATION_PATH="$(stack path --local-bin)"

    if [[ "$IS_WINDOWS" = "true" ]]; then
        INSTALLATION_PATH="$(cygpath "$INSTALLATION_PATH")"
    fi

    print_message "Normalizer installation path: $INSTALLATION_PATH"
}

export -f set_installation_path

function add_installation_path_to_path {
    if ! [[ ":$PATH:" == *":$INSTALLATION_PATH:"* ]]; then
        export PATH="$INSTALLATION_PATH:$PATH"
        print_message "Added Normalizer installation path to PATH"
    else
        print_message "PATH already contains the Normalizer installation path"
    fi
}

export -f add_installation_path_to_path

function write_pipeline_lock {
        cat > "$PIPELINE_LOCK_FILE_NEW" <<EOF
EO_HEAD_HASH="$(git rev-parse HEAD:eo)"
PIPELINE_CONFIG_HASH="$(git hash-object "$PIPELINE_CONFIG_FILE")"
EOF

    PIPELINE_LOCK_CHANGED="${PIPELINE_LOCK_CHANGED:-false}"

    if ! cmp "$PIPELINE_LOCK_FILE" "$PIPELINE_LOCK_FILE_NEW"; then
        PIPELINE_LOCK_CHANGED="true"
    fi
}

export -f write_pipeline_lock

function update_pipeline_lock {
    print_message "Check the pipeline lock in $PIPELINE_LOCK_FILE"

    write_pipeline_lock

    if [[ "$PIPELINE_LOCK_CHANGED" = "true" ]]; then
        print_message "Pipeline lock updated"
        cp "$PIPELINE_LOCK_FILE_NEW" "$PIPELINE_LOCK_FILE"
    else
        print_message "Pipeline lock didn't change"
    fi
}

export -f write_pipeline_lock

function mkdir_clean {
    rm -rf "$1"
    mkdir -p "$1"
}

export -f mkdir_clean

function get_eo_version {
    printf "%s" "${EO:-$(yq '.project.parent.version' -p xml < eo/eo-runtime/pom.xml)}"
}

export -f get_eo_version

function commit_and_push_if_changed {
    local files="$1"
    local updated_message="$2"
    if [ -n "$(git status --porcelain "${files[@]}")" ]; then
        git add "${files[@]}"
        git commit -m "Update $updated_message"
        git push
    else
        echo "Nothing to commit.";
    fi
}

export -f commit_and_push_if_changed

function eo {
    npx eoc --parser="$EO" "$@"
}

export -f eo

function install_eo_phi_normalizer {
    set_installation_path
    add_installation_path_to_path

    print_message "Install the Normalizer"

    if [[ "$EO_PHI_NORMALIZER_INSTALLED" = "true" ]]; then
        if [[ "$IS_WINDOWS" = "true" ]]; then
            mv "$INSTALLATION_PATH/eo-phi-normalizer.exe" "$INSTALLATION_PATH/eo-phi-normalizer"
        fi
    else
        stack install eo-phi-normalizer:exe:eo-phi-normalizer --ghc-options -O2
    fi

    print_message "The Normalizer is installed"
}

export -f install_eo_phi_normalizer

function run_pipeline {
    bash "$PIPELINE_SCRIPT"
}

export -f run_pipeline

function get_failing_tests {
    local logs="$1"
    local stage="$2"

    export logs

    failed="$(
        perl -ne 'print if /<<< FAILURE/' "$logs" \
        | perl -pe 's/^.*EOorg.EOeolang.EO(.*)Test$/$1/p' \
        | perl -pe 's/_/-/g'
    )"

    if [[ "$failed" = "" ]]; then
        print_message "No tests failed $stage normalization"
    else
        print_message "Some tests failed $stage normalization"

        printf "%s\n" "$failed"
    fi
}

export -f get_failing_tests

function get_failing_tests_non_normalized {
    get_failing_tests "$PIPELINE_TEST_EO_INITIAL_LOGS" "before"
}

export -f get_failing_tests_non_normalized

function get_failing_tests_normalized {
    get_failing_tests "$PIPELINE_TEST_EO_NORMALIZED_LOGS" "after"
}

export -f get_failing_tests_normalized

function check_syntax_files_exist {
    SYNTAX_FILES_EXIST=false

    if [[ -f "$SYNTAX_DIR/Lex.hs" && -f "$SYNTAX_DIR/Par.hs" ]]; then
        SYNTAX_FILES_EXIST=true
    fi

    print_message "Syntax files exist: $SYNTAX_FILES_EXIST"
}

export -f check_syntax_files_exist

function write_dependencies_markdown_for_eo_version {
    local eo_version=$1

    export PIPELINE_EO_PHI_NORMALIZER_DATA_DIR

    local version_data_dir="$PIPELINE_EO_PHI_NORMALIZER_DATA_DIR/$eo_version"
    export version_data_dir

    function print_program {
        # shellcheck disable=SC2317
        local path=$1

        # shellcheck disable=SC2317
        local path_local="${path#"$version_data_dir/"}"

        # shellcheck disable=SC2317
        printf "## [%s](./%s)\n\n\`\`\`console\n%s\n\`\`\`\n\n" "$path_local" "$path_local" "$(cat "$path")"
    }

    export -f print_program

    local output="$version_data_dir/dependencies.md"

    printf "# Dependencies\n\n" > "$output"

    find "$version_data_dir" -name '*.phi' \
        | sort \
        | xargs -I {} bash -c 'print_program {}' \
        >> "$output"

    export -n version_data_dir
    export -n print_program
}

export -f write_dependencies_markdown_for_eo_version

function write_dependencies_markdown {
    export PIPELINE_EO_PHI_NORMALIZER_DATA_DIR

    # shellcheck disable=SC2038
    find "$PIPELINE_EO_PHI_NORMALIZER_DATA_DIR" -mindepth 1 -maxdepth 1 -type d \
        | xargs -I {} basename {} \
        | xargs -I {} bash -c "write_dependencies_markdown_for_eo_version {}"
}

export -f write_dependencies_markdown
