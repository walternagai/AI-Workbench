#!/usr/bin/env bash
# platforms/nvidia/tensorrt.sh — TensorRT for optimized inference (optional).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_nvidia_tensorrt() {
    log_step "Installing TensorRT (optional)"

    if ! is_true "${INSTALL_TENSORRT:-false}"; then
        log_info "INSTALL_TENSORRT is not enabled in config.env; skipping."
        return 0
    fi

    # TensorRT is only distributed through NVIDIA's own apt repo, never
    # Ubuntu's — never available without this (see repo.sh).
    _ensure_nvidia_cuda_apt_repo || true

    sudo apt-get install -y tensorrt python3-libnvinfer-dev \
        || log_warn "TensorRT install failed; continuing without it (non-fatal)."

    log_ok "TensorRT step complete."
}
