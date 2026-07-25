#!/usr/bin/env bash
# lib/utils.sh — generic helpers shared across AI-Workbench modules.

[[ -n "${AWB_UTILS_LOADED:-}" ]] && return 0
AWB_UTILS_LOADED=1

# Set non-interactive frontend for apt so package installs never prompt
# (works for all scripts that source this library, from install.sh to
# individual platform/runtime modules).
export DEBIAN_FRONTEND=noninteractive

# has_cmd <name> — true if a binary is on PATH.
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# require_cmd <name> [why] — fail-loud if a required binary is missing.
# Prerequisites are never assumed silently; a missing tool aborts the
# script with a clear, actionable message instead of failing three
# steps later with a confusing error.
require_cmd() {
    local cmd="$1" why="${2:-required by AI-Workbench}"
    has_cmd "$cmd" || fail_loud "Missing prerequisite '$cmd' ($why). Install it and re-run."
}

# is_true <value> — treats "true"/"1"/"yes" (any case) as boolean true.
# Used to evaluate config.env flags like INSTALL_OLLAMA=true.
is_true() {
    local v
    v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
    [[ "$v" == "true" || "$v" == "1" || "$v" == "yes" ]]
}

# ensure_dir <path> — idempotent directory creation, fail-loud on error.
ensure_dir() {
    mkdir -p "$1" || fail_loud "Could not create directory: $1"
}

# ensure_prereq_dirs — shared prerequisite resources created unconditionally,
# BEFORE any platform/runtime conditional branches run. This is a hard rule:
# a real bug (a runtime silently depending on a directory only created by a
# platform branch that hadn't executed yet) was caught during v1.0 QA and
# fixed by centralizing this here. Never move these into an if-block.
ensure_prereq_dirs() {
    ensure_dir "${AWB_ROOT}/logs"
    ensure_dir "${AWB_ROOT}/reports"
    ensure_dir "${AI_HOME:-$HOME/ai}"
    ensure_dir "${AI_HOME:-$HOME/ai}/models"
    ensure_dir "${AI_HOME:-$HOME/ai}/bin"
    ensure_dir "$HOME/venvs"
}

# retry <n> <sleep_seconds> <command...> — retry a flaky command n times.
retry() {
    local n="$1" delay="$2"; shift 2
    local i=0
    until "$@"; do
        i=$((i + 1))
        if (( i >= n )); then
            return 1
        fi
        log_warn "Command failed (attempt $i/$n), retrying in ${delay}s: $*"
        sleep "$delay"
    done
}

# sudo_keepalive — keep sudo's timestamp fresh for the duration of a long
# install so the user isn't prompted mid-flow. Cleans itself up on exit
# (via EXIT, INT and TERM traps so no background processes are left behind).
#
# SIGKILL cannot be trapped, but the background process checks the parent
# PID every 30 s via kill -0; if the parent has died it exits on its own
# within that window.
sudo_keepalive() {
    if [[ "${EUID}" -eq 0 ]]; then
        return 0  # already root, nothing to keep alive
    fi
    require_cmd sudo "system package installation"
    sudo -v || fail_loud "sudo authentication failed"
    # background loop: refresh sudo every 4 minutes (default timeout is 5);
    # check parent liveness every 30 s to bound orphan lifetime.
    (
        while true; do
            sudo -n true 2>/dev/null || exit
            sleep 30
            kill -0 "$$" 2>/dev/null || exit
        done
    ) &
    AWB_SUDO_KEEPALIVE_PID=$!
    _cleanup_sudo() {
        kill "$AWB_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    }
    trap '_cleanup_sudo' EXIT INT TERM
}

# apt_update_once — run apt-get update at most once per process tree,
# so repeated calls from platform scripts don't hammer the network.
# Uses a process-tree marker (AWB_APT_UPDATED) rather than a temp file.
apt_update_once() {
    if [[ -n "${AWB_APT_UPDATED:-}" ]]; then
        return 0
    fi
    export AWB_APT_UPDATED=1
    log_info "Updating package lists (once per run)..."
    sudo apt-get update -y || fail_loud "apt-get update failed"
}

# confirm <prompt> — interactive yes/no, defaults to "no".
# Uses printf %b to safely interpret colour escape sequences (replaces
# non-portable echo -e).
confirm() {
    local prompt="$1" reply
    printf '%b%s%b [y/N] ' "${C_YELLOW}" "$prompt" "${C_RESET}"
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# load_env <path> — source a .env file if it exists, fail-loud if it's
# supposed to exist and doesn't.
load_env() {
    local path="$1" required="${2:-false}"
    if [[ -f "$path" ]]; then
        # shellcheck disable=SC1090
        set -a; source "$path"; set +a
    elif is_true "$required"; then
        fail_loud "Required environment file not found: $path"
    fi
}

# safe_source <path> — source a script only if it exists; fail-loud if missing.
# Eliminates silent failures when a required module is absent.
safe_source() {
    local path="$1"
    if [[ -f "$path" ]]; then
        # shellcheck disable=SC1090
        source "$path"
    else
        fail_loud "Required module not found: $path"
    fi
}

# json_kv <key> <value> — emit one "key": "value" JSON line (no trailing comma).
# Escapes backslash, double-quote, newline, tab, carriage-return, and
# control characters so the output is always valid JSON.
json_kv() {
    local key="$1" value="$2"
    # Escape sequence: \ → \\, " → \", newline → \n, tab → \t, CR → \r
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\t'/\\t}"
    value="${value//$'\r'/\\r}"
    # Strip remaining control characters (0x00–0x1F except those already escaped).
    # Uses printf instead of echo -n to avoid reinterpreting backslash sequences.
    value="$(printf '%s' "$value" | tr -d '[\000-\010\013\014\016-\037]')"
    printf '  "%s": "%s"' "$key" "$value"
}
