#!/usr/bin/env bash
# platforms/amd/hip.sh — HIP compiler + rocBLAS/MIOpen math libraries.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_amd_hip() {
    log_step "Installing HIP + rocBLAS + MIOpen"

    sudo apt-get install -y hip-runtime-amd rocblas miopen-hip \
        || fail_loud "Failed to install HIP/rocBLAS/MIOpen packages"

    log_ok "HIP toolchain and math libraries installed."
}
