#!/usr/bin/env bash
# monitoring/gpu.sh — GPU utilization/VRAM/temperature, dispatched by vendor.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

monitor_gpu() {
    echo -e "${C_BOLD}GPU (${GPU_VENDOR:-unknown})${C_RESET}"
    case "${GPU_VENDOR:-}" in
        NVIDIA)
            if has_cmd nvidia-smi; then
                # A driver that is not loaded makes nvidia-smi fail. Under
                # pipefail and set -e that aborted `awb monitor` silently (M5).
                nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
                    --format=csv,noheader | sed 's/^/  /' \
                    || echo "  nvidia-smi não respondeu (driver carregado?)"
            fi
            ;;
        AMD)
            if has_cmd rocm-smi; then
                rocm-smi --showuse --showmemuse --showtemp | sed 's/^/  /' \
                    || echo "  rocm-smi não respondeu (driver carregado?)"
            fi
            ;;
        Intel)
            if has_cmd intel_gpu_top; then
                echo "  (run 'sudo intel_gpu_top' interactively for live engine utilization)"
            fi
            ;;
        *)
            echo "  No GPU monitoring available for this vendor."
            ;;
    esac
}
