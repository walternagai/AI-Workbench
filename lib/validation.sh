#!/usr/bin/env bash
# lib/validation.sh — pre-flight validation shared by install.sh and doctor.sh.

[[ -n "${AWB_VALIDATION_LOADED:-}" ]] && return 0
AWB_VALIDATION_LOADED=1

AWB_SUPPORTED_DISTROS=("ubuntu" "pop" "linuxmint")

# validate_os — fail-loud if running on an unsupported distro.
# Portability principle: v1.0 targets Ubuntu, Pop!_OS and Linux Mint
# explicitly; anything else is refused rather than silently attempted.
validate_os() {
    # AWB_OS_RELEASE exists so the unsupported-distro path is reachable from a
    # unit test without a container: nothing else should ever override it.
    local osrel="${AWB_OS_RELEASE:-/etc/os-release}"
    [[ -f "$osrel" ]] || fail_loud "Cannot detect OS: ${osrel} not found."
    # Parse os-release with awk instead of sourcing it,
    # for the same security and isolation reasons as detect.sh.
    local id like pretty
    id=$(awk -F= '/^ID=/          {gsub(/"/,"",$2); print $2; exit}' "$osrel") || id="unknown"
    like=$(awk -F= '/^ID_LIKE=/    {gsub(/"/,"",$2); print $2; exit}' "$osrel") || like=""
    pretty=$(awk -F= '/^PRETTY_NAME=/ {gsub(/"/,"",$2); print $2; exit}' "$osrel") || pretty="$id"
    local supported=false
    for d in "${AWB_SUPPORTED_DISTROS[@]}"; do
        if [[ "$id" == "$d" || "$like" == *"$d"* || "$like" == *"debian"* || "$id" == "debian" ]]; then
            supported=true
            break
        fi
    done
    if [[ "$supported" != true ]]; then
        fail_loud "Unsupported distribution: '${pretty}'. Supported: Ubuntu, Pop!_OS, Linux Mint."
    fi
    export AWB_OS_ID="$id"
    export AWB_OS_PRETTY="$pretty"
    log_ok "OS supported: ${AWB_OS_PRETTY}"
}

# validate_arch — currently x86_64 only.
validate_arch() {
    local arch
    arch="$(uname -m)"
    if [[ "$arch" != "x86_64" ]]; then
        fail_loud "Unsupported architecture: $arch (AI-Workbench v1.0 supports x86_64 only)."
    fi
    export AWB_ARCH="$arch"
    log_ok "Architecture supported: $arch"
}

# validate_disk_space <min_gb> <path>
validate_disk_space() {
    local min_gb="$1" path="${2:-$HOME}" avail_gb
    avail_gb=$(df -BG --output=avail "$path" 2>/dev/null | tail -1 | tr -dc '0-9')
    if [[ -z "$avail_gb" ]]; then
        log_warn "Could not determine free disk space on $path; skipping check."
        return 0
    fi
    if (( avail_gb < min_gb )); then
        fail_loud "Insufficient disk space on $path: ${avail_gb}GB free, ${min_gb}GB required."
    fi
    log_ok "Disk space OK: ${avail_gb}GB free on $path"
}

# validate_ram <min_gb>
validate_ram() {
    local min_gb="$1" total_gb
    total_gb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
    if (( total_gb < min_gb )); then
        log_warn "System has ${total_gb}GB RAM; ${min_gb}GB recommended. Continuing with reduced defaults."
        export AWB_LOW_MEMORY=true
    else
        export AWB_LOW_MEMORY=false
    fi
    log_ok "RAM detected: ${total_gb}GB (low-memory mode: ${AWB_LOW_MEMORY})"
}

# validate_not_root_unless_intended — warn (don't abort) if run as root
# outside a container, since package installs behave differently.
validate_not_root_unless_intended() {
    if [[ "$EUID" -eq 0 && -z "${AWB_ALLOW_ROOT:-}" ]]; then
        log_warn "Running as root. Set AWB_ALLOW_ROOT=true to silence this warning."
    fi
}
