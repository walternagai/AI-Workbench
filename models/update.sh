#!/usr/bin/env bash
# models/update.sh — refresh installed models. Since model weights rarely
# change in place upstream, "update" primarily means: re-check for a newer
# quantization/revision in the catalog and let the user opt in.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

AWB_MODELS_DIR="${AI_HOME:-$HOME/ai}/models/gguf"
AWB_WHISPER_MODELS_DIR="${AI_HOME:-$HOME/ai}/models/whisper"

# _list_models_in <label> <dir> <glob> — print installed models of one kind.
# Returns 1 if none were found, so the caller can tell "nothing installed
# anywhere" apart from "nothing of this kind".
_list_models_in() {
    local label="$1" dir="$2" pattern="$3"
    local -a files=()
    while IFS= read -r -d '' f; do files+=("$f"); done \
        < <(find "$dir" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)

    (( ${#files[@]} > 0 )) || return 1

    printf '  %s:\n' "$label"
    local f
    for f in "${files[@]}"; do
        printf '    %-10s %s\n' "$(du -h "$f" | cut -f1)" "$(basename "$f")"
    done
}

model_update_all() {
    log_step "Checking installed models"

    ensure_dir "$AWB_MODELS_DIR"
    ensure_dir "$AWB_WHISPER_MODELS_DIR"

    # Collect first so the "Installed models:" header is only printed when
    # there is actually something to list. The `|| true` guards are required:
    # _list_models_in returns 1 when a directory holds no models, which under
    # `set -e` would otherwise abort the whole script via the assignment's
    # exit status whenever the last listed kind happens to be empty.
    local listing
    listing="$(
        _list_models_in "LLM (GGUF)" "$AWB_MODELS_DIR" '*.gguf' || true
        _list_models_in "Speech (whisper.cpp GGML)" "$AWB_WHISPER_MODELS_DIR" '*.bin' || true
    )"

    if [[ -z "$listing" ]]; then
        log_info "No models installed yet. Use: awb model install <name>"
        return 0
    fi

    log_info "Installed models:"
    printf '%s\n' "$listing"

    log_info "AI-Workbench does not silently overwrite installed model files. To pull a fresh copy, remove it first (awb model remove <file>) then re-install."
}
