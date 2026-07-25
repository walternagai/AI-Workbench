#!/usr/bin/env bash
# runtimes/onnxruntime/install.sh — ONNX Runtime, with the execution
# provider matched to the detected platform (CUDA / ROCm / OpenVINO / CPU).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_onnxruntime() {
    log_step "Installing ONNX Runtime"

    local venv="$HOME/venvs/vision"
    [[ -d "$venv" ]] || fail_loud "vision venv missing; run python/create_envs.sh first."

    local package="onnxruntime"
    case "${PLATFORM_TARGET:-cpu}" in
        nvidia) package="onnxruntime-gpu" ;;
        intel)  package="onnxruntime-openvino" ;;
        *)      package="onnxruntime" ;;
    esac

    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    pip install "$package" \
        || fail_loud "Failed to install $package"
    deactivate

    log_ok "ONNX Runtime installed (package: ${package})"
}
