#!/usr/bin/env bash
# platforms/nvidia/cuda.sh — NVIDIA driver + CUDA Toolkit.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_nvidia_cuda() {
    log_step "Installing NVIDIA driver + CUDA Toolkit"

    if has_cmd nvidia-smi && nvidia-smi >/dev/null 2>&1; then
        log_ok "NVIDIA driver already functional ($(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1))."
    else
        sudo apt-get update -y || fail_loud "apt-get update failed"
        sudo ubuntu-drivers autoinstall \
            || fail_loud "ubuntu-drivers autoinstall failed. Install the NVIDIA driver manually and re-run."
        log_warn "NVIDIA driver installed. A REBOOT is required before CUDA can be used."
    fi

    if ! has_cmd nvcc; then
        log_info "Installing CUDA Toolkit..."
        sudo apt-get install -y nvidia-cuda-toolkit \
            || fail_loud "Failed to install nvidia-cuda-toolkit"
    else
        log_ok "CUDA Toolkit already present: $(nvcc --version | tail -1)"
    fi

    log_ok "NVIDIA/CUDA step complete."
}
