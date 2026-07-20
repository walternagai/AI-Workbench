#!/usr/bin/env bash
# monitoring/memory.sh — RAM/swap usage snapshot.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

monitor_memory() {
    echo -e "${C_BOLD}Memory${C_RESET}"
    free -h | awk 'NR==1{print "  " $0} NR==2{print "  " $0} NR==3{print "  " $0}'
}
