#!/usr/bin/env bash
# runtimes/ollama/install.sh — installs Ollama via the official install script.
# Note (per Walter's hardware notes): on Intel iGPUs without a Vulkan backend
# in Ollama's engine, this runs CPU-only. NVIDIA/AMD get GPU acceleration
# out of the box once drivers (cuda.sh/rocm.sh) are installed.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_ollama() {
    log_step "Installing Ollama"

    if has_cmd ollama; then
        log_ok "Ollama already installed ($(ollama --version 2>/dev/null | head -1))."
    else
        require_cmd curl "Ollama installer"
        curl -fsSL https://ollama.com/install.sh | sh \
            || fail_loud "Ollama install script failed"
    fi

    if [[ "${PLATFORM_TARGET:-}" == "intel" && "${HAS_INTEL_ARC:-false}" != "false" ]]; then
        log_warn "Ollama has no Vulkan backend for Intel iGPUs on this stack; it will run CPU-only here. Prefer llama.cpp (Vulkan) for GPU-accelerated inference on this hardware."
    fi

    systemctl is-active --quiet ollama 2>/dev/null \
        && log_ok "ollama systemd service is active." \
        || log_warn "ollama systemd service not active; start with: sudo systemctl enable --now ollama"
}

update_ollama() {
    log_step "Updating Ollama"
    curl -fsSL https://ollama.com/install.sh | sh || fail_loud "Ollama update failed"
}

remove_ollama() {
    log_step "Removing Ollama"
    sudo systemctl stop ollama 2>/dev/null || true
    sudo systemctl disable ollama 2>/dev/null || true
    sudo rm -f /usr/local/bin/ollama /usr/bin/ollama
    log_ok "Ollama removed (models under ~/.ollama left intact; delete manually if desired)."
}
