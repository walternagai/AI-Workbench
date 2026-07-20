#!/usr/bin/env bash
# lib/utils.sh — generic helpers shared across AI-Workbench modules.

[[ -n "${AWB_UTILS_LOADED:-}" ]] && return 0
AWB_UTILS_LOADED=1

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
# install so the user isn't prompted mid-flow. Cleans itself up on exit.
sudo_keepalive() {
    if [[ "${EUID}" -eq 0 ]]; then
        return 0  # already root, nothing to keep alive
    fi
    require_cmd sudo "system package installation"
    sudo -v || fail_loud "sudo authentication failed"
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    AWB_SUDO_KEEPALIVE_PID=$!
    trap 'kill "$AWB_SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

# confirm <prompt> — interactive yes/no, defaults to "no".
confirm() {
    local prompt="$1" reply
    read -r -p "$(echo -e "${C_YELLOW}${prompt}${C_RESET} [y/N] ")" reply
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

# json_kv <key> <value> — emit one "key": "value" JSON line (no trailing comma).
json_kv() {
    printf '  "%s": "%s"' "$1" "$2"
}
