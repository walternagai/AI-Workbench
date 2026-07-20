#!/usr/bin/env bash
# install.sh — AI-Workbench Core v1.0 main installer.
#
# Flow (per docs/ARCHITECTURE.md):
#   validate OS -> update system -> detect hardware -> run platform module
#   -> create Python envs -> install runtimes -> download default model
#   -> run benchmark -> generate final report
#
# Every step is idempotent: re-running install.sh after a partial failure
# does not corrupt what already succeeded (selective re-execution, see
# docs/PRINCIPLES.md and the INSTALL_* / RUN_* flags in config.env).
set -euo pipefail

AWB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWB_ROOT

# shellcheck source=lib/colors.sh
source "${AWB_ROOT}/lib/colors.sh"
# shellcheck source=lib/logger.sh
source "${AWB_ROOT}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${AWB_ROOT}/lib/utils.sh"
# shellcheck source=lib/downloader.sh
source "${AWB_ROOT}/lib/downloader.sh"
# shellcheck source=lib/validation.sh
source "${AWB_ROOT}/lib/validation.sh"

load_env "${AWB_ROOT}/config.env" true

# ---------------------------------------------------------------------------
# CLI flags (menu-style partial re-execution; see also `make install-*`)
# ---------------------------------------------------------------------------
RUN_VALIDATE=true
RUN_SYSTEM_UPDATE=true
RUN_DETECT=true
RUN_PLATFORM=true
RUN_PYTHON=true
RUN_RUNTIMES=true
RUN_MODELS=true
RUN_SERVICES=true
RUN_BENCHMARK=true
RUN_REPORT=true

_print_help() {
    cat <<EOF
Usage: install.sh [options]

  --only <section>     Run only one section: validate|system|detect|platform|
                        python|runtimes|models|services|benchmark|report
  --skip <section>      Skip one section (repeatable)
  -h, --help            Show this help
EOF
}

_disable_all_sections() {
    RUN_VALIDATE=false RUN_SYSTEM_UPDATE=false RUN_DETECT=false RUN_PLATFORM=false
    RUN_PYTHON=false RUN_RUNTIMES=false RUN_MODELS=false RUN_SERVICES=false
    RUN_BENCHMARK=false RUN_REPORT=false
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            _disable_all_sections
            case "$2" in
                validate)  RUN_VALIDATE=true ;;
                system)    RUN_SYSTEM_UPDATE=true ;;
                detect)    RUN_DETECT=true ;;
                platform)  RUN_DETECT=true; RUN_PLATFORM=true ;;
                python)    RUN_PYTHON=true ;;
                runtimes)  RUN_DETECT=true; RUN_RUNTIMES=true ;;
                models)    RUN_MODELS=true ;;
                services)  RUN_SERVICES=true ;;
                benchmark) RUN_DETECT=true; RUN_BENCHMARK=true ;;
                report)    RUN_DETECT=true; RUN_REPORT=true ;;
                *) fail_loud "Unknown section for --only: $2" ;;
            esac
            shift 2 ;;
        --skip)
            case "$2" in
                validate)  RUN_VALIDATE=false ;;
                system)    RUN_SYSTEM_UPDATE=false ;;
                detect)    RUN_DETECT=false ;;
                platform)  RUN_PLATFORM=false ;;
                python)    RUN_PYTHON=false ;;
                runtimes)  RUN_RUNTIMES=false ;;
                models)    RUN_MODELS=false ;;
                services)  RUN_SERVICES=false ;;
                benchmark) RUN_BENCHMARK=false ;;
                report)    RUN_REPORT=false ;;
                *) fail_loud "Unknown section for --skip: $2" ;;
            esac
            shift 2 ;;
        -h|--help) _print_help; exit 0 ;;
        *) fail_loud "Unknown argument: $1 (see --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------
section_validate() {
    log_step "Validating system"
    validate_not_root_unless_intended
    validate_os
    validate_arch
    validate_ram "${MIN_RAM_GB:-8}"
    validate_disk_space "${MIN_DISK_GB:-20}" "$HOME"
}

section_system_update() {
    log_step "Updating system packages"
    sudo_keepalive
    sudo apt-get update -y || fail_loud "apt-get update failed"
    sudo apt-get upgrade -y || fail_loud "apt-get upgrade failed"
    sudo apt-get install -y build-essential cmake ninja-build git curl wget pciutils lm-sensors python3 python3-venv python3-pip \
        || fail_loud "Failed to install base build/detection tooling"
}

section_detect() {
    log_step "Detecting hardware"
    # shellcheck disable=SC1091
    source "${AWB_ROOT}/detect.sh" 2>/dev/null || true
    run_all_detections
    resolve_platform_target
    print_summary
    write_hardware_report
}

# Shared prerequisites are created unconditionally, before ANY conditional
# platform/runtime branch below — this ordering fixed a real bug where a
# runtime assumed a directory only a platform branch had created.
section_prereqs() {
    log_step "Preparing shared prerequisites"
    ensure_prereq_dirs
}

section_platform() {
    log_step "Installing platform stack: ${PLATFORM_TARGET}"
    # CPU baseline is always installed, regardless of detected GPU, since
    # every runtime needs a working fallback path.
    source "${AWB_ROOT}/platforms/cpu/install.sh"
    install_cpu_platform

    case "$PLATFORM_TARGET" in
        intel)
            source "${AWB_ROOT}/platforms/intel/install.sh"
            install_intel_platform ;;
        amd)
            source "${AWB_ROOT}/platforms/amd/install.sh"
            install_amd_platform ;;
        nvidia)
            source "${AWB_ROOT}/platforms/nvidia/install.sh"
            install_nvidia_platform ;;
        cpu)
            log_info "No GPU detected; CPU-only stack is sufficient." ;;
        *)
            fail_loud "Unresolved platform target: $PLATFORM_TARGET" ;;
    esac
}

section_python() {
    log_step "Creating Python environments"
    source "${AWB_ROOT}/python/create_envs.sh"
    create_all_envs
}

section_runtimes() {
    log_step "Installing runtimes"
    is_true "${INSTALL_LLAMACPP:-true}" && { source "${AWB_ROOT}/runtimes/llama.cpp/install.sh"; install_llama_cpp; }
    is_true "${INSTALL_OLLAMA:-true}"   && { source "${AWB_ROOT}/runtimes/ollama/install.sh"; install_ollama; }
    is_true "${INSTALL_OPENVINO:-true}" && { source "${AWB_ROOT}/runtimes/openvino/install.sh"; install_openvino_runtime; }
    is_true "${INSTALL_ONNXRUNTIME:-true}" && { source "${AWB_ROOT}/runtimes/onnxruntime/install.sh"; install_onnxruntime; }
    is_true "${INSTALL_WHISPER:-true}"  && { source "${AWB_ROOT}/runtimes/whisper/install.sh"; install_whisper_cpp; }
}

section_models() {
    log_step "Downloading default model"
    source "${AWB_ROOT}/models/install.sh"
    model_install "${DEFAULT_MODEL:-gemma3-e2b}"
}

section_services() {
    log_step "Starting services"
    source "${AWB_ROOT}/services/install.sh"
    install_services
}

section_benchmark() {
    log_step "Running benchmark"
    local model_file="${AI_HOME:-$HOME/ai}/models/gguf/${AWB_DEFAULT_GGUF:-}"
    if [[ -f "$model_file" ]]; then
        source "${AWB_ROOT}/runtimes/llama.cpp/benchmark.sh"
        benchmark_llama_cpp "$model_file"
    else
        log_warn "Default model not found at $model_file; skipping benchmark."
    fi
}

section_report() {
    log_step "Generating final report"
    ensure_dir "${AWB_ROOT}/reports"
    {
        echo "# AI-Workbench Install Report"
        echo
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        echo "## Hardware"
        echo '```json'
        cat "${AWB_ROOT}/reports/hardware.json" 2>/dev/null || echo "(not available)"
        echo '```'
        echo
        echo "## Installed components"
        echo "- Platform: ${PLATFORM_TARGET:-unknown}"
        echo "- llama.cpp: $(is_true "${INSTALL_LLAMACPP:-true}" && echo yes || echo no)"
        echo "- Ollama: $(is_true "${INSTALL_OLLAMA:-true}" && echo yes || echo no)"
        echo "- OpenVINO: $(is_true "${INSTALL_OPENVINO:-true}" && echo yes || echo no)"
        echo "- ONNX Runtime: $(is_true "${INSTALL_ONNXRUNTIME:-true}" && echo yes || echo no)"
        echo "- Whisper: $(is_true "${INSTALL_WHISPER:-true}" && echo yes || echo no)"
        echo "- Default model: ${DEFAULT_MODEL:-none}"
        echo
        echo "Full logs: logs/installation.log"
        echo "Run 'awb doctor' any time to re-verify the environment."
    } > "${AWB_ROOT}/reports/install_report.md"
    log_ok "Report written to reports/install_report.md"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_step "AI-Workbench Core v1.0 — Installer"

    is_true "$RUN_VALIDATE" && section_validate
    is_true "$RUN_SYSTEM_UPDATE" && section_system_update
    section_prereqs   # always runs, unconditionally, before any branch below
    is_true "$RUN_DETECT" && section_detect
    is_true "$RUN_PLATFORM" && section_platform
    is_true "$RUN_PYTHON" && section_python
    is_true "$RUN_RUNTIMES" && section_runtimes
    is_true "$RUN_MODELS" && section_models
    is_true "$RUN_SERVICES" && section_services
    is_true "$RUN_BENCHMARK" && section_benchmark
    is_true "$RUN_REPORT" && section_report

    log_ok "AI-Workbench installation complete."
    log_info "Run 'awb doctor' to verify everything, or 'awb info' for a quick summary."
}

main
