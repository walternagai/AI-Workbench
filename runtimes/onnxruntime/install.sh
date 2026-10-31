#!/usr/bin/env bash
# runtimes/onnxruntime/install.sh — ONNX Runtime, with the execution
# provider matched to the detected platform (CUDA / ROCm / OpenVINO / CPU).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_onnxruntime() {
    log_step "Installing ONNX Runtime"

    local venv="$HOME/venvs/vision"
    [[ -d "$venv" ]] || fail_loud "vision venv missing at ${venv}. Run './install.sh --only python' first, or './install.sh' for a full install."

    local package
    package="$(onnxruntime_package_for "${PLATFORM_TARGET:-cpu}")"

    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    pip install "$package" \
        || fail_loud "Failed to install $package"
    deactivate

    log_ok "ONNX Runtime installed (package: ${package})"
}

update_onnxruntime() {
    log_step "Updating ONNX Runtime"

    local venv="$HOME/venvs/vision"
    [[ -d "$venv" ]] || fail_loud "vision venv missing; run install first."

    local package
    package="$(onnxruntime_package_for "${PLATFORM_TARGET:-cpu}")"

    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    pip install --upgrade "$package" \
        || fail_loud "Failed to update $package"
    deactivate

    log_ok "ONNX Runtime updated (package: ${package})"
}
