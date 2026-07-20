#!/usr/bin/env bash
# platforms/intel/install.sh — orchestrates the full Intel platform stack.
# Compatible with: Arc, Iris Xe, Meteor Lake, Lunar Lake, Battlemage, Arrow Lake.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

# shellcheck source=platforms/intel/gpu.sh
source "${AWB_ROOT}/platforms/intel/gpu.sh"
# shellcheck source=platforms/intel/vulkan.sh
source "${AWB_ROOT}/platforms/intel/vulkan.sh"
# shellcheck source=platforms/intel/opencl.sh
source "${AWB_ROOT}/platforms/intel/opencl.sh"
# shellcheck source=platforms/intel/npu.sh
source "${AWB_ROOT}/platforms/intel/npu.sh"
# shellcheck source=platforms/intel/openvino.sh
source "${AWB_ROOT}/platforms/intel/openvino.sh"
# shellcheck source=platforms/intel/oneapi.sh
source "${AWB_ROOT}/platforms/intel/oneapi.sh"

install_intel_platform() {
    log_step "Intel platform: ${GPU_MODEL:-unknown}"

    install_intel_gpu_tools
    install_intel_vulkan          # primary acceleration path for llama.cpp
    install_intel_opencl          # secondary API, used by OpenVINO/some runtimes
    install_intel_npu             # best-effort, only if NPU present
    is_true "${INSTALL_OPENVINO:-true}" && install_intel_openvino
    install_intel_oneapi_runtime  # best-effort, redistributables only

    log_ok "Intel platform stack installed."
    log_info "IPEX-LLM (XPU/SYCL) is deliberately NOT installed by default: it is impractical on iGPUs given setup complexity and limited community testing. Vulkan (llama.cpp) is the supported path."
}
