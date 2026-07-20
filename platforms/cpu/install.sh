#!/usr/bin/env bash
# platforms/cpu/install.sh — always installed, regardless of detected GPU,
# since every runtime needs a working CPU fallback path.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

# shellcheck source=platforms/cpu/onednn.sh
source "${AWB_ROOT}/platforms/cpu/onednn.sh"
# shellcheck source=platforms/cpu/openblas.sh
source "${AWB_ROOT}/platforms/cpu/openblas.sh"
# shellcheck source=platforms/cpu/mkl.sh
source "${AWB_ROOT}/platforms/cpu/mkl.sh"

install_cpu_platform() {
    log_step "CPU platform: ${CPU_VENDOR:-unknown} ${CPU_MODEL:-}"

    install_cpu_openblas
    install_cpu_onednn
    install_cpu_mkl

    log_ok "CPU platform stack installed."
}
