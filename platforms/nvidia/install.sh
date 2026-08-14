#!/usr/bin/env bash
# platforms/nvidia/install.sh — orchestrates the NVIDIA platform stack.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

# shellcheck source=platforms/nvidia/cuda.sh
source "${AWB_ROOT}/platforms/nvidia/cuda.sh"
# shellcheck source=platforms/nvidia/repo.sh
source "${AWB_ROOT}/platforms/nvidia/repo.sh"
# shellcheck source=platforms/nvidia/cudnn.sh
source "${AWB_ROOT}/platforms/nvidia/cudnn.sh"
# shellcheck source=platforms/nvidia/tensorrt.sh
source "${AWB_ROOT}/platforms/nvidia/tensorrt.sh"
# shellcheck source=platforms/nvidia/vulkan.sh
source "${AWB_ROOT}/platforms/nvidia/vulkan.sh"
# shellcheck source=platforms/nvidia/opencl.sh
source "${AWB_ROOT}/platforms/nvidia/opencl.sh"

install_nvidia_platform() {
    log_step "NVIDIA platform: ${GPU_MODEL:-unknown}"

    install_nvidia_cuda
    install_nvidia_cudnn
    install_nvidia_tensorrt
    install_nvidia_vulkan
    install_nvidia_opencl

    if is_true "${INSTALL_DOCKER:-true}"; then
        install_nvidia_container_toolkit
    fi

    log_ok "NVIDIA platform stack installed."
}

# NVIDIA Container Toolkit — required for GPU passthrough into Docker
# (used by services/openwebui and the fine-tuning containers).
install_nvidia_container_toolkit() {
    log_step "Installing NVIDIA Container Toolkit"

    if has_cmd nvidia-ctk; then
        log_ok "NVIDIA Container Toolkit already installed."
        return 0
    fi

    require_cmd curl "adding the NVIDIA Container Toolkit apt repo"
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit.gpg \
        || fail_loud "Failed to fetch NVIDIA Container Toolkit GPG key"

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit.gpg] https://#' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

    sudo apt-get update -y || fail_loud "apt-get update failed after adding NVIDIA Container Toolkit repo"
    sudo apt-get install -y nvidia-container-toolkit || fail_loud "Failed to install nvidia-container-toolkit"
    sudo nvidia-ctk runtime configure --runtime=docker || fail_loud "Failed to configure Docker runtime for NVIDIA"
    sudo systemctl restart docker || log_warn "Could not restart docker; restart it manually before running GPU containers."

    log_ok "NVIDIA Container Toolkit installed and Docker configured."
}
