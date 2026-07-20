#!/usr/bin/env bash
# platforms/intel/gpu.sh — base Intel GPU tools (metrics, firmware, groups).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_intel_gpu_tools() {
    log_step "Installing Intel GPU Tools"

    sudo apt-get update -y || fail_loud "apt-get update failed"
    sudo apt-get install -y intel-gpu-tools || fail_loud "Failed to install intel-gpu-tools"

    # The render group is required for unprivileged Vulkan/OpenCL access
    # to /dev/dri/renderD*. Add the invoking user idempotently.
    local user="${SUDO_USER:-$USER}"
    if ! id -nG "$user" | grep -qw render; then
        sudo usermod -aG render "$user" \
            && log_warn "Added $user to the 'render' group. Log out and back in for it to take effect."
    else
        log_ok "$user already in 'render' group."
    fi

    log_ok "Intel GPU tools installed."
}
