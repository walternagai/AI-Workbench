#!/usr/bin/env bash
# monitoring/cpu.sh — CPU utilization/frequency snapshot.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

monitor_cpu() {
    echo -e "${C_BOLD}CPU${C_RESET}"
    echo "  Load average: $(cut -d' ' -f1-3 /proc/loadavg)"
    if has_cmd mpstat; then
        mpstat 1 1 | tail -1 | awk '{printf "  Utilization: %.1f%%\n", 100 - $NF}'
    fi
    if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
        local freq_khz
        freq_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
        printf '  Frequency (cpu0): %.2f GHz\n' "$(echo "$freq_khz / 1000000" | bc -l)"
    fi
}
