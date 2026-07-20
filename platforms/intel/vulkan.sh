#!/usr/bin/env bash
# platforms/intel/vulkan.sh — Mesa ANV Vulkan driver for Intel iGPUs/Arc.
# This is the practical acceleration path for llama.cpp on Intel iGPUs
# (Meteor Lake, Arc, Lunar Lake, Battlemage, Arrow Lake); the XPU/SYCL path
# is intentionally not used here (see docs/PRINCIPLES.md).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_intel_vulkan() {
    log_step "Installing Vulkan (Mesa ANV) for Intel GPU"

    if has_cmd vulkaninfo && vulkaninfo --summary >/dev/null 2>&1; then
        log_ok "Vulkan already functional, skipping."
        return 0
    fi

    sudo apt-get update -y || fail_loud "apt-get update failed"
    sudo apt-get install -y \
        mesa-vulkan-drivers \
        vulkan-tools \
        libvulkan1 \
        mesa-utils \
        || fail_loud "Failed to install Mesa/Vulkan packages"

    if ! (vulkaninfo --summary >/dev/null 2>&1); then
        fail_loud "Vulkan installed but vulkaninfo reports no usable device. Check that the iGPU is enabled in BIOS and the user is in the 'render' group (sudo usermod -aG render \$USER, then re-login)."
    fi

    log_ok "Vulkan (Mesa ANV) functional."
}
