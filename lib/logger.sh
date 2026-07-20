#!/usr/bin/env bash
# lib/logger.sh — structured logging for every AI-Workbench script.
#
# Design principles (see docs/PRINCIPLES.md):
#   - Fail-loud: errors are never swallowed, they are logged and propagated.
#   - Every action is observable: all log lines go to stdout/stderr AND to
#     logs/installation.log, timestamped and leveled, so `doctor.sh` and
#     post-mortem debugging always have a full trail.

[[ -n "${AWB_LOGGER_LOADED:-}" ]] && return 0
AWB_LOGGER_LOADED=1

AWB_ROOT="${AWB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
AWB_LOG_DIR="${AWB_ROOT}/logs"
AWB_LOG_FILE="${AWB_LOG_DIR}/installation.log"

mkdir -p "$AWB_LOG_DIR"
touch "$AWB_LOG_FILE"

_log_timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

_log_write() {
    local level="$1" msg="$2"
    printf '%s [%s] %s\n' "$(_log_timestamp)" "$level" "$msg" >> "$AWB_LOG_FILE"
}

log_info() {
    echo -e "${C_CYAN}[INFO]${C_RESET}  $*"
    _log_write "INFO" "$*"
}

log_ok() {
    echo -e "${CHECK_MARK} $*"
    _log_write "OK" "$*"
}

log_warn() {
    echo -e "${WARN_MARK} ${C_YELLOW}$*${C_RESET}" >&2
    _log_write "WARN" "$*"
}

log_error() {
    echo -e "${CROSS_MARK} ${C_RED}$*${C_RESET}" >&2
    _log_write "ERROR" "$*"
}

log_step() {
    echo -e "\n${C_BOLD}${C_BLUE}==> $*${C_RESET}"
    _log_write "STEP" "$*"
}

# fail_loud <message> [exit_code]
# Core fail-loud primitive: log the error and abort immediately.
# Never call this from a subshell you intend to keep running after —
# it is meant to stop the current script cold.
fail_loud() {
    local msg="$1"
    local code="${2:-1}"
    log_error "FATAL: $msg"
    log_error "Aborting. See ${AWB_LOG_FILE} for the full trail."
    exit "$code"
}
