#!/usr/bin/env bash
# platforms/cpu/openblas.sh — OpenBLAS, used by llama.cpp's CPU backend.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_cpu_openblas() {
    log_step "Installing OpenBLAS"

    sudo apt-get update -y || fail_loud "apt-get update failed"
    sudo apt-get install -y libopenblas-dev || fail_loud "Failed to install libopenblas-dev"

    log_ok "OpenBLAS installed."
}
