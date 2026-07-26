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

# _cmd_version <cmd> — best-effort one-line version string, empty if none.
#
# Deliberately forgiving: this is diagnostic detail, not a check, so nothing
# here may fail a run or hang one. `timeout` guards tools that block without a
# tty, and the digit test rejects tools whose --version prints something else
# entirely (intel_gpu_top answers with its one-line description).
_cmd_version() {
    local cmd="$1" out=""
    out="$(timeout 5 "$cmd" --version 2>/dev/null | head -1)"
    [[ -z "$out" ]] && out="$(timeout 5 "$cmd" -version 2>/dev/null | head -1)"
    [[ "$out" =~ [0-9]+\.[0-9]+ ]] || out=""
    # Trim the tails that make these lines long without making them
    # informative: curl's library inventory after "(", pip's install path
    # after " from " (already covered by the resolved path we print anyway).
    out="${out%% (*}"
    out="${out%% from *}"
    printf '%s' "$out" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//' | cut -c1-60
}

# _venv_pkg_version <venv> <package> — prints the installed version of <package>
# inside ~/venvs/<venv>, returns non-zero if it isn't installed there.
_venv_pkg_version() {
    local venv="$1" pkg="$2" py="$HOME/venvs/$1/bin/python" ver=""
    [[ -x "$py" ]] || return 1
    ver="$(timeout 30 "$py" -c "import importlib.metadata as m; print(m.version('${pkg}'))" 2>/dev/null)"
    [[ -n "$ver" ]] || return 1
    printf '%s' "$ver"
}

check_cmd() {
    local label="$1" cmd="$2" path ver
    if path="$(command -v "$cmd" 2>/dev/null)"; then
        # Record the resolved path alongside the version: "which binary am I
        # actually getting" is the question a PATH shadowed by a stray venv or
        # a hand-built /usr/local copy makes you ask, and the answer belongs in
        # the report rather than in a follow-up round trip.
        ver="$(_cmd_version "$cmd")"
        check "$label" pass "${ver:+${ver} — }${path}"
    else
        check "$label" fail "'$cmd' not found on PATH"
    fi
}

check_file() {
    local label="$1" path="$2" detail="$2" target bytes size
    if [[ ! -e "$path" ]]; then
        check "$label" fail "$path missing"
        return
    fi
    # Everything install.sh drops in ~/ai/bin is a symlink into the build tree,
    # so resolve it: "which build is this binary from" is the question that
    # actually gets asked, and du on the link itself reports 0.
    if [[ -L "$path" ]]; then
        target="$(readlink -f "$path" 2>/dev/null)"
        [[ -n "$target" && "$target" != "$path" ]] && detail="${path} -> ${target}"
    fi
    # Size only where it carries information. Printing "4,0K" beside a venv
    # activate script is noise; printing it beside a 4.8GB model is not.
    bytes="$(stat -Lc %s "$path" 2>/dev/null)"
    if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes >= 1048576 )); then
        size="$(du -Lh "$path" 2>/dev/null | cut -f1)"
        detail="${detail}${size:+ (${size})}"
    fi
    check "$label" pass "$detail"
}

check_true() {
    local label="$1" cond="$2" fail_detail="${3:-}" pass_detail="${4:-}"
    if [[ "$cond" == "true" ]]; then
        check "$label" pass "$pass_detail"
    else
        check "$label" fail "$fail_detail"
    fi
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
if has_cmd docker && compose_ver="$(docker compose version 2>/dev/null)"; then
    check "Docker Compose plugin" pass "$compose_ver"
else
    check "Docker Compose plugin" fail "run: sudo apt-get install docker-compose-plugin"
fi
check_cmd "Python 3" python3
if python3 -m venv --help >/dev/null 2>&1; then
    check "python3-venv module" pass "$(python3 --version 2>&1)"
else
    check "python3-venv module" fail "sudo apt-get install python3-venv"
fi
check_cmd "pip" pip3

# ---------------------------------------------------------------------------
# Category: Acceleration APIs
# ---------------------------------------------------------------------------
echo -e "\n${C_BOLD}Acceleration${C_RESET}"
check_true "Vulkan" "${HAS_VULKAN:-false}" "no functional Vulkan device detected" "${VULKAN_DEVICE:-device name unavailable}"
check_true "OpenCL" "${HAS_OPENCL:-false}" "no OpenCL platform detected" "${OPENCL_DEVICE:-device name unavailable}"
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
    check_true "Intel Arc / iGPU detected" \
        "$( [[ "${GPU_VENDOR:-}" == "Intel" ]] && echo true || echo false )" \
        "PLATFORM_TARGET is intel but GPU_VENDOR is '${GPU_VENDOR:-unset}'" \
        "${GPU_MODEL:-unknown}"
    if [[ "${HAS_INTEL_NPU:-false}" == "true" ]]; then
        check_true "Intel NPU" "${HAS_INTEL_NPU}" "" "accel device present"
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
# These report the installed package version, not just the venv's existence:
# an empty venv passes a directory test while every import in it fails.
if is_true "${INSTALL_OPENVINO:-true}"; then
    if [[ ! -d "$HOME/venvs/openvino" ]]; then
        check "OpenVINO venv" fail "$HOME/venvs/openvino missing — run: awb install --only python"
    elif _ver="$(_venv_pkg_version openvino openvino)"; then
        check "OpenVINO venv" pass "openvino ${_ver}"
    else
        check "OpenVINO venv" warn "venv exists but 'openvino' is not installed in it — run: awb install --only platform"
    fi
else
    check "OpenVINO venv" skip "INSTALL_OPENVINO disabled in config.env"
fi
if is_true "${INSTALL_ONNXRUNTIME:-true}"; then
    if [[ ! -d "$HOME/venvs/vision" ]]; then
        check "ONNX Runtime venv (vision)" fail "$HOME/venvs/vision missing — run: awb install --only python"
    elif _ver="$(_venv_pkg_version vision onnxruntime-openvino)"; then
        check "ONNX Runtime venv (vision)" pass "onnxruntime-openvino ${_ver}"
    else
        check "ONNX Runtime venv (vision)" warn "venv exists but 'onnxruntime-openvino' is not installed in it — run: awb install --only runtimes"
    fi
else
    check "ONNX Runtime venv (vision)" skip "INSTALL_ONNXRUNTIME disabled in config.env"
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
        # A service the user asked for in config.env but which isn't running is
        # a discrepancy between intent and reality — that's "warn". Only a
        # service nobody asked for is genuinely not applicable ("skip").
        svc_status="$(docker ps --filter "name=^${svc}$" --format '{{.Status}}' 2>/dev/null | head -1)"
        if [[ -n "$svc_status" ]]; then
            check "Service running: ${svc}" pass "$svc_status"
        elif is_true "$flag"; then
            check "Service running: ${svc}" warn "enabled in config.env but not running — start it with: awb install --only services"
        else
            check "Service running: ${svc}" skip "disabled in config.env"
        fi
    done
elif is_true "${INSTALL_OPENWEBUI:-true}" || is_true "${INSTALL_QDRANT:-false}" \
  || is_true "${INSTALL_CHROMADB:-false}" || is_true "${INSTALL_POSTGRES:-false}"; then
    check "Services" warn "Docker not installed, but services are enabled in config.env"
else
    check "Services" skip "Docker not installed, and no services enabled in config.env"
fi

# Three distinct states, which a bare is-active test used to collapse into one
# "skipped": never asked for (skip), asked for and installed but not running
# (warn — install.sh writes the unit but deliberately does not enable it), and
# asked for with no unit on disk at all (warn, a different remedy).
_llama_unit="$HOME/.config/systemd/user/llama-server.service"
if ! is_true "${INSTALL_LLAMACPP_SERVICE:-true}"; then
    check "llama-server systemd service" skip "INSTALL_LLAMACPP_SERVICE disabled in config.env"
elif [[ ! -f "$_llama_unit" ]]; then
    check "llama-server systemd service" warn "enabled in config.env but no unit at ${_llama_unit} — run: awb install --only runtimes"
elif systemctl --user is-active --quiet llama-server 2>/dev/null; then
    check "llama-server systemd service" pass "active"
else
    check "llama-server systemd service" warn "unit installed but not running — start it with: systemctl --user enable --now llama-server"
fi

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
    # See json_kv in lib/utils.sh: no enclosing [] — tr would delete them
    # literally, stripping brackets out of device names and paths.
    printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037'
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
