#!/usr/bin/env bash
# python/create_envs.sh — creates the standardized Python environments under
# ~/venvs/, each scoped to one concern so dependency conflicts (e.g. a
# vision library pinning a different numpy than RAG) stay contained.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

AWB_VENV_ROOT="$HOME/venvs"

_create_venv() {
    local name="$1"; shift
    local packages=("$@")
    local path="${AWB_VENV_ROOT}/${name}"

    if [[ -d "$path" ]]; then
        log_info "venv '${name}' already exists; updating packages."
    else
        log_info "Creating venv '${name}'..."
        python3 -m venv "$path" || fail_loud "Failed to create venv: $name"
    fi

    # shellcheck disable=SC1091
    source "$path/bin/activate"
    pip install --upgrade pip wheel --quiet
    if (( ${#packages[@]} > 0 )); then
        # Always install/upgrade, even for existing venvs, so package list
        # changes are picked up on re-runs (idempotent with updates).
        pip install --upgrade "${packages[@]}" || fail_loud "Failed to install packages into venv '${name}'"
    fi
    deactivate

    log_ok "venv '${name}' ready at ${path}"
}

create_all_envs() {
    log_step "Creating Python environments"

    require_cmd python3 "Python 3 runtime"
    python3 -m venv --help >/dev/null 2>&1 || fail_loud "python3-venv module missing (sudo apt-get install python3-venv)"

    ensure_dir "$AWB_VENV_ROOT"

    # core — general-purpose scripting, FastAPI services, model management
    _create_venv "core" \
        requests pyyaml python-dotenv fastapi "uvicorn[standard]" huggingface_hub

    # openvino — Intel-optimized inference (only meaningfully used on Intel,
    # but created uniformly so cross-platform scripts don't special-case it)
    _create_venv "openvino" \
        requests pyyaml

    # rag — retrieval-augmented generation: embeddings, vector stores
    _create_venv "rag" \
        sentence-transformers qdrant-client chromadb langchain

    # vision — computer vision / image models
    _create_venv "vision" \
        pillow opencv-python-headless numpy

    # speech — STT/TTS (Whisper and friends)
    _create_venv "speech" \
        openai-whisper soundfile

    log_ok "All Python environments created under ${AWB_VENV_ROOT}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AWB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck source=lib/colors.sh
    source "${AWB_ROOT}/lib/colors.sh"
    # shellcheck source=lib/logger.sh
    source "${AWB_ROOT}/lib/logger.sh"
    # shellcheck source=lib/utils.sh
    source "${AWB_ROOT}/lib/utils.sh"
    create_all_envs
fi
