#!/usr/bin/env bash
# platforms/nvidia/repo.sh — adds NVIDIA's official CUDA apt repository.
#
# Ubuntu's own repos carry nvidia-cuda-toolkit (what cuda.sh installs) but
# never cuDNN or TensorRT packages — those are only distributed through
# NVIDIA's own network repo. cuda.sh doesn't need this repo for itself;
# cudnn.sh and tensorrt.sh do. Best-effort, non-fatal: both callers already
# fall back to a log_warn if the package install itself fails, and this
# helper follows the same philosophy if the repo can't be added at all.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

# _ensure_nvidia_cuda_apt_repo — idempotent; installs NVIDIA's cuda-keyring
# package (GPG key + apt source entry in one .deb) if not already present.
# Returns 1 (never fail_loud) on any failure so callers can degrade gracefully.
_ensure_nvidia_cuda_apt_repo() {
    if dpkg -s cuda-keyring &>/dev/null; then
        return 0
    fi

    require_cmd curl "adding the NVIDIA CUDA apt repository"

    local os_tag="ubuntu${OS_VERSION//./}"
    local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${os_tag}/x86_64/cuda-keyring_1.1-1_all.deb"
    local keyring_deb
    keyring_deb="$(mktemp /tmp/cuda-keyring.XXXXXX.deb)"

    log_info "Adding NVIDIA CUDA apt repository for ${os_tag}..."
    if ! curl -fsSL --retry 3 --retry-delay 5 -o "$keyring_deb" "$keyring_url"; then
        rm -f "$keyring_deb"
        log_warn "Could not download the NVIDIA CUDA apt repository keyring for ${OS_NAME:-this OS} (${keyring_url}). cuDNN/TensorRT will be unavailable via apt; continuing (non-fatal)."
        return 1
    fi

    if ! sudo dpkg -i "$keyring_deb"; then
        rm -f "$keyring_deb"
        log_warn "Failed to install the NVIDIA CUDA apt repository keyring; continuing without it (non-fatal)."
        return 1
    fi
    rm -f "$keyring_deb"

    if ! sudo apt-get update -y; then
        log_warn "apt-get update failed after adding the NVIDIA CUDA apt repo; continuing (non-fatal)."
        return 1
    fi

    log_ok "NVIDIA CUDA apt repository configured."
}
