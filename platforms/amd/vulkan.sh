#!/usr/bin/env bash
# platforms/amd/vulkan.sh — Mesa RADV Vulkan driver for AMD GPUs.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_amd_vulkan() {
    log_step "Installing Vulkan (Mesa RADV) for AMD GPU"

    if has_cmd vulkaninfo && vulkaninfo --summary >/dev/null 2>&1; then
        log_ok "Vulkan already functional, skipping."
        return 0
    fi

    sudo apt-get update -y || fail_loud "apt-get update failed"
    sudo apt-get install -y mesa-vulkan-drivers vulkan-tools libvulkan1 mesa-utils \
        || fail_loud "Failed to install Mesa/Vulkan packages"

    vulkaninfo --summary >/dev/null 2>&1 \
        || fail_loud "Vulkan installed but no usable device detected. Check BIOS GPU settings and 'render' group membership."

    log_ok "Vulkan (Mesa RADV) functional."
}
