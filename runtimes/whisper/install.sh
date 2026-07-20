#!/usr/bin/env bash
# runtimes/whisper/install.sh — whisper.cpp for fast local STT, compiled
# with the same backend logic as llama.cpp (they share ggml).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

AWB_WHISPER_SRC="${AI_HOME:-$HOME/ai}/src/whisper.cpp"

install_whisper_cpp() {
    log_step "Installing whisper.cpp"

    require_cmd git "cloning whisper.cpp"
    require_cmd cmake "building whisper.cpp"

    if [[ -d "$AWB_WHISPER_SRC/.git" ]]; then
        git -C "$AWB_WHISPER_SRC" pull --ff-only || log_warn "Could not update whisper.cpp; keeping existing checkout."
    else
        git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$AWB_WHISPER_SRC" \
            || fail_loud "Failed to clone whisper.cpp"
    fi

    local cmake_flags=""
    case "${PLATFORM_TARGET:-cpu}" in
        nvidia) cmake_flags="-DGGML_CUDA=ON" ;;
        intel)  cmake_flags="-DGGML_VULKAN=ON" ;;
    esac

    local build_dir="${AWB_WHISPER_SRC}/build"
    # shellcheck disable=SC2086
    cmake -S "$AWB_WHISPER_SRC" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release ${cmake_flags} \
        || fail_loud "whisper.cpp cmake configuration failed"
    cmake --build "$build_dir" --config Release -j "$(nproc)" \
        || fail_loud "whisper.cpp build failed"

    ensure_dir "${AI_HOME:-$HOME/ai}/bin"
    ln -sf "${build_dir}/bin/whisper-cli" "${AI_HOME:-$HOME/ai}/bin/whisper-cli"

    log_ok "whisper.cpp built and linked into ${AI_HOME:-$HOME/ai}/bin/"
}
