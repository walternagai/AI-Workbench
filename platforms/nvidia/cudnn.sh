#!/usr/bin/env bash
# platforms/nvidia/cudnn.sh — cuDNN libraries for deep-learning frameworks.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_nvidia_cudnn() {
    log_step "Installing cuDNN"

    sudo apt-get install -y libcudnn8 libcudnn8-dev 2>/dev/null \
        || log_warn "libcudnn8 not found in configured apt sources; PyTorch's bundled cuDNN (via pip) will be used instead for fine-tuning workflows. Non-fatal."

    log_ok "cuDNN step complete (best-effort)."
}
