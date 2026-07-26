#!/usr/bin/env bash
# platforms/intel/openvino.sh — OpenVINO runtime, installed via pip into the
# dedicated 'openvino' venv (see python/create_envs.sh) rather than system-wide.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_intel_openvino() {
    log_step "Installing OpenVINO runtime"

    local venv="$HOME/venvs/openvino"
    if [[ ! -d "$venv" ]]; then
        fail_loud "openvino venv not found at ${venv}. Run './install.sh --only python' first, or './install.sh' for a full install."
    fi

    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    pip install --upgrade pip --quiet
    pip install "openvino>=2024.0" "openvino-dev>=2024.0" \
        || fail_loud "Failed to pip install openvino into $venv"
    deactivate

    log_ok "OpenVINO installed into venv: $venv"
}
