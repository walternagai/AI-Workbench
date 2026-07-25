#!/usr/bin/env bash
# platforms/nvidia/cudnn.sh — cuDNN libraries for deep-learning frameworks.
#
# cuDNN 9 packages are suffixed by CUDA major version (cudnn9-cuda-12, not
# a single universal "libcudnn8" — that name is cuDNN 8-era, matched to
# CUDA 11, and doesn't exist for the CUDA 12.x that cuda.sh installs on
# current Ubuntu/Pop!_OS). Only available via NVIDIA's own apt repo (see
# repo.sh) — never in Ubuntu's own repos.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_nvidia_cudnn() {
    log_step "Installing cuDNN"

    _ensure_nvidia_cuda_apt_repo || true

    local cuda_major="" pkg="libcudnn8"
    if has_cmd nvcc; then
        cuda_major="$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9]+')"
    fi
    [[ -n "$cuda_major" ]] && pkg="cudnn9-cuda-${cuda_major}"

    sudo apt-get install -y "$pkg" 2>/dev/null \
        || log_warn "${pkg} not found in configured apt sources; PyTorch's bundled cuDNN (via pip) will be used instead for fine-tuning workflows. Non-fatal."

    log_ok "cuDNN step complete (best-effort)."
}
