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
AWB_LOG_MAX_BYTES=$((10 * 1024 * 1024))  # 10 MB before rotation
AWB_LOG_KEEP=3                           # keep 3 rotated backups

mkdir -p "$AWB_LOG_DIR"

# Rotate log if it exceeds the max size: keep up to N rotated copies,
# discarding the oldest.  Inspired by logrotate's simple copy-truncate
# but using mv+create so we never lose a line between copy and truncate.
_log_rotate() {
    local f
    if [[ -f "$AWB_LOG_FILE" && "$(stat -c%s "$AWB_LOG_FILE" 2>/dev/null || echo 0)" -ge $AWB_LOG_MAX_BYTES ]]; then
        # Shift old backups: N → N+1, then drop the last
        for ((f = AWB_LOG_KEEP; f > 0; f--)); do
            [[ -f "${AWB_LOG_FILE}.${f}" ]] && mv "${AWB_LOG_FILE}.${f}" "${AWB_LOG_FILE}.$((f + 1))" 2>/dev/null || true
        done
        mv "$AWB_LOG_FILE" "${AWB_LOG_FILE}.1" 2>/dev/null || true
    fi
}

_log_rotate
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
