#!/usr/bin/env bash
# platforms/amd/install.sh — orchestrates the AMD platform stack.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

# shellcheck source=platforms/amd/vulkan.sh
source "${AWB_ROOT}/platforms/amd/vulkan.sh"
# shellcheck source=platforms/amd/rocm.sh
source "${AWB_ROOT}/platforms/amd/rocm.sh"
# shellcheck source=platforms/amd/hip.sh
source "${AWB_ROOT}/platforms/amd/hip.sh"

install_amd_platform() {
    log_step "AMD platform: ${GPU_MODEL:-unknown}"

    install_amd_vulkan   # primary acceleration path for llama.cpp
    install_amd_rocm     # needed for PyTorch/fine-tuning workflows
    install_amd_hip

    log_ok "AMD platform stack installed."
}
