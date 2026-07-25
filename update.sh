#!/usr/bin/env bash
# update.sh — updates AI-Workbench itself (git pull, if cloned) and, on
# request, the installed runtimes and models. Facilitates updates without
# requiring a full reinstall (see docs/PRINCIPLES.md — selective re-execution).
set -euo pipefail

AWB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWB_ROOT

# shellcheck source=lib/colors.sh
source "${AWB_ROOT}/lib/colors.sh"
# shellcheck source=lib/logger.sh
source "${AWB_ROOT}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${AWB_ROOT}/lib/utils.sh"
# shellcheck source=lib/downloader.sh
source "${AWB_ROOT}/lib/downloader.sh"

load_env "${AWB_ROOT}/config.env" false

UPDATE_SELF=true
UPDATE_RUNTIMES=false
UPDATE_MODELS=false

for arg in "$@"; do
    case "$arg" in
        --runtimes) UPDATE_RUNTIMES=true ;;
        --models)   UPDATE_MODELS=true ;;
        --all)      UPDATE_RUNTIMES=true; UPDATE_MODELS=true ;;
        --no-self)  UPDATE_SELF=false ;;
        -h|--help)
            cat <<EOF
Usage: update.sh [--runtimes] [--models] [--all] [--no-self]

  (no args)    Update AI-Workbench itself only
  --runtimes   Also update llama.cpp, Ollama, OpenVINO, ONNX Runtime, whisper.cpp
               (each gated by its INSTALL_* flag in config.env)
  --models     Show installed models / update guidance
  --all        Equivalent to --runtimes --models
  --no-self    Skip updating AI-Workbench itself
EOF
            exit 0 ;;
        *) fail_loud "Unknown argument: $arg" ;;
    esac
done

update_self() {
    log_step "Updating AI-Workbench Core"
    if [[ -d "${AWB_ROOT}/.git" ]]; then
        git -C "$AWB_ROOT" pull --ff-only || fail_loud "Could not fast-forward AI-Workbench; resolve local changes first."
        log_ok "AI-Workbench updated."
    else
        log_warn "AI-Workbench was not installed via git clone; skipping self-update. Re-download the release to update."
    fi
}

update_runtimes() {
    log_step "Updating runtimes"
    safe_source "${AWB_ROOT}/detect.sh"
    declare -F run_all_detections &>/dev/null || fail_loud "detect.sh loaded but run_all_detections() not found"
    declare -F resolve_platform_target &>/dev/null || fail_loud "detect.sh loaded but resolve_platform_target() not found"
    run_all_detections
    resolve_platform_target

    is_true "${INSTALL_LLAMACPP:-true}" \
        && { safe_source "${AWB_ROOT}/runtimes/llama.cpp/install.sh"; update_llama_cpp; }

    is_true "${INSTALL_OLLAMA:-true}" && has_cmd ollama \
        && { safe_source "${AWB_ROOT}/runtimes/ollama/install.sh"; update_ollama; }

    is_true "${INSTALL_OPENVINO:-true}" \
        && { safe_source "${AWB_ROOT}/runtimes/openvino/install.sh"; update_openvino_runtime; }

    is_true "${INSTALL_ONNXRUNTIME:-true}" \
        && { safe_source "${AWB_ROOT}/runtimes/onnxruntime/install.sh"; update_onnxruntime; }

    is_true "${INSTALL_WHISPER:-true}" \
        && { safe_source "${AWB_ROOT}/runtimes/whisper/install.sh"; update_whisper_cpp; }
}

update_models() {
    log_step "Checking models"
    safe_source "${AWB_ROOT}/models/update.sh"
    model_update_all
}

main() {
    trap 'log_info "Update interrupted."; exit 1' INT TERM
    is_true "$UPDATE_SELF" && update_self
    is_true "$UPDATE_RUNTIMES" && update_runtimes
    is_true "$UPDATE_MODELS" && update_models
    log_ok "Update complete."
}

main
