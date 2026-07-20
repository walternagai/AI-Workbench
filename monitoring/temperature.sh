#!/usr/bin/env bash
# monitoring/temperature.sh — thermal sensor snapshot (best-effort; not all
# systems expose sensors without lm-sensors configured).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

monitor_temperature() {
    echo -e "${C_BOLD}Temperature${C_RESET}"
    if has_cmd sensors; then
        sensors 2>/dev/null | grep -E '°C' | sed 's/^/  /'
    else
        echo "  lm-sensors not installed (sudo apt-get install lm-sensors && sudo sensors-detect)"
    fi
}
