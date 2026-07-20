#!/usr/bin/env bash
# models/update.sh — refresh installed models. Since GGUF files rarely
# change in place upstream, "update" primarily means: re-check for a newer
# quantization/revision in the catalog and let the user opt in.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

AWB_MODELS_DIR="${AI_HOME:-$HOME/ai}/models/gguf"

model_update_all() {
    log_step "Checking installed models"

    ensure_dir "$AWB_MODELS_DIR"
    if [[ -z "$(ls -A "$AWB_MODELS_DIR" 2>/dev/null)" ]]; then
        log_info "No models installed yet. Use: awb model install <name>"
        return 0
    fi

    log_info "Installed models:"
    du -h "$AWB_MODELS_DIR"/*.gguf 2>/dev/null | while read -r size path; do
        printf '  %-10s %s\n' "$size" "$(basename "$path")"
    done

    log_info "AI-Workbench does not silently overwrite installed GGUF files. To pull a fresh copy, remove it first (awb model remove <file>) then re-install."
}
