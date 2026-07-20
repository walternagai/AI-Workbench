#!/usr/bin/env bash
# platforms/intel/oneapi.sh — oneAPI runtime (opportunistic, best-effort).
#
# Design note: full oneAPI toolkit installs are heavyweight and mostly
# unnecessary for local LLM inference (llama.cpp uses Vulkan, not SYCL,
# on iGPUs in this stack). We only install the redistributable runtime
# libraries when the apt repo is already configured, and never fail the
# overall install if it's unavailable.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_intel_oneapi_runtime() {
    log_step "Installing oneAPI runtime (optional)"

    if ! apt-cache search intel-oneapi-runtime-opencl 2>/dev/null | grep -q .; then
        log_warn "oneAPI apt repository not configured; skipping (non-fatal). See docs/PLATFORM_INTEL.md to add it manually if needed."
        return 0
    fi

    sudo apt-get install -y intel-oneapi-runtime-opencl intel-oneapi-runtime-compilers \
        || log_warn "oneAPI runtime install failed; continuing without it (non-fatal)."

    log_ok "oneAPI runtime step complete (best-effort)."
}
