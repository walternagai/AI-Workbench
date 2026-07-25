#!/usr/bin/env bash
# platforms/cpu/mkl.sh — Intel MKL, only installed when the CPU is Intel
# (it's a no-op, non-fatal skip on AMD/other CPUs).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_cpu_mkl() {
    log_step "Installing Intel MKL (when compatible)"

    if [[ "${CPU_VENDOR:-}" != "Intel" ]]; then
        log_info "CPU vendor is ${CPU_VENDOR:-unknown}, not Intel; MKL is not applicable. Skipping."
        return 0
    fi

    local venv="$HOME/venvs/core"
    if [[ -d "$venv" ]]; then
        # shellcheck disable=SC1091
        source "$venv/bin/activate"
        pip install mkl mkl-include \
            || log_warn "pip install of mkl failed; continuing without it (non-fatal, OpenBLAS remains available)."
        deactivate
    else
        log_warn "core venv not found yet; skipping MKL pip install (will still work via OpenBLAS)."
    fi

    log_ok "Intel MKL step complete."
}
