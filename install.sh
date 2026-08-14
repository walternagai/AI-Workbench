#!/usr/bin/env bash
# install.sh — AI-Workbench Core v1.0 main installer.
#
# Flow (per CLAUDE.md's Architecture section):
#   validate OS -> update system -> detect hardware -> install the awb CLI
#   -> create Python envs -> run platform module -> install runtimes
#   -> download default + whisper models -> docker services -> benchmark
#   -> generate final report
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

# Optional local overrides, gitignored. Secrets belong here rather than in the
# tracked config.env, which is public. Loaded second so its values win.
load_env "${AWB_ROOT}/config.local.env" false

# ---------------------------------------------------------------------------
# CLI flags (menu-style partial re-execution; see also `make install-*`)
# ---------------------------------------------------------------------------
RUN_VALIDATE=true
RUN_SYSTEM_UPDATE=true
RUN_DETECT=true
RUN_CLI=true
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

  --only <section>     Run only one section: validate|system|detect|cli|
                        platform|python|runtimes|models|services|benchmark|
                        report
  --skip <section>      Skip one section (repeatable)
  -h, --help            Show this help
EOF
}

_disable_all_sections() {
    RUN_VALIDATE=false RUN_SYSTEM_UPDATE=false RUN_DETECT=false RUN_CLI=false RUN_PLATFORM=false
    RUN_PYTHON=false RUN_RUNTIMES=false RUN_MODELS=false RUN_SERVICES=false
    RUN_BENCHMARK=false RUN_REPORT=false
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            [[ $# -ge 2 ]] || fail_loud "--only requires a section name (see --help)"
            _disable_all_sections
            case "$2" in
                validate)  RUN_VALIDATE=true ;;
                system)    RUN_SYSTEM_UPDATE=true ;;
                detect)    RUN_DETECT=true ;;
                cli)       RUN_CLI=true ;;
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
            [[ $# -ge 2 ]] || fail_loud "--skip requires a section name (see --help)"
            case "$2" in
                validate)  RUN_VALIDATE=false ;;
                system)    RUN_SYSTEM_UPDATE=false ;;
                detect)    RUN_DETECT=false ;;
                cli)       RUN_CLI=false ;;
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
    apt_update_once
    sudo apt-get install -y \
        build-essential cmake ninja-build git curl wget pciutils \
        lm-sensors python3 python3-venv python3-pip \
        vulkan-tools clinfo \
        docker-compose-plugin \
        || fail_loud "Failed to install base build/detection tooling"
}

section_detect() {
    log_step "Detecting hardware"
    safe_source "${AWB_ROOT}/detect.sh"
    declare -F run_all_detections &>/dev/null || fail_loud "detect.sh loaded but run_all_detections() not found"
    declare -F resolve_platform_target &>/dev/null || fail_loud "detect.sh loaded but resolve_platform_target() not found"
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

# Puts `awb` on PATH. Runs early so the CLI exists even if a later section
# fails — a partial install is exactly when you want the diagnostics command.
section_cli() {
    log_step "Installing the awb CLI"
    if ! is_true "${INSTALL_AWB_CLI:-true}"; then
        log_info "Skipping awb CLI symlink (INSTALL_AWB_CLI not enabled in config.env). Run it as ${AWB_ROOT}/scripts/awb."
        return 0
    fi

    local target_dir="${AWB_CLI_DIR:-$HOME/.local/bin}"
    local link="${target_dir}/awb"
    local src="${AWB_ROOT}/scripts/awb"

    [[ -f "$src" ]] || fail_loud "Cannot install the CLI: ${src} not found."
    ensure_dir "$target_dir"

    # Never clobber something that isn't ours: a real binary named 'awb' from
    # another project is the user's, not ours to overwrite. Re-pointing our own
    # symlink is fine and keeps the section idempotent across repo moves.
    if [[ -e "$link" && ! -L "$link" ]]; then
        fail_loud "Refusing to overwrite ${link}: it exists and is not a symlink. Remove it, or set AWB_CLI_DIR to another directory in config.env."
    fi

    ln -sfn "$src" "$link" || fail_loud "Failed to symlink ${link} -> ${src}"

    case ":${PATH}:" in
        *":${target_dir}:"*)
            log_ok "awb installed: ${link} (on PATH)" ;;
        *)
            log_warn "awb installed at ${link}, but ${target_dir} is not on your PATH. Add it to your shell profile: export PATH=\"${target_dir}:\$PATH\"" ;;
    esac
}

section_platform() {
    log_step "Installing platform stack: ${PLATFORM_TARGET}"
    # CPU baseline is always installed, regardless of detected GPU, since
    # every runtime needs a working fallback path.
    safe_source "${AWB_ROOT}/platforms/cpu/install.sh"
    install_cpu_platform

    case "$PLATFORM_TARGET" in
        intel)
            safe_source "${AWB_ROOT}/platforms/intel/install.sh"
            install_intel_platform ;;
        amd)
            safe_source "${AWB_ROOT}/platforms/amd/install.sh"
            install_amd_platform ;;
        nvidia)
            safe_source "${AWB_ROOT}/platforms/nvidia/install.sh"
            install_nvidia_platform ;;
        cpu)
            log_info "No GPU detected; CPU-only stack is sufficient." ;;
        *)
            fail_loud "Unresolved platform target: $PLATFORM_TARGET" ;;
    esac
}

section_python() {
    log_step "Creating Python environments"
    safe_source "${AWB_ROOT}/python/create_envs.sh"
    create_all_envs
}

section_runtimes() {
    log_step "Installing runtimes"
    is_true "${INSTALL_LLAMACPP:-true}" && { safe_source "${AWB_ROOT}/runtimes/llama.cpp/install.sh"; install_llama_cpp; }
    is_true "${INSTALL_OLLAMA:-true}"   && { safe_source "${AWB_ROOT}/runtimes/ollama/install.sh"; install_ollama; }
    is_true "${INSTALL_OPENVINO:-true}" && { safe_source "${AWB_ROOT}/runtimes/openvino/install.sh"; install_openvino_runtime; }
    is_true "${INSTALL_ONNXRUNTIME:-true}" && { safe_source "${AWB_ROOT}/runtimes/onnxruntime/install.sh"; install_onnxruntime; }
    is_true "${INSTALL_WHISPER:-true}"  && { safe_source "${AWB_ROOT}/runtimes/whisper/install.sh"; install_whisper_cpp; }
}

section_models() {
    log_step "Downloading default model"
    safe_source "${AWB_ROOT}/models/install.sh"
    model_install "${DEFAULT_MODEL:-gemma3-e2b}"

    # whisper.cpp's binary is inert without a GGML model, and section_runtimes
    # only builds the binary — so before this, every clean install finished with
    # a working whisper-cli and nothing for it to transcribe, which doctor then
    # reported as a failure on a brand new machine.
    if is_true "${INSTALL_WHISPER:-true}" && [[ -n "${DEFAULT_WHISPER_MODEL:-}" ]]; then
        model_install "$DEFAULT_WHISPER_MODEL"
    fi
}

section_services() {
    log_step "Starting services"
    safe_source "${AWB_ROOT}/services/install.sh"
    install_services
}

section_benchmark() {
    log_step "Running benchmark"
    local model_file="${AI_HOME:-$HOME/ai}/models/gguf/${AWB_DEFAULT_GGUF:-}"
    if [[ -f "$model_file" ]]; then
        safe_source "${AWB_ROOT}/runtimes/llama.cpp/benchmark.sh"
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
# Called on EXIT / INT / TERM to ensure no background processes (e.g.
# sudo_keepalive) are left behind after an interruption or crash.
_cleanup() {
    if [[ -n "${AWB_SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$AWB_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

main() {
    trap _cleanup EXIT INT TERM
    log_step "AI-Workbench Core v1.0 — Installer"

    is_true "$RUN_VALIDATE" && section_validate
    is_true "$RUN_SYSTEM_UPDATE" && section_system_update
    section_prereqs   # always runs, unconditionally, before any branch below
    is_true "$RUN_DETECT" && section_detect
    is_true "$RUN_CLI" && section_cli
    # Python envs precede the platform stack: platforms/intel/openvino.sh pip
    # installs into the 'openvino' venv that create_envs.sh builds, and
    # runtimes/openvino layers on top of that. create_envs.sh itself needs only
    # python3/python3-venv (checked in validate), never the platform stack.
    is_true "$RUN_PYTHON" && section_python
    is_true "$RUN_PLATFORM" && section_platform
    is_true "$RUN_RUNTIMES" && section_runtimes
    is_true "$RUN_MODELS" && section_models
    is_true "$RUN_SERVICES" && section_services
    is_true "$RUN_BENCHMARK" && section_benchmark
    is_true "$RUN_REPORT" && section_report

    log_ok "AI-Workbench installation complete."
    log_info "Run 'awb doctor' to verify everything, or 'awb info' for a quick summary."
}

main
