#!/usr/bin/env bash
# monitoring/temperature.sh — thermal sensor snapshot (best-effort; not all
# systems expose sensors without lm-sensors configured).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

monitor_temperature() {
    echo -e "${C_BOLD}Temperature${C_RESET}"
    if has_cmd sensors; then
        # grep exits 1 when sensors reports no Celsius line. Under pipefail and
        # set -e that aborted `awb monitor` with no message (M5), so the empty
        # case is handled here.
        sensors 2>/dev/null | grep -E '°C' | sed 's/^/  /' \
            || echo "  sensors não reportou leituras em °C"
    else
        echo "  lm-sensors not installed (sudo apt-get install lm-sensors && sudo sensors-detect)"
    fi
}
