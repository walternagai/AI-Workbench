#!/usr/bin/env bash
# platforms/intel/npu.sh — Intel NPU driver (Meteor Lake and newer).
#
# Distribution note: unlike oneAPI, Intel does not publish an apt repository
# for the NPU driver — it ships prebuilt .deb packages as GitHub release
# tarballs, one per supported Ubuntu release (see docs/PLATFORM_INTEL.md).
# Best-effort: if the current Ubuntu release isn't covered by the latest
# upstream release, this warns and continues rather than failing the
# overall install (per docs/PRINCIPLES.md §1 — NPU is a non-critical path).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

AWB_NPU_GH_REPO="intel/linux-npu-driver"
AWB_NPU_SRC="${AI_HOME:-$HOME/ai}/src/intel-npu-driver"

install_intel_npu() {
    log_step "Installing Intel NPU driver"

    if [[ "${HAS_INTEL_NPU:-false}" != "true" ]]; then
        log_info "No Intel NPU detected on this system; skipping."
        return 0
    fi

    if dpkg -s intel-driver-compiler-npu &>/dev/null; then
        log_ok "Intel NPU driver already installed."
        return 0
    fi

    require_cmd curl "fetching the NPU driver release"

    # Upstream names release assets like "...-ubuntu2404.tar.gz" — one
    # tarball per Ubuntu release, not a version-agnostic apt package.
    local asset_tag="ubuntu${OS_VERSION//./}"
    local asset_url=""
    asset_url="$(curl -fsSL "https://api.github.com/repos/${AWB_NPU_GH_REPO}/releases/latest" \
        | grep -o "\"browser_download_url\": *\"[^\"]*${asset_tag}[^\"]*\.tar\.gz\"" \
        | head -1 | sed -E 's/.*"(https[^"]+)"/\1/')" || true

    if [[ -z "$asset_url" ]]; then
        log_warn "Intel does not currently publish a prebuilt NPU driver release for ${OS_NAME:-this OS} (looked for a *${asset_tag}*.tar.gz asset in ${AWB_NPU_GH_REPO}). Continuing without NPU acceleration; see docs/PLATFORM_INTEL.md for manual install options."
        return 0
    fi

    apt_update_once
    sudo apt-get install -y libtbb12 \
        || { log_warn "Failed to install libtbb12 (NPU driver dependency); skipping NPU driver install."; return 0; }

    ensure_dir "$AWB_NPU_SRC"
    local tarball="${AWB_NPU_SRC}/driver.tar.gz"
    if ! curl -fsSL --retry 3 --retry-delay 5 -o "$tarball" "$asset_url"; then
        log_warn "Failed to download Intel NPU driver release; skipping (non-fatal)."
        return 0
    fi

    if ! tar -xzf "$tarball" -C "$AWB_NPU_SRC"; then
        log_warn "Failed to extract Intel NPU driver archive; skipping (non-fatal)."
        return 0
    fi

    # Only the real .deb packages — exclude *.ddeb (debug symbols) and
    # *.asc (detached signatures), which ship in the same tarball.
    local -a debs=()
    while IFS= read -r -d '' f; do debs+=("$f"); done \
        < <(find "$AWB_NPU_SRC" -maxdepth 1 -name '*.deb' -print0)

    if (( ${#debs[@]} == 0 )); then
        log_warn "NPU driver archive contained no .deb packages; skipping (non-fatal)."
        return 0
    fi

    sudo dpkg -i "${debs[@]}" \
        || log_warn "NPU driver dpkg install reported errors; NPU acceleration may be incomplete."

    log_ok "Intel NPU driver installed (best-effort)."
}
