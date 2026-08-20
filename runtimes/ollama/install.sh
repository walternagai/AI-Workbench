#!/usr/bin/env bash
# runtimes/ollama/install.sh — installs Ollama via the official install script.
#
# Security note: downloads the installer to a temp file, verifies it looks
# like a shell script (starts with #! shebang), and only then executes it.
# This avoids the "curl | sh" anti-pattern (partial download execution,
# no audit trail, MITM risk without verification).
#
# Note (per Walter's hardware notes): on Intel iGPUs without a Vulkan backend
# in Ollama's engine, this runs CPU-only. NVIDIA/AMD get GPU acceleration
# out of the box once drivers (cuda.sh/rocm.sh) are installed.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

# _ollama_download — download Ollama installer to a temp file and verify
# it is a plausible shell script before execution.
_ollama_download() {
    local tmpfile
    tmpfile="$(mktemp /tmp/ollama-install.XXXXXX.sh)"

    require_cmd curl "Ollama installer"
    # stdout is the function's return channel ($(_ollama_download)); keep log
    # lines off it or they end up inside the filename the caller runs.
    log_info "Downloading Ollama installer to ${tmpfile} ..." >&2
    curl --fail --location --progress-bar \
        --retry 3 --retry-delay 5 \
        --output "$tmpfile" \
        https://ollama.com/install.sh \
        || { rm -f "$tmpfile"; fail_loud "Ollama installer download failed"; }

    # Basic sanity check: verify it starts with a shell shebang.
    if ! head -1 "$tmpfile" | grep -qE '^#!(/bin/(sh|bash)|/usr/bin/(env bash|env sh))'; then
        rm -f "$tmpfile"
        fail_loud "Ollama installer does not appear to be a shell script; aborting for safety."
    fi

    echo "$tmpfile"
}

install_ollama() {
    log_step "Installing Ollama"

    if has_cmd ollama; then
        log_ok "Ollama already installed ($(ollama --version 2>/dev/null | head -1))."
    else
        local installer
        installer="$(_ollama_download)"
        log_info "Running Ollama installer ..."
        sh "$installer" || { rm -f "$installer"; fail_loud "Ollama install script failed"; }
        rm -f "$installer"
    fi

    if [[ "${PLATFORM_TARGET:-}" == "intel" && "${HAS_INTEL_ARC:-false}" != "false" ]]; then
        log_warn "Ollama has no Vulkan backend for Intel iGPUs on this stack; it will run CPU-only here. Prefer llama.cpp (Vulkan) for GPU-accelerated inference on this hardware."
    fi

    systemctl is-active --quiet ollama 2>/dev/null \
        && log_ok "ollama systemd service is active." \
        || log_warn "ollama systemd service not active; start with: sudo systemctl enable --now ollama"
}

update_ollama() {
    log_step "Updating Ollama"
    local installer
    installer="$(_ollama_download)"
    log_info "Running Ollama installer (update) ..."
    sh "$installer" || { rm -f "$installer"; fail_loud "Ollama update failed"; }
    rm -f "$installer"
}

remove_ollama() {
    log_step "Removing Ollama"
    sudo systemctl stop ollama 2>/dev/null || true
    sudo systemctl disable ollama 2>/dev/null || true
    sudo rm -f /usr/local/bin/ollama /usr/bin/ollama
    log_ok "Ollama removed (models under ~/.ollama left intact; delete manually if desired)."
}
