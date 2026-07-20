#!/usr/bin/env bash
# platforms/intel/opencl.sh — Intel Compute Runtime (OpenCL) for iGPU/Arc.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_intel_opencl() {
    log_step "Installing Intel OpenCL Runtime"

    sudo apt-get update -y || fail_loud "apt-get update failed"
    sudo apt-get install -y \
        intel-opencl-icd \
        clinfo \
        ocl-icd-libopencl1 \
        || fail_loud "Failed to install Intel OpenCL packages"

    if has_cmd clinfo && clinfo -l 2>/dev/null | grep -qi intel; then
        log_ok "Intel OpenCL runtime functional."
    else
        log_warn "OpenCL packages installed but no Intel platform detected by clinfo. This is non-fatal; Vulkan remains the primary acceleration path."
    fi
}
