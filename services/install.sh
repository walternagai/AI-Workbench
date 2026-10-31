#!/usr/bin/env bash
# services/install.sh — brings up the optional Docker Compose services
# (Open WebUI, Qdrant, ChromaDB, Postgres, ComfyUI). Every service is off by
# default in config.env and is turned on in config.local.env, so the tracked
# defaults never depend on one machine's network, GPU or images.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

_compose_up() {
    local name="$1" dir="${AWB_ROOT}/services/${1}"
    log_step "Starting service: ${name}"
    require_cmd docker "running ${name}"
    ( cd "$dir" && docker compose --env-file "${AWB_ROOT}/config.env" up -d ) \
        || fail_loud "Failed to start service: ${name}"
    log_ok "${name} is up."
}

# _require_real_secret <config var name> <value> — config.env is tracked and
# public, so it ships "change-me" placeholders instead of real secrets. Real
# values live in the gitignored config.local.env; starting a service on the
# placeholder would run it with a publicly known credential, so abort.
# Deliberately NOT a skip: a service with a public password is never started.
_require_real_secret() {
    local var_name="$1" value="$2"
    if [[ "$value" == "change-me" ]]; then
        fail_loud "${var_name} is still the 'change-me' placeholder. Set a real value in config.local.env (see config.local.env.example)."
    fi
}

# Prerequisites outside this repository (the hub's Docker network, an image
# built locally) make a service SKIP with a warning instead of aborting the
# whole services section. That is a documented exception to fail-loud
# (docs/PRINCIPLES.md §1): the skip is logged, and it ends up in the report.
# Configuration the user explicitly asked for (INSTALL_COMFYUI=true with no GPU)
# still aborts, and so do secrets (_require_real_secret).

_chromadb_ready() {
    local net="${CHROMADB_EXTERNAL_NETWORK:-}"
    if [[ -z "$net" ]]; then
        log_warn "ChromaDB pulado: CHROMADB_EXTERNAL_NETWORK está vazio (rede Docker do hub). Defina em config.local.env ou desligue INSTALL_CHROMADB."
        return 1
    fi
    if ! docker network inspect "$net" >/dev/null 2>&1; then
        log_warn "ChromaDB pulado: a rede Docker '${net}' não existe. Suba a stack do hub antes, ou desligue INSTALL_CHROMADB."
        return 1
    fi
    return 0
}

_comfyui_ready() {
    if [[ -z "${COMFYUI_GPU_UUID:-}" ]]; then
        fail_loud "INSTALL_COMFYUI=true, mas COMFYUI_GPU_UUID está vazio. Defina a GPU em config.local.env (nvidia-smi -L)."
    fi
    local image="${COMFYUI_IMAGE:-seiryu/comfyui:0.43.2-cu128-restore}"
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        log_warn "ComfyUI pulado: a imagem '${image}' não existe localmente. Construa com: docker build --target comfyui-0.43 -t ${image} services/comfyui/"
        return 1
    fi
    return 0
}

install_services() {
    if ! is_true "${INSTALL_DOCKER:-true}"; then
        log_info "INSTALL_DOCKER is disabled in config.env; skipping all services."
        return 0
    fi
    require_cmd docker "running AI-Workbench services"

    is_true "${INSTALL_OPENWEBUI:-false}" && {
        _require_real_secret "WEBUI_SECRET_KEY" "${WEBUI_SECRET_KEY:-}"
        _compose_up openwebui
    }
    is_true "${INSTALL_QDRANT:-false}"   && _compose_up qdrant
    is_true "${INSTALL_CHROMADB:-false}" && _chromadb_ready && _compose_up chromadb
    is_true "${INSTALL_POSTGRES:-false}" && {
        _require_real_secret "POSTGRES_PASSWORD" "${POSTGRES_PASSWORD:-}"
        _compose_up postgres
    }
    is_true "${INSTALL_COMFYUI:-false}"  && _comfyui_ready && _compose_up comfyui

    log_ok "Services step complete."
}
