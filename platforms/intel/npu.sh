#!/usr/bin/env bash
# platforms/intel/npu.sh — Intel NPU driver/runtime (Meteor Lake and newer).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_intel_npu() {
    log_step "Installing Intel NPU driver"

    if [[ "${HAS_INTEL_NPU:-false}" != "true" ]]; then
        log_info "No Intel NPU detected on this system; skipping."
        return 0
    fi

    apt_update_once
    sudo apt-get install -y intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu level-zero \
        || log_warn "NPU packages not found in configured apt sources. The 'intel/npu-driver' PPA/repo may need to be added manually; see docs/PLATFORM_INTEL.md. Continuing without NPU acceleration."

    log_ok "Intel NPU setup step complete (best-effort)."
}
