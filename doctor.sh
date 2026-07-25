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

load_env "${AWB_ROOT}/config.env" false

safe_source "${AWB_ROOT}/detect.sh"
declare -F run_all_detections &>/dev/null || fail_loud "detect.sh loaded but run_all_detections() not found"
declare -F resolve_platform_target &>/dev/null || fail_loud "detect.sh loaded but resolve_platform_target() not found"
run_all_detections >/dev/null 2>&1
resolve_platform_target >/dev/null 2>&1

declare -a AWB_CHECK_NAMES=()
declare -a AWB_CHECK_STATUS=()   # "pass" | "fail" | "skip"
declare -a AWB_CHECK_DETAIL=()

check() {
    local name="$1" status="$2" detail="${3:-}"
    AWB_CHECK_NAMES+=("$name")
    AWB_CHECK_STATUS+=("$status")
    AWB_CHECK_DETAIL+=("$detail")
    case "$status" in
        pass) echo -e "  ${CHECK_MARK} ${name}" ;;
        fail) echo -e "  ${CROSS_MARK} ${name}${detail:+ — ${detail}}" ;;
        skip) echo -e "  ${WARN_MARK} ${name} (skipped)${detail:+ — ${detail}}" ;;
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
check_file "llama-server binary" "${AI_HOME:-$HOME/ai}/bin/llama-server"
check_file "llama-cli binary" "${AI_HOME:-$HOME/ai}/bin/llama-cli"
check_cmd "Ollama" ollama
check_file "whisper-cli binary" "${AI_HOME:-$HOME/ai}/bin/whisper-cli"
[[ -d "$HOME/venvs/openvino" ]] && check "OpenVINO venv" pass || check "OpenVINO venv" fail "run python/create_envs.sh"
[[ -d "$HOME/venvs/vision" ]] && check "ONNX Runtime venv (vision)" pass || check "ONNX Runtime venv" fail "run python/create_envs.sh"

# ---------------------------------------------------------------------------
# Category: Python environments
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Python environments${C_RESET}"
for env in core openvino rag vision speech; do
    check_file "venv: ${env}" "$HOME/venvs/${env}/bin/activate"
done

# ---------------------------------------------------------------------------
# Category: Services
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Services${C_RESET}"
if has_cmd docker; then
    for svc in awb-open-webui awb-qdrant awb-chromadb awb-postgres; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$svc"; then
            check "Service running: ${svc}" pass
        else
            check "Service running: ${svc}" skip "not started (see config.env INSTALL_* flags)"
        fi
    done
else
    check "Services" skip "Docker not installed"
fi
systemctl --user is-active --quiet llama-server 2>/dev/null \
    && check "llama-server systemd service" pass \
    || check "llama-server systemd service" skip "not enabled (systemctl --user enable --now llama-server)"

# ---------------------------------------------------------------------------
# Category: Resources
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Resources${C_RESET}"
check "RAM" pass "${RAM_GB:-?} GB"
check "VRAM" pass "${VRAM_GB:-0} GB"
check "Disk free" pass "${DISK_AVAIL_GB:-?} GB"

# ---------------------------------------------------------------------------
# Category: Models
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Models${C_RESET}"
model_count=$(find "${AI_HOME:-$HOME/ai}/models/gguf" -name '*.gguf' 2>/dev/null | wc -l) || model_count=0
if (( model_count > 0 )); then
    check "GGUF models installed" pass "${model_count} file(s)"
else
    check "GGUF models installed" fail "run: awb model install ${DEFAULT_MODEL:-gemma3-e2b}"
fi

# ---------------------------------------------------------------------------
# Summary + report generation
# ---------------------------------------------------------------------------
total=${#AWB_CHECK_NAMES[@]}
passed=0; failed=0; skipped=0
for s in "${AWB_CHECK_STATUS[@]}"; do
    case "$s" in
        pass) passed=$((passed+1)) ;;
        fail) failed=$((failed+1)) ;;
        skip) skipped=$((skipped+1)) ;;
    esac
done

echo -e "\n${C_BOLD}Summary:${C_RESET} ${passed} passed, ${failed} failed, ${skipped} skipped (of ${total})"

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
    echo "Summary: ${passed} passed, ${failed} failed, ${skipped} skipped (of ${total})"
    echo
    for i in "${!AWB_CHECK_NAMES[@]}"; do
        mark="✔"; [[ "${AWB_CHECK_STATUS[$i]}" == "fail" ]] && mark="✘"; [[ "${AWB_CHECK_STATUS[$i]}" == "skip" ]] && mark="⚠"
        echo "- ${mark} ${AWB_CHECK_NAMES[$i]}${AWB_CHECK_DETAIL[$i]:+ — ${AWB_CHECK_DETAIL[$i]}}"
    done
} > "${AWB_ROOT}/reports/doctor.md"

log_info "Reports written: reports/doctor.json, reports/doctor.md"

if (( failed > 0 )); then exit 1; else exit 0; fi
