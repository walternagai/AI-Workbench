#!/usr/bin/env bash
# detect.sh — hardware & capability detection for AI-Workbench.
#
# Responsibilities (per spec): distro, arch, CPU, GPU, NPU, Vulkan, OpenCL,
# CUDA, ROCm, RAM, storage.
#
# Can be sourced (exports variables for install.sh/doctor.sh) or run
# directly (prints a human-readable summary + writes reports/hardware.json).
set -euo pipefail

AWB_ROOT="${AWB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib/colors.sh
source "${AWB_ROOT}/lib/colors.sh"
# shellcheck source=lib/logger.sh
source "${AWB_ROOT}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${AWB_ROOT}/lib/utils.sh"

# ---------------------------------------------------------------------------
# Distro / architecture
# ---------------------------------------------------------------------------
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # Parse /etc/os-release with awk instead of sourcing it.
        # This avoids executing arbitrary code from the file and
        # prevents environment pollution from ~30 exported variables.
        OS_ID=$(awk -F= '/^ID=/    {gsub(/"/,"",$2); print $2; exit}' /etc/os-release) || OS_ID="unknown"
        OS_NAME=$(awk -F= '/^PRETTY_NAME=/ {gsub(/"/,"",$2); print $2; exit}' /etc/os-release) || OS_NAME="unknown"
        OS_VERSION=$(awk -F= '/^VERSION_ID=/ {gsub(/"/,"",$2); print $2; exit}' /etc/os-release) || OS_VERSION="unknown"
        export OS_ID OS_NAME OS_VERSION
    else
        export OS_ID="unknown" OS_NAME="unknown" OS_VERSION="unknown"
    fi
    export CPU_ARCH
    CPU_ARCH="$(uname -m)"
}

# ---------------------------------------------------------------------------
# CPU
# ---------------------------------------------------------------------------
detect_cpu() {
    local model vendor
    model=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
    vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
    export CPU_MODEL="${model:-unknown}"
    case "$vendor" in
        GenuineIntel) export CPU_VENDOR="Intel" ;;
        AuthenticAMD) export CPU_VENDOR="AMD" ;;
        *) export CPU_VENDOR="${vendor:-unknown}" ;;
    esac
    export CPU_CORES
    CPU_CORES=$(nproc)
}

# ---------------------------------------------------------------------------
# GPU (PCI enumeration — works headlessly, no driver required to detect)
# ---------------------------------------------------------------------------
detect_gpu() {
    export GPU_VENDOR="none"
    export GPU_MODEL="none"
    export HAS_INTEL_ARC="false"
    export HAS_NVIDIA_GPU="false"
    export HAS_AMD_GPU="false"

    if ! has_cmd lspci; then
        log_warn "lspci not found; GPU detection will be limited. (apt install pciutils)"
        return 0
    fi

    local vga_line
    vga_line=$(lspci -mm | grep -Ei 'VGA compatible controller|3D controller|Display controller' | head -1 || true)

    if echo "$vga_line" | grep -qi 'nvidia'; then
        export GPU_VENDOR="NVIDIA"
        export HAS_NVIDIA_GPU="true"
        GPU_MODEL=$(echo "$vga_line" | sed -n 's/.*"\(.*\)"\s*$/\1/p')
    elif echo "$vga_line" | grep -qi 'amd\|ati'; then
        export GPU_VENDOR="AMD"
        export HAS_AMD_GPU="true"
        GPU_MODEL=$(echo "$vga_line" | sed -n 's/.*"\(.*\)"\s*$/\1/p')
    elif echo "$vga_line" | grep -qi 'intel'; then
        export GPU_VENDOR="Intel"
        GPU_MODEL=$(echo "$vga_line" | sed -n 's/.*"\(.*\)"\s*$/\1/p')
        if echo "$GPU_MODEL" | grep -qi 'arc\|meteor lake\|lunar lake\|battlemage\|arrow lake\|iris xe'; then
            export HAS_INTEL_ARC="true"
        fi
    fi
    export GPU_MODEL="${GPU_MODEL:-unknown}"

    # Discrete NVIDIA/AMD GPUs may coexist with an Intel iGPU. Record all
    # controllers so doctor.sh / reports can show the full picture.
    export GPU_ALL_CONTROLLERS
    GPU_ALL_CONTROLLERS=$(lspci -mm | grep -Ei 'VGA compatible controller|3D controller' | sed -n 's/.*"\(.*\)"\s*$/\1/p' | paste -sd '; ' -) || true
}

# ---------------------------------------------------------------------------
# NPU (Intel Meteor Lake / Lunar Lake onward expose an accel device)
# ---------------------------------------------------------------------------
detect_npu() {
    export HAS_INTEL_NPU="false"
    if [[ -e /dev/accel/accel0 ]] || compgen -G "/sys/class/accel/*" >/dev/null 2>&1; then
        export HAS_INTEL_NPU="true"
    fi
}

# ---------------------------------------------------------------------------
# Acceleration APIs
# ---------------------------------------------------------------------------
detect_vulkan() {
    export HAS_VULKAN="false"
    export VULKAN_DEVICE=""
    if has_cmd vulkaninfo; then
        local tmpfile
        tmpfile="$(mktemp /tmp/awb_vulkaninfo.XXXXXX 2>/dev/null)" || tmpfile=""
        if [[ -n "$tmpfile" ]]; then
            if vulkaninfo --summary >"$tmpfile" 2>/dev/null; then
                export HAS_VULKAN="true"
                VULKAN_DEVICE=$(grep -m1 'deviceName' "$tmpfile" | cut -d= -f2 | sed 's/^ //')
            fi
            rm -f "$tmpfile"
        fi
    fi
}

detect_opencl() {
    export HAS_OPENCL="false"
    if has_cmd clinfo; then
        if clinfo -l 2>/dev/null | grep -q .; then
            export HAS_OPENCL="true"
        fi
    fi
}

detect_cuda() {
    export HAS_CUDA="false"
    export CUDA_VERSION=""
    if has_cmd nvidia-smi; then
        if nvidia-smi >/dev/null 2>&1; then
            export HAS_CUDA="true"
            CUDA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
        fi
    fi
}

detect_rocm() {
    export HAS_ROCM="false"
    if has_cmd rocminfo; then
        if rocminfo >/dev/null 2>&1; then
            export HAS_ROCM="true"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Memory / storage
# ---------------------------------------------------------------------------
detect_memory() {
    export RAM_GB
    local mem_total
    mem_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}') || true
    if [[ -n "$mem_total" ]]; then
        RAM_GB=$(( mem_total / 1024 / 1024 ))
    else
        RAM_GB=0
        log_warn "Could not determine RAM size (/proc/meminfo not available)."
    fi

    export VRAM_GB="0"
    if [[ "${HAS_CUDA:-false}" == "true" ]]; then
        VRAM_GB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
            | awk '{sum+=$1} END {printf "%d", sum/1024}')
    fi
}

detect_storage() {
    export DISK_AVAIL_GB
    DISK_AVAIL_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9') || DISK_AVAIL_GB=""
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------
run_all_detections() {
    detect_os
    detect_cpu
    detect_gpu
    detect_npu
    detect_vulkan
    detect_opencl
    detect_cuda
    detect_rocm
    detect_memory
    detect_storage
}

# select PLATFORM_TARGET based on detected hardware priority:
# discrete NVIDIA > discrete AMD > Intel (iGPU/Arc/NPU) > CPU-only fallback.
resolve_platform_target() {
    if [[ "${HAS_NVIDIA_GPU}" == "true" ]]; then
        export PLATFORM_TARGET="nvidia"
    elif [[ "${HAS_AMD_GPU}" == "true" ]]; then
        export PLATFORM_TARGET="amd"
    elif [[ "${GPU_VENDOR}" == "Intel" ]]; then
        export PLATFORM_TARGET="intel"
    else
        export PLATFORM_TARGET="cpu"
    fi
}

write_hardware_report() {
    ensure_dir "${AWB_ROOT}/reports"
    cat > "${AWB_ROOT}/reports/hardware.json" <<EOF
{
$(json_kv os_id "$OS_ID"),
$(json_kv os_name "$OS_NAME"),
$(json_kv arch "$CPU_ARCH"),
$(json_kv cpu_vendor "$CPU_VENDOR"),
$(json_kv cpu_model "$CPU_MODEL"),
$(json_kv cpu_cores "$CPU_CORES"),
$(json_kv gpu_vendor "$GPU_VENDOR"),
$(json_kv gpu_model "$GPU_MODEL"),
$(json_kv gpu_all_controllers "${GPU_ALL_CONTROLLERS:-}"),
$(json_kv has_intel_arc "$HAS_INTEL_ARC"),
$(json_kv has_intel_npu "$HAS_INTEL_NPU"),
$(json_kv has_nvidia_gpu "$HAS_NVIDIA_GPU"),
$(json_kv has_amd_gpu "$HAS_AMD_GPU"),
$(json_kv has_vulkan "$HAS_VULKAN"),
$(json_kv vulkan_device "${VULKAN_DEVICE:-}"),
$(json_kv has_opencl "$HAS_OPENCL"),
$(json_kv has_cuda "$HAS_CUDA"),
$(json_kv cuda_version "${CUDA_VERSION:-}"),
$(json_kv has_rocm "$HAS_ROCM"),
$(json_kv ram_gb "$RAM_GB"),
$(json_kv vram_gb "$VRAM_GB"),
$(json_kv disk_avail_gb "${DISK_AVAIL_GB:-unknown}"),
$(json_kv platform_target "${PLATFORM_TARGET:-unresolved}")
}
EOF
    log_ok "Hardware report written to reports/hardware.json"
}

print_summary() {
    echo -e "\n${C_BOLD}AI-Workbench — Hardware Detection${C_RESET}"
    echo -e "  OS:            ${OS_NAME}"
    echo -e "  Architecture:  ${CPU_ARCH}"
    echo -e "  CPU:           ${CPU_VENDOR} — ${CPU_MODEL} (${CPU_CORES} cores)"
    echo -e "  GPU:           ${GPU_VENDOR} — ${GPU_MODEL}"
    [[ -n "${GPU_ALL_CONTROLLERS:-}" ]] && echo -e "  All GPUs:      ${GPU_ALL_CONTROLLERS}"
    echo -e "  Intel Arc:     ${HAS_INTEL_ARC}"
    echo -e "  Intel NPU:     ${HAS_INTEL_NPU}"
    echo -e "  Vulkan:        ${HAS_VULKAN} ${VULKAN_DEVICE:+(${VULKAN_DEVICE})}"
    echo -e "  OpenCL:        ${HAS_OPENCL}"
    echo -e "  CUDA:          ${HAS_CUDA} ${CUDA_VERSION:+(driver ${CUDA_VERSION})}"
    echo -e "  ROCm:          ${HAS_ROCM}"
    echo -e "  RAM:           ${RAM_GB} GB"
    echo -e "  VRAM:          ${VRAM_GB} GB"
    echo -e "  Disk free:     ${DISK_AVAIL_GB:-unknown} GB"
    echo -e "  Platform:      ${C_BOLD}${PLATFORM_TARGET}${C_RESET}\n"
}

# Only run standalone logic if executed directly, not when sourced by
# install.sh/doctor.sh (which just want the exported variables).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_detections
    resolve_platform_target
    print_summary
    write_hardware_report
fi
