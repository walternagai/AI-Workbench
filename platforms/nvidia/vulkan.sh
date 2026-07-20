#!/usr/bin/env bash
# platforms/nvidia/vulkan.sh — Vulkan via the proprietary NVIDIA driver
# (installed by cuda.sh); this just verifies + fills gaps with vulkan-tools.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_nvidia_vulkan() {
    log_step "Verifying Vulkan on NVIDIA"

    sudo apt-get install -y vulkan-tools libvulkan1 || fail_loud "Failed to install vulkan-tools"

    if has_cmd vulkaninfo && vulkaninfo --summary >/dev/null 2>&1; then
        log_ok "Vulkan functional via NVIDIA driver."
    else
        log_warn "Vulkan not yet functional — this is expected if the NVIDIA driver hasn't been installed/reloaded yet. Re-run doctor.sh after a reboot."
    fi
}
