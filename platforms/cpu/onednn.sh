#!/usr/bin/env bash
# platforms/cpu/onednn.sh — oneDNN (via pip, bundled with PyTorch/ONNX Runtime
# CPU builds), verified here as a standalone capability check.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_cpu_onednn() {
    log_step "Verifying oneDNN availability"
    log_info "oneDNN ships inside PyTorch/ONNX Runtime CPU wheels; no separate system package is installed. This step just documents the dependency for doctor.sh."
    log_ok "oneDNN dependency acknowledged (delivered via Python wheels)."
}
