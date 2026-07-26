#!/usr/bin/env bash
# doctor.sh — AI-Workbench diagnostics.
#
# Runs a broad battery of checks (OS, kernel, tooling, acceleration APIs,
# runtimes, services) and reports pass/fail per item, then writes
# reports/doctor.json and reports/doctor.md. Never aborts on an individual
# failure — doctor's job is to report status, not to fail loud itself.
set -uo pipefail  # deliberately not -e: a failed check must not kill doctor.sh

AWB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWB_ROOT

# shellcheck source=lib/colors.sh
source "${AWB_ROOT}/lib/colors.sh"
# shellcheck source=lib/logger.sh
source "${AWB_ROOT}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${AWB_ROOT}/lib/utils.sh"
# shellcheck source=lib/downloader.sh
source "${AWB_ROOT}/lib/downloader.sh"   # for _awb_hf_cli (Models category)

load_env "${AWB_ROOT}/config.env" false

safe_source "${AWB_ROOT}/detect.sh"
declare -F run_all_detections &>/dev/null || fail_loud "detect.sh loaded but run_all_detections() not found"
declare -F resolve_platform_target &>/dev/null || fail_loud "detect.sh loaded but resolve_platform_target() not found"
run_all_detections >/dev/null 2>&1
resolve_platform_target >/dev/null 2>&1

declare -a AWB_CHECK_NAMES=()
declare -a AWB_CHECK_STATUS=()   # "pass" | "warn" | "fail" | "skip"
declare -a AWB_CHECK_DETAIL=()

# "warn" exists because some conditions are degraded-but-usable rather than
# broken, and lib/validation.sh already draws that line at install time:
# validate_disk_space aborts below MIN_DISK_GB, validate_ram only warns below
# MIN_RAM_GB and sets AWB_LOW_MEMORY. Collapsing that into pass/fail would make
# doctor either lie about a low-RAM box or report a failure install tolerates.
# Unlike "skip" (deliberately not applicable), "warn" means look at this.
check() {
    local name="$1" status="$2" detail="${3:-}"
    AWB_CHECK_NAMES+=("$name")
    AWB_CHECK_STATUS+=("$status")
    AWB_CHECK_DETAIL+=("$detail")
    case "$status" in
        pass) echo -e "  ${CHECK_MARK} ${name}" ;;
        warn) echo -e "  ${WARN_MARK} ${name}${detail:+ — ${detail}}" ;;
        fail) echo -e "  ${CROSS_MARK} ${name}${detail:+ — ${detail}}" ;;
        skip) echo -e "  ${SKIP_MARK} ${name} (skipped)${detail:+ — ${detail}}" ;;
        *)    echo -e "  ${CROSS_MARK} ${name} — internal error: unknown check status '${status}'" ;;
    esac
}

check_cmd() {
    local label="$1" cmd="$2"
    if has_cmd "$cmd"; then check "$label" pass; else check "$label" fail "'$cmd' not found"; fi
}

check_file() {
    local label="$1" path="$2"
    if [[ -e "$path" ]]; then check "$label" pass; else check "$label" fail "$path missing"; fi
}

check_true() {
    local label="$1" cond="$2" detail="${3:-}"
    if [[ "$cond" == "true" ]]; then check "$label" pass; else check "$label" fail "$detail"; fi
}

# ---------------------------------------------------------------------------
# Category: System
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}System${C_RESET}"
check "Operating System" pass "${OS_NAME:-unknown}"
check "Kernel" pass "$(uname -r)"
check_cmd "Git" git
check_cmd "Make" make
check_cmd "CMake" cmake
check_cmd "Ninja" ninja
check_cmd "curl" curl
check_cmd "wget" wget
check_cmd "Docker" docker
if has_cmd docker && docker compose version >/dev/null 2>&1; then
    check "Docker Compose plugin" pass
else
    check "Docker Compose plugin" fail "run: sudo apt-get install docker-compose-plugin"
fi
check_cmd "Python 3" python3
python3 -m venv --help >/dev/null 2>&1 && check "python3-venv module" pass || check "python3-venv module" fail "sudo apt-get install python3-venv"
check_cmd "pip" pip3

# ---------------------------------------------------------------------------
# Category: Acceleration APIs
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Acceleration${C_RESET}"
check_true "Vulkan" "${HAS_VULKAN:-false}" "no functional Vulkan device detected"
check_true "OpenCL" "${HAS_OPENCL:-false}" "no OpenCL platform detected"
if [[ "${PLATFORM_TARGET:-}" == "nvidia" ]]; then
    check_true "CUDA" "${HAS_CUDA:-false}" "nvidia-smi not functional"
else
    check "CUDA" skip "not applicable on ${PLATFORM_TARGET:-this} platform"
fi
if [[ "${PLATFORM_TARGET:-}" == "amd" ]]; then
    check_true "ROCm" "${HAS_ROCM:-false}" "rocminfo not functional"
else
    check "ROCm" skip "not applicable on ${PLATFORM_TARGET:-this} platform"
fi
if [[ "${PLATFORM_TARGET:-}" == "intel" ]]; then
    check_true "Intel Arc / iGPU detected" "$( [[ "${GPU_VENDOR:-}" == "Intel" ]] && echo true || echo false )"
    if [[ "${HAS_INTEL_NPU:-false}" == "true" ]]; then
        check_true "Intel NPU" "${HAS_INTEL_NPU}"
    else
        check "Intel NPU" skip "no NPU present on this CPU"
    fi
else
    check "Intel Arc" skip "not applicable on ${PLATFORM_TARGET:-this} platform"
fi

# ---------------------------------------------------------------------------
# Category: Vendor GPU tooling
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}GPU Vendors${C_RESET}"
[[ "${HAS_NVIDIA_GPU:-false}" == "true" ]] && check_cmd "nvidia-smi" nvidia-smi || check "NVIDIA" skip "no NVIDIA GPU detected"
[[ "${HAS_AMD_GPU:-false}" == "true" ]] && check_cmd "rocm-smi" rocm-smi || check "AMD" skip "no AMD GPU detected"
[[ "${GPU_VENDOR:-}" == "Intel" ]] && check_cmd "intel_gpu_top" intel_gpu_top || check "Intel GPU tools" skip "no Intel GPU detected"

# ---------------------------------------------------------------------------
# Category: Runtimes
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Runtimes${C_RESET}"
if is_true "${INSTALL_LLAMACPP:-true}"; then
    check_file "llama-server binary" "${AI_HOME:-$HOME/ai}/bin/llama-server"
    check_file "llama-cli binary" "${AI_HOME:-$HOME/ai}/bin/llama-cli"
else
    check "llama-server binary" skip "INSTALL_LLAMACPP disabled in config.env"
    check "llama-cli binary" skip "INSTALL_LLAMACPP disabled in config.env"
fi
if is_true "${INSTALL_OLLAMA:-true}"; then
    check_cmd "Ollama" ollama
else
    check "Ollama" skip "INSTALL_OLLAMA disabled in config.env"
fi
if is_true "${INSTALL_WHISPER:-true}"; then
    check_file "whisper-cli binary" "${AI_HOME:-$HOME/ai}/bin/whisper-cli"
else
    check "whisper-cli binary" skip "INSTALL_WHISPER disabled in config.env"
fi
if is_true "${INSTALL_OPENVINO:-true}"; then
    [[ -d "$HOME/venvs/openvino" ]] && check "OpenVINO venv" pass || check "OpenVINO venv" fail "run python/create_envs.sh"
else
    check "OpenVINO venv" skip "INSTALL_OPENVINO disabled in config.env"
fi
if is_true "${INSTALL_ONNXRUNTIME:-true}"; then
    [[ -d "$HOME/venvs/vision" ]] && check "ONNX Runtime venv (vision)" pass || check "ONNX Runtime venv" fail "run python/create_envs.sh"
else
    check "ONNX Runtime venv" skip "INSTALL_ONNXRUNTIME disabled in config.env"
fi

# ---------------------------------------------------------------------------
# Category: Python environments
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Python environments${C_RESET}"
for env in core openvino rag vision; do
    check_file "venv: ${env}" "$HOME/venvs/${env}/bin/activate"
done
# 'speech' is opt-in (see INSTALL_SPEECH_VENV in config.env) — checking it
# unconditionally would report a failure for an env deliberately not created.
if is_true "${INSTALL_SPEECH_VENV:-false}"; then
    check_file "venv: speech" "$HOME/venvs/speech/bin/activate"
else
    check "venv: speech" skip "INSTALL_SPEECH_VENV disabled in config.env"
fi

# ---------------------------------------------------------------------------
# Category: Services
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Services${C_RESET}"
if has_cmd docker; then
    for svc in awb-open-webui awb-qdrant awb-chromadb awb-postgres; do
        flag=""
        case "$svc" in
            awb-open-webui) flag="${INSTALL_OPENWEBUI:-true}" ;;
            awb-qdrant)     flag="${INSTALL_QDRANT:-false}" ;;
            awb-chromadb)   flag="${INSTALL_CHROMADB:-false}" ;;
            awb-postgres)   flag="${INSTALL_POSTGRES:-false}" ;;
        esac
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$svc"; then
            check "Service running: ${svc}" pass
        elif is_true "$flag"; then
            check "Service running: ${svc}" skip "enabled in config.env but not started"
        else
            check "Service running: ${svc}" skip "disabled in config.env"
        fi
    done
else
    check "Services" skip "Docker not installed"
fi
systemctl --user is-active --quiet llama-server 2>/dev/null \
    && check "llama-server systemd service" pass \
    || check "llama-server systemd service" skip "not enabled (systemctl --user enable --now llama-server)"

# ---------------------------------------------------------------------------
# Category: Security
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Security${C_RESET}"

# check_secret <label> <enabled_flag> <value> — flags a secret/password left
# at its committed config.env placeholder. Only meaningful for services that
# are actually enabled; a disabled service's unused default isn't a risk.
check_secret() {
    local label="$1" enabled_flag="$2" value="$3"
    if ! is_true "$enabled_flag"; then
        check "$label" skip "service disabled in config.env"
    elif [[ "$value" == "change-me" ]]; then
        check "$label" fail "still the default 'change-me' — edit config.env before exposing this service"
    else
        check "$label" pass
    fi
}
check_secret "Open WebUI secret key" "${INSTALL_OPENWEBUI:-true}" "${WEBUI_SECRET_KEY:-}"
check_secret "Postgres password" "${INSTALL_POSTGRES:-false}" "${POSTGRES_PASSWORD:-}"

# ---------------------------------------------------------------------------
# Category: Resources
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Resources${C_RESET}"

# These three passed a literal `pass` until this was fixed: they printed the
# numbers without ever comparing them to anything, so they reported green on a
# box with 1GB of RAM and no disk. Thresholds come from config.env, and the
# severities mirror lib/validation.sh (disk fatal, RAM degraded-but-usable) so
# doctor and install.sh cannot disagree about the same machine.
_min_ram="${MIN_RAM_GB:-8}"
if [[ ! "${RAM_GB:-}" =~ ^[0-9]+$ ]]; then
    check "RAM" warn "could not determine system RAM"
elif (( RAM_GB < _min_ram )); then
    check "RAM" warn "${RAM_GB} GB detected, ${_min_ram} GB recommended — low-memory mode: prefer smaller models and Q8_0 over Q4_K_M"
else
    check "RAM" pass "${RAM_GB} GB (min ${_min_ram} GB)"
fi

# VRAM only means something for a GPU with memory of its own. detect.sh reads
# it from nvidia-smi and nothing else, so it is 0 on every other vendor —
# reporting "0 GB / pass" reads as "no GPU memory" on an iGPU that is in fact
# running every layer out of shared system RAM at full speed.
if [[ "${VRAM_GB:-0}" =~ ^[0-9]+$ ]] && (( VRAM_GB > 0 )); then
    check "VRAM" pass "${VRAM_GB} GB dedicated"
elif [[ "${GPU_VENDOR:-}" == "Intel" ]]; then
    check "VRAM" skip "Intel iGPU has no dedicated VRAM — it shares system memory (${RAM_GB:-?} GB total)"
elif [[ "${HAS_AMD_GPU:-false}" == "true" ]]; then
    check "VRAM" skip "not measured on AMD — detect.sh reads VRAM via nvidia-smi only"
elif [[ "${PLATFORM_TARGET:-cpu}" == "cpu" ]]; then
    check "VRAM" skip "no GPU detected; CPU-only stack"
else
    check "VRAM" skip "not measured on ${GPU_VENDOR:-unknown} GPUs"
fi

_min_disk="${MIN_DISK_GB:-20}"
if [[ ! "${DISK_AVAIL_GB:-}" =~ ^[0-9]+$ ]]; then
    check "Disk free" warn "could not determine free space on $HOME"
elif (( DISK_AVAIL_GB < _min_disk )); then
    check "Disk free" fail "${DISK_AVAIL_GB} GB free on $HOME, ${_min_disk} GB required — model downloads will fail"
else
    check "Disk free" pass "${DISK_AVAIL_GB} GB free (min ${_min_disk} GB)"
fi

# ---------------------------------------------------------------------------
# Category: Models
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Models${C_RESET}"

# The Hugging Face CLI is what every model download goes through. It is not
# necessarily on PATH: create_envs.sh installs huggingface_hub into
# ~/venvs/core, which nothing activates — so resolve it exactly the way
# lib/downloader.sh does rather than just checking `has_cmd hf`.
if hf_cli_path="$(_awb_hf_cli 2>/dev/null)"; then
    check "Hugging Face CLI reachable" pass "$hf_cli_path"
else
    check "Hugging Face CLI reachable" fail "no 'hf' found on PATH or in ~/venvs/core; model downloads will fail (pip install huggingface_hub, or ./install.sh --only python)"
fi

model_count=$(find "${AI_HOME:-$HOME/ai}/models/gguf" -name '*.gguf' 2>/dev/null | wc -l) || model_count=0
if (( model_count > 0 )); then
    check "GGUF models installed" pass "${model_count} file(s)"
else
    check "GGUF models installed" fail "run: awb model install ${DEFAULT_MODEL:-gemma3-e2b}"
fi

# whisper-cli is useless without a GGML model, and benchmarks/whisper/run.sh
# needs one specifically — checking only the binary let a green doctor run
# still be followed by a failing `awb benchmark whisper`.
if is_true "${INSTALL_WHISPER:-true}"; then
    whisper_count=$(find "${AI_HOME:-$HOME/ai}/models/whisper" -name '*.bin' 2>/dev/null | wc -l) || whisper_count=0
    if (( whisper_count > 0 )); then
        check "Whisper models installed" pass "${whisper_count} file(s)"
    else
        check "Whisper models installed" fail "run: awb model install whisper-base.en"
    fi
else
    check "Whisper models installed" skip "INSTALL_WHISPER disabled in config.env"
fi

# ---------------------------------------------------------------------------
# Summary + report generation
# ---------------------------------------------------------------------------
total=${#AWB_CHECK_NAMES[@]}
passed=0; warned=0; failed=0; skipped=0
for s in "${AWB_CHECK_STATUS[@]}"; do
    case "$s" in
        pass) passed=$((passed+1)) ;;
        warn) warned=$((warned+1)) ;;
        fail) failed=$((failed+1)) ;;
        skip) skipped=$((skipped+1)) ;;
    esac
done

summary_line="${passed} passed, ${warned} warned, ${failed} failed, ${skipped} skipped (of ${total})"
echo -e "\n${C_BOLD}Summary:${C_RESET} ${summary_line}"

ensure_dir "${AWB_ROOT}/reports"

# _json_escape <string> — escape JSON special characters in a string.
_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s" | tr -d '[\000-\010\013\014\016-\037]'
}
{
    echo "{"
    echo "  \"total\": ${total},"
    echo "  \"passed\": ${passed},"
    echo "  \"warned\": ${warned},"
    echo "  \"failed\": ${failed},"
    echo "  \"skipped\": ${skipped},"
    echo "  \"checks\": ["
    for i in "${!AWB_CHECK_NAMES[@]}"; do
        sep=","; [[ $i -eq $((total-1)) ]] && sep=""
        printf '    {"name": "%s", "status": "%s", "detail": "%s"}%s\n' \
            "$(_json_escape "${AWB_CHECK_NAMES[$i]}")" \
            "$(_json_escape "${AWB_CHECK_STATUS[$i]}")" \
            "$(_json_escape "${AWB_CHECK_DETAIL[$i]}")" \
            "$sep"
    done
    echo "  ]"
    echo "}"
} > "${AWB_ROOT}/reports/doctor.json"

{
    echo "# AI-Workbench Doctor Report"
    echo
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Summary: ${summary_line}"
    echo
    for i in "${!AWB_CHECK_NAMES[@]}"; do
        case "${AWB_CHECK_STATUS[$i]}" in
            fail) mark="✘" ;;
            warn) mark="⚠" ;;
            skip) mark="○" ;;
            *)    mark="✔" ;;
        esac
        echo "- ${mark} ${AWB_CHECK_NAMES[$i]}${AWB_CHECK_DETAIL[$i]:+ — ${AWB_CHECK_DETAIL[$i]}}"
    done
} > "${AWB_ROOT}/reports/doctor.md"

log_info "Reports written: reports/doctor.json, reports/doctor.md"

if (( failed > 0 )); then exit 1; else exit 0; fi
