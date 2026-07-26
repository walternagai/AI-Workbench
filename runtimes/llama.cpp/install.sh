#!/usr/bin/env bash
# runtimes/llama.cpp/install.sh — clones and compiles llama.cpp with the
# backend appropriate to the detected hardware:
#   NVIDIA  -> CUDA (GGML_CUDA)
#   AMD     -> HIP  (GGML_HIP)
#   Intel   -> Vulkan (GGML_VULKAN) — practical path on iGPUs (see docs/PRINCIPLES.md)
#   CPU     -> OpenBLAS
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

AWB_LLAMACPP_SRC="${AI_HOME:-$HOME/ai}/src/llama.cpp"
AWB_LLAMACPP_REPO="https://github.com/ggml-org/llama.cpp.git"

_llamacpp_cmake_flags() {
    case "${PLATFORM_TARGET:-cpu}" in
        nvidia) echo "-DGGML_CUDA=ON" ;;
        amd)    echo "-DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1030,gfx1100,gfx1101,gfx1102" ;;
        intel)  echo "-DGGML_VULKAN=ON" ;;
        *)      echo "-DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS" ;;
    esac
}

install_llama_cpp() {
    log_step "Installing llama.cpp (backend: ${PLATFORM_TARGET:-cpu})"

    require_cmd git "cloning llama.cpp"
    require_cmd cmake "building llama.cpp"
    require_cmd ninja "fast builds of llama.cpp" || true  # optional, cmake falls back to make

    ensure_dir "$(dirname "$AWB_LLAMACPP_SRC")"

    if [[ -d "$AWB_LLAMACPP_SRC/.git" ]]; then
        log_info "llama.cpp already cloned; pulling latest..."
        git -C "$AWB_LLAMACPP_SRC" pull --ff-only || log_warn "Could not fast-forward llama.cpp; keeping existing checkout."
    else
        git clone --depth 1 "$AWB_LLAMACPP_REPO" "$AWB_LLAMACPP_SRC" \
            || fail_loud "Failed to clone llama.cpp"
    fi

    local build_dir="${AWB_LLAMACPP_SRC}/build"
    local cmake_flags
    cmake_flags="$(_llamacpp_cmake_flags)"

    log_info "Configuring with: ${cmake_flags}"
    # shellcheck disable=SC2086
    cmake -S "$AWB_LLAMACPP_SRC" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        ${cmake_flags} \
        || fail_loud "llama.cpp cmake configuration failed"

    cmake --build "$build_dir" --config Release -j "$(nproc)" \
        || fail_loud "llama.cpp build failed"

    ensure_dir "${AI_HOME:-$HOME/ai}/bin"
    ln -sf "${build_dir}/bin/llama-server" "${AI_HOME:-$HOME/ai}/bin/llama-server"
    ln -sf "${build_dir}/bin/llama-cli" "${AI_HOME:-$HOME/ai}/bin/llama-cli"

    log_ok "llama.cpp built. Binaries linked into ${AI_HOME:-$HOME/ai}/bin/"

    install_llama_cpp_service
}

# Installs llama-server as a systemd --user service, matching Walter's
# production setup: no manual foreground process, restarts on failure.
install_llama_cpp_service() {
    if ! is_true "${INSTALL_LLAMACPP_SERVICE:-true}"; then
        return 0
    fi
    log_step "Installing llama-server systemd --user service"

    local unit_dir="$HOME/.config/systemd/user"
    ensure_dir "$unit_dir"

    # The model path is resolved here, at write time, and baked into the unit.
    # It used to be emitted as a literal \${AWB_DEFAULT_GGUF:-model.gguf} for
    # systemd to expand, which cannot work twice over: systemd supports only
    # $VAR / ${VAR}, not bash's ${VAR:-default}, and nothing puts the variable
    # in the unit's environment anyway. The result passed through verbatim,
    # llama-server exited with "model loading error", and Restart=on-failure
    # turned that into a crash loop the moment anyone enabled the service.
    local gguf="${AWB_DEFAULT_GGUF:-}"
    [[ -n "$gguf" ]] || fail_loud "AWB_DEFAULT_GGUF is not set in config.env, so the llama-server unit would have no model to load. Set it, or set INSTALL_LLAMACPP_SERVICE=false."
    local model_path="${AI_HOME:-$HOME/ai}/models/gguf/${gguf}"

    # Deliberately not checking that the file exists: section_runtimes runs
    # before section_models, so on a clean install the model is downloaded
    # after this unit is written.
    cat > "${unit_dir}/llama-server.service" <<EOF
[Unit]
Description=llama.cpp inference server (AI-Workbench)
After=network.target

[Service]
ExecStart=${AI_HOME:-$HOME/ai}/bin/llama-server \\
    --model ${model_path} \\
    --host 127.0.0.1 --port 8080 \\
    --ctx-size 4096
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload || log_warn "Could not reload systemd --user daemon."
    log_ok "systemd unit written to ${unit_dir}/llama-server.service (enable with: systemctl --user enable --now llama-server)"
}

update_llama_cpp() {
    log_step "Updating llama.cpp"
    [[ -d "$AWB_LLAMACPP_SRC" ]] || fail_loud "llama.cpp not installed yet; run install first."
    git -C "$AWB_LLAMACPP_SRC" pull --ff-only || fail_loud "Could not update llama.cpp"
    install_llama_cpp
}

remove_llama_cpp() {
    log_step "Removing llama.cpp"
    rm -rf "$AWB_LLAMACPP_SRC"
    rm -f "${AI_HOME:-$HOME/ai}/bin/llama-server" "${AI_HOME:-$HOME/ai}/bin/llama-cli"
    log_ok "llama.cpp removed."
}
