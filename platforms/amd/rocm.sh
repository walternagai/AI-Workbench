#!/usr/bin/env bash
# platforms/amd/rocm.sh — ROCm stack (driver + runtime) for AMD GPUs.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

install_amd_rocm() {
    log_step "Installing ROCm"

    if has_cmd rocminfo && rocminfo >/dev/null 2>&1; then
        log_ok "ROCm already functional, skipping."
        return 0
    fi

    require_cmd wget "downloading the ROCm installer"
    local os_codename
    os_codename=$(awk -F= '/^VERSION_CODENAME=/ {gsub(/"/,"",$2); print $2; exit}' /etc/os-release 2>/dev/null) || os_codename="jammy"

    log_info "Adding ROCm apt repository for ${os_codename}..."
    wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/rocm.gpg \
        || fail_loud "Failed to fetch ROCm GPG key"
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/latest ${os_codename} main" \
        | sudo tee /etc/apt/sources.list.d/rocm.list >/dev/null

    sudo apt-get update -y || fail_loud "apt-get update failed after adding ROCm repo"
    sudo apt-get install -y rocm-hip-runtime rocm-smi rocminfo \
        || fail_loud "Failed to install ROCm packages"

    local user="${SUDO_USER:-$USER}"
    for grp in render video; do
        id -nG "$user" | grep -qw "$grp" || sudo usermod -aG "$grp" "$user"
    done

    log_ok "ROCm installed. A re-login may be required for group membership to apply."
}
