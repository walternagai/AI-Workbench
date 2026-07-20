#!/usr/bin/env bash
# lib/colors.sh — ANSI color codes shared by every AI-Workbench script.
# Sourced, never executed directly. Guarded so re-sourcing is harmless.

[[ -n "${AWB_COLORS_LOADED:-}" ]] && return 0
AWB_COLORS_LOADED=1

if [[ -t 1 ]]; then
    export C_RESET='\033[0m'
    export C_BOLD='\033[1m'
    export C_DIM='\033[2m'
    export C_RED='\033[0;31m'
    export C_GREEN='\033[0;32m'
    export C_YELLOW='\033[0;33m'
    export C_BLUE='\033[0;34m'
    export C_MAGENTA='\033[0;35m'
    export C_CYAN='\033[0;36m'
    export C_WHITE='\033[0;37m'
else
    # Not a terminal (redirected to a file/CI log) — no escape codes.
    export C_RESET='' C_BOLD='' C_DIM=''
    export C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE=''
fi

export CHECK_MARK="${C_GREEN}✔${C_RESET}"
export CROSS_MARK="${C_RED}✘${C_RESET}"
export WARN_MARK="${C_YELLOW}⚠${C_RESET}"
export ARROW="${C_CYAN}➜${C_RESET}"
