#!/usr/bin/env bats
# Structural tests for the model catalogs in models/install.sh.
#
# Five of the six GGUF entries once pointed at repos or filenames that do not
# exist on the Hub, and the default install died on the first download.
#
# Only the Hub can confirm an entry actually resolves, and a unit suite must not
# go to the network, so these cannot catch a well-formed entry pointing at a
# repo nobody ever published — the gemma3-e2b failure was exactly that. What
# they do lock down is everything checkable offline: field counts, repo shape,
# filename extension and casing, size format, and agreement between the
# catalogs, model_catalog_list and config.env. Run with:
#   bats tests/bats/models_catalog.bats

setup() {
    export AWB_ROOT
    AWB_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export AI_HOME="${BATS_TEST_TMPDIR}/ai"

    source "${AWB_ROOT}/lib/colors.sh"
    source "${AWB_ROOT}/lib/logger.sh"
    source "${AWB_ROOT}/lib/utils.sh"
    source "${AWB_ROOT}/models/install.sh"
}

# The names model_catalog_list advertises. Every assertion below walks these,
# so an entry added to the catalog without being listed is itself a failure.
LLM_MODELS="gemma3 gemma3-e2b gemma4-e2b gemma4-e4b gemma4-26b qwen3 qwen3-4b phi4 deepseek-coder-v2"
WHISPER_MODELS="whisper-tiny.en whisper-base.en whisper-small.en whisper-medium.en whisper-large-v3-turbo"

# --- catalog lookup -------------------------------------------------------

@test "_awb_model_catalog: every advertised LLM name resolves to an entry" {
    for name in $LLM_MODELS; do
        run _awb_model_catalog "$name"
        [ "$status" -eq 0 ] || { echo "no catalog entry for '$name'"; return 1; }
        [ -n "$output" ]
    done
}

@test "_awb_whisper_catalog: every advertised whisper name resolves to an entry" {
    for name in $WHISPER_MODELS; do
        run _awb_whisper_catalog "$name"
        [ "$status" -eq 0 ] || { echo "no catalog entry for '$name'"; return 1; }
        [ -n "$output" ]
    done
}

@test "_awb_model_catalog: returns non-zero for an unknown name" {
    run _awb_model_catalog definitely-not-a-model
    [ "$status" -ne 0 ]
}

@test "_awb_whisper_catalog: returns non-zero for an unknown name" {
    run _awb_whisper_catalog definitely-not-a-model
    [ "$status" -ne 0 ]
}

@test "the two catalogs are disjoint — no name resolves in both" {
    for name in $LLM_MODELS; do
        run _awb_whisper_catalog "$name"
        [ "$status" -ne 0 ] || { echo "'$name' is in both catalogs"; return 1; }
    done
    for name in $WHISPER_MODELS; do
        run _awb_model_catalog "$name"
        [ "$status" -ne 0 ] || { echo "'$name' is in both catalogs"; return 1; }
    done
}

# --- entry shape ----------------------------------------------------------
# _install_catalog_entry cut -d'|' -f1..4 blindly; a missing field silently
# becomes an empty repo_id or filename and the download fails far from here.

@test "every LLM entry has exactly four pipe-delimited fields" {
    for name in $LLM_MODELS; do
        entry="$(_awb_model_catalog "$name")"
        fields="$(awk -F'|' '{print NF}' <<<"$entry")"
        [ "$fields" -eq 4 ] || { echo "'$name' has ${fields} fields, expected 4: ${entry}"; return 1; }
    done
}

@test "every whisper entry has exactly four pipe-delimited fields" {
    for name in $WHISPER_MODELS; do
        entry="$(_awb_whisper_catalog "$name")"
        fields="$(awk -F'|' '{print NF}' <<<"$entry")"
        [ "$fields" -eq 4 ] || { echo "'$name' has ${fields} fields, expected 4: ${entry}"; return 1; }
    done
}

@test "every entry names a repo as owner/name" {
    for name in $LLM_MODELS; do
        repo="$(_awb_model_catalog "$name" | cut -d'|' -f1)"
        [[ "$repo" == */* ]] || { echo "'$name' repo_id is not owner/name: ${repo}"; return 1; }
        [[ "$repo" != */*/* ]] || { echo "'$name' repo_id has too many segments: ${repo}"; return 1; }
    done
    for name in $WHISPER_MODELS; do
        repo="$(_awb_whisper_catalog "$name" | cut -d'|' -f1)"
        [[ "$repo" == */* ]] || { echo "'$name' repo_id is not owner/name: ${repo}"; return 1; }
    done
}

@test "no field is blank in any entry" {
    for name in $LLM_MODELS; do
        entry="$(_awb_model_catalog "$name")"
        for f in 1 2 3 4; do
            value="$(cut -d'|' -f"$f" <<<"$entry")"
            [ -n "$value" ] || { echo "'$name' field ${f} is empty: ${entry}"; return 1; }
        done
    done
}

@test "LLM filenames end in .gguf — the only format llama.cpp loads" {
    for name in $LLM_MODELS; do
        file="$(_awb_model_catalog "$name" | cut -d'|' -f2)"
        [[ "$file" == *.gguf ]] || { echo "'$name' filename is not a .gguf: ${file}"; return 1; }
    done
}

@test "whisper filenames are ggml .bin files, not GGUF" {
    # whisper.cpp loads GGML, and these land in a different directory than the
    # LLM catalog — mixing the two formats up silently installs an unusable file.
    for name in $WHISPER_MODELS; do
        file="$(_awb_whisper_catalog "$name" | cut -d'|' -f2)"
        [[ "$file" == ggml-*.bin ]] || { echo "'$name' filename is not a ggml .bin: ${file}"; return 1; }
    done
}

@test "no filename contains a path separator" {
    # awb_hf_download joins dest_dir and filename; a slash here would escape
    # the models directory.
    for name in $LLM_MODELS; do
        file="$(_awb_model_catalog "$name" | cut -d'|' -f2)"
        [[ "$file" != */* ]] || { echo "'$name' filename contains a slash: ${file}"; return 1; }
    done
    for name in $WHISPER_MODELS; do
        file="$(_awb_whisper_catalog "$name" | cut -d'|' -f2)"
        [[ "$file" != */* ]] || { echo "'$name' filename contains a slash: ${file}"; return 1; }
    done
}

# Heuristic, and the only one here: Hugging Face paths are case-sensitive, and
# an all-lowercase filename under a repo whose model name carries uppercase is
# how both the qwen3 and deepseek-coder-v2 entries were wrong — "Qwen3-8B-GGUF"
# paired with "qwen3-8b-q4_k_m.gguf", which 404s. If a future entry is
# legitimately lowercase under a mixed-case repo, skip this test for it rather
# than weakening the rule.
@test "filename casing is consistent with the repo name it lives under" {
    for name in $LLM_MODELS; do
        entry="$(_awb_model_catalog "$name")"
        repo_model="$(cut -d'|' -f1 <<<"$entry" | cut -d'/' -f2)"
        file="$(cut -d'|' -f2 <<<"$entry")"
        # Only meaningful when the repo itself has uppercase to be consistent with.
        [[ "$repo_model" =~ [A-Z] ]] || continue
        [[ "$file" =~ [A-Z] ]] || {
            echo "'$name': repo '${repo_model}' is mixed-case but filename '${file}' is all lowercase"
            return 1
        }
    done
}

@test "every size field parses as a number with a unit" {
    for name in $LLM_MODELS; do
        size="$(_awb_model_catalog "$name" | cut -d'|' -f3)"
        [[ "$size" =~ ^~?[0-9]+(\.[0-9]+)?(MB|GB)$ ]] || { echo "'$name' size is unparseable: ${size}"; return 1; }
    done
    for name in $WHISPER_MODELS; do
        size="$(_awb_whisper_catalog "$name" | cut -d'|' -f3)"
        [[ "$size" =~ ^~?[0-9]+(\.[0-9]+)?(MB|GB)$ ]] || { echo "'$name' size is unparseable: ${size}"; return 1; }
    done
}

# --- catalog / listing agreement ------------------------------------------

@test "model_catalog_list prints every LLM and whisper name" {
    run model_catalog_list
    [ "$status" -eq 0 ]
    for name in $LLM_MODELS $WHISPER_MODELS; do
        [[ "$output" == *"$name"* ]] || { echo "'$name' missing from model_catalog_list output"; return 1; }
    done
}

@test "model_catalog_list iterates exactly the names the catalogs define" {
    # Guards the duplicated name list inside model_catalog_list: adding a
    # catalog entry without adding it there leaves it undiscoverable.
    listed="$(sed -n 's/^ *for name in \(.*\); do$/\1/p' "${AWB_ROOT}/models/install.sh")"
    [[ "$listed" == *"$LLM_MODELS"* ]]
    [[ "$listed" == *"$WHISPER_MODELS"* ]]
}

# --- the default model ----------------------------------------------------

@test "DEFAULT_MODEL in config.env exists in the catalog" {
    # section_models installs this name on every clean run; if it is not in the
    # catalog, the install aborts at the last step of a long build.
    default="$(sed -n 's/^DEFAULT_MODEL=//p' "${AWB_ROOT}/config.env" | tr -d '"'"'"' ')"
    [ -n "$default" ]
    run _awb_model_catalog "$default"
    [ "$status" -eq 0 ] || { echo "DEFAULT_MODEL='${default}' is not in the catalog"; return 1; }
}

@test "AWB_DEFAULT_GGUF in config.env matches the DEFAULT_MODEL filename" {
    # section_benchmark and the systemd unit both build a path from
    # AWB_DEFAULT_GGUF; if it disagrees with what section_models downloaded,
    # the benchmark silently skips and llama-server fails to start.
    default="$(sed -n 's/^DEFAULT_MODEL=//p' "${AWB_ROOT}/config.env" | tr -d '"'"'"' ')"
    declared="$(sed -n 's/^AWB_DEFAULT_GGUF=//p' "${AWB_ROOT}/config.env" | tr -d '"'"'"' ')"
    [ -n "$declared" ] || skip "AWB_DEFAULT_GGUF not set in config.env"
    actual="$(_awb_model_catalog "$default" | cut -d'|' -f2)"
    [ "$declared" = "$actual" ] || { echo "AWB_DEFAULT_GGUF='${declared}' but catalog says '${actual}'"; return 1; }
}

# --- model_install dispatch -----------------------------------------------

@test "model_install: rejects an unknown name instead of downloading something" {
    run model_install definitely-not-a-model
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown model"* ]]
}

@test "model_install: a whisper name routes to the whisper directory" {
    # Regression guard for the dispatch in model_install: whisper models must
    # not land in models/gguf, which is where benchmarks and llama.cpp look.
    awb_hf_download() { echo "DEST=$3"; }
    run model_install whisper-base.en
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEST=${AI_HOME}/models/whisper"* ]]
}

@test "model_install: an LLM name routes to the gguf directory" {
    awb_hf_download() { echo "DEST=$3"; }
    run model_install gemma3-e2b
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEST=${AI_HOME}/models/gguf"* ]]
}

@test "model_install: custom passes the caller's repo and filename straight through" {
    awb_hf_download() { echo "REPO=$1 FILE=$2 DEST=$3"; }
    run model_install custom some-org/some-repo some-file.gguf
    [ "$status" -eq 0 ]
    [[ "$output" == *"REPO=some-org/some-repo"* ]]
    [[ "$output" == *"FILE=some-file.gguf"* ]]
}

@test "DEFAULT_WHISPER_MODEL in config.env exists in the whisper catalog" {
    # section_models installs this alongside DEFAULT_MODEL whenever
    # INSTALL_WHISPER is on, so a typo here aborts a clean install at the very
    # last download. Empty is legal and means "build whisper.cpp without a model".
    default="$(sed -n 's/^DEFAULT_WHISPER_MODEL=//p' "${AWB_ROOT}/config.env" | tr -d '"'"'"' ')"
    [ -n "$default" ] || skip "DEFAULT_WHISPER_MODEL deliberately empty"
    run _awb_whisper_catalog "$default"
    [ "$status" -eq 0 ] || { echo "DEFAULT_WHISPER_MODEL='${default}' is not in the whisper catalog"; return 1; }
}

@test "DEFAULT_WHISPER_MODEL is the model benchmarks/whisper expects" {
    # benchmarks/whisper/run.sh defaults to base.en; shipping a different
    # default would leave `awb benchmark whisper` broken out of the box.
    default="$(sed -n 's/^DEFAULT_WHISPER_MODEL=//p' "${AWB_ROOT}/config.env" | tr -d '"'"'"' ')"
    [ -n "$default" ] || skip "DEFAULT_WHISPER_MODEL deliberately empty"
    file="$(_awb_whisper_catalog "$default" | cut -d'|' -f2)"
    grep -q "$file" "${AWB_ROOT}/benchmarks/whisper/run.sh" \
        || { echo "benchmarks/whisper/run.sh does not reference '${file}'"; return 1; }
}
