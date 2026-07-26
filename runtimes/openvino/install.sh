#!/usr/bin/env bash
# runtimes/openvino/install.sh — OpenVINO Model Server / GenAI runtime,
# layered on top of platforms/intel/openvino.sh (which handles the pip install).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_openvino_runtime() {
    log_step "Installing OpenVINO GenAI runtime"

    local venv="$HOME/venvs/openvino"
    [[ -d "$venv" ]] || fail_loud "openvino venv missing at ${venv}. Run './install.sh --only python' first, or './install.sh' for a full install."

    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    pip install "openvino-genai>=2024.0" \
        || fail_loud "Failed to install openvino-genai"
    deactivate

    log_ok "OpenVINO GenAI runtime installed."
}

update_openvino_runtime() {
    log_step "Updating OpenVINO GenAI runtime"

    local venv="$HOME/venvs/openvino"
    [[ -d "$venv" ]] || fail_loud "openvino venv missing; run install first."

    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    pip install --upgrade "openvino-genai>=2024.0" \
        || fail_loud "Failed to update openvino-genai"
    deactivate

    log_ok "OpenVINO GenAI runtime updated."
}
