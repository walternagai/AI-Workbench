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

    if dpkg -l | grep -q '^ii  nvidia-cudnn'; then
        log_ok "nvidia-cudnn already installed; skipping cuDNN 9 metapackage to avoid conflicts."
        return 0
    fi
    if dpkg -l | grep -q '^ii  libcudnn9-dev-cuda-'; then
        log_ok "libcudnn9-dev-cuda-* already installed; skipping."
        return 0
    fi

    local cuda_major="" pkg="libcudnn8"
    if has_cmd nvcc; then
        cuda_major="$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9]+')"
    fi
    [[ -n "$cuda_major" ]] && pkg="cudnn9-cuda-${cuda_major}"

    # nvidia-cudnn (Ubuntu repo) and cudnn9-cuda-12 (NVIDIA repo) both own
    # /usr/lib/x86_64-linux-gnu/libcudnn.so — installing the 9.x metapackage
    # over the legacy 8.9 package makes dpkg abort mid-unpack, which leaves
    # the whole apt state inconsistent and takes every later install down.
    # The version check is belt-and-braces on top of the guard above, and the
    # conflict check keeps this section best-effort: skip rather than break.
    if apt-cache policy "$pkg" 2>/dev/null | grep -q 'Candidate:'; then
        local cand
        cand=$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/{print $2; exit}')
        if [[ "$cand" =~ ^9\.[0-9]+ ]] \
            && dpkg -l nvidia-cudnn 2>/dev/null | grep -q '^ii'; then
            log_warn "cuDNN 9 ($cand) conflicts with the installed legacy nvidia-cudnn; keeping 8.9 (PyTorch's bundled cuDNN via pip is used for fine-tuning)."
            log_ok "cuDNN step complete (best-effort)."
            return 0
        fi
        sudo apt-get install -y "$pkg" 2>/dev/null \
            || log_warn "${pkg} not found in configured apt sources; PyTorch's bundled cuDNN (via pip) will be used instead for fine-tuning workflows. Non-fatal."
    else
        log_warn "${pkg} not found in configured apt sources; PyTorch's bundled cuDNN (via pip) will be used instead for fine-tuning workflows. Non-fatal."
    fi

    log_ok "cuDNN step complete (best-effort)."
}
