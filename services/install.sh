#!/usr/bin/env bash
# services/install.sh — brings up the optional Docker Compose services
# (Open WebUI, Qdrant, ChromaDB, Postgres), gated individually by config.env
# flags so a workstation install doesn't drag in server-oriented containers.
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

# _warn_default_secret <config.env var name> <value> — deliberate log_warn +
# continue (not fail_loud): config.env ships "change-me" placeholders so a
# first install works out of the box, but they must not stay in place once
# a service is actually exposed. See CLAUDE.md's fail-loud principle for why
# this is one of the documented log_warn exceptions.
_warn_default_secret() {
    local var_name="$1" value="$2"
    if [[ "$value" == "change-me" ]]; then
        log_warn "${var_name} is still the default 'change-me' in config.env. Change it before exposing this service beyond localhost."
    fi
}

install_services() {
    if ! is_true "${INSTALL_DOCKER:-true}"; then
        log_info "INSTALL_DOCKER is disabled in config.env; skipping all services."
        return 0
    fi
    require_cmd docker "running AI-Workbench services"

    is_true "${INSTALL_OPENWEBUI:-true}" && {
        _warn_default_secret "WEBUI_SECRET_KEY" "${WEBUI_SECRET_KEY:-}"
        _compose_up openwebui
    }
    is_true "${INSTALL_QDRANT:-false}"    && _compose_up qdrant
    is_true "${INSTALL_CHROMADB:-false}"  && _compose_up chromadb
    is_true "${INSTALL_POSTGRES:-false}"  && {
        _warn_default_secret "POSTGRES_PASSWORD" "${POSTGRES_PASSWORD:-}"
        _compose_up postgres
    }

    log_ok "Services step complete."
}
