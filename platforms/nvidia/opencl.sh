#!/usr/bin/env bash
# platforms/nvidia/opencl.sh — OpenCL via the NVIDIA driver (installed by
# cuda.sh); this installs the diagnostic tool and verifies the ICD answers.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_nvidia_opencl() {
    log_step "Verifying OpenCL on NVIDIA"

    sudo apt-get install -y clinfo ocl-icd-libopencl1 \
        || fail_loud "Failed to install clinfo"

    if has_cmd clinfo && clinfo -l 2>/dev/null | grep -qi nvidia; then
        log_ok "OpenCL functional via NVIDIA driver."
    else
        log_warn "OpenCL packages installed but no NVIDIA platform detected by clinfo. This is non-fatal; CUDA remains the primary acceleration path."
    fi
}
