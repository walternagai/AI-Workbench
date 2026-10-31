#!/usr/bin/env bats
# services/install.sh — the service gating after the A2 decision: every
# service is off by default, prerequisites outside the repo skip with a warning,
# and secrets or explicit misconfiguration still abort. Hermetic: docker is a
# stub that records its calls, so nothing is pulled or started.

setup() {
    REPO="${BATS_TEST_DIRNAME}/../.."
    export AWB_ROOT
    AWB_ROOT="$(mktemp -d)"
    mkdir -p "${AWB_ROOT}/bin"
    ln -s "${REPO}/services" "${AWB_ROOT}/services"
    PATH="${AWB_ROOT}/bin:${PATH}"

    # docker stub: logs every call. `network inspect` and `image inspect`
    # succeed only when the test says the network/image exists.
    cat > "${AWB_ROOT}/bin/docker" <<'EOF'
#!/bin/sh
echo "$*" >> "${AWB_ROOT}/docker.log"
case "$1" in
  network) [ "${AWB_TEST_NET_EXISTS:-0}" = 1 ] ;;
  image)   [ "${AWB_TEST_IMAGE_EXISTS:-0}" = 1 ] ;;
  *)       exit 0 ;;
esac
EOF
    chmod +x "${AWB_ROOT}/bin/docker"

    source "${REPO}/lib/colors.sh"
    source "${REPO}/lib/logger.sh"
    source "${REPO}/lib/utils.sh"
    source "${REPO}/services/install.sh"

    # Clean slate: no service flag, no personal value, no stub answers.
    unset INSTALL_OPENWEBUI INSTALL_QDRANT INSTALL_CHROMADB INSTALL_POSTGRES INSTALL_COMFYUI
    unset WEBUI_SECRET_KEY POSTGRES_PASSWORD CHROMADB_EXTERNAL_NETWORK COMFYUI_GPU_UUID COMFYUI_IMAGE
    export AWB_TEST_NET_EXISTS=0 AWB_TEST_IMAGE_EXISTS=0
    export INSTALL_DOCKER=true
}

teardown() {
    rm -rf "$AWB_ROOT"
}

# Number of `docker compose` calls recorded by the stub. No log file means no
# calls at all, so print 0 rather than nothing (an empty string breaks [ -eq ]).
_compose_calls() {
    if [[ -f "${AWB_ROOT}/docker.log" ]]; then
        grep -c '^compose' "${AWB_ROOT}/docker.log" || true
    else
        echo 0
    fi
}

# --- defaults -------------------------------------------------------------

@test "config.env: every service flag defaults to false" {
    [ "$(grep -cE '^INSTALL_(OPENWEBUI|QDRANT|CHROMADB|POSTGRES|COMFYUI)=false$' "${REPO}/config.env")" -eq 5 ]
}

@test "install_services: with no service flag set, nothing is started" {
    run install_services
    [ "$status" -eq 0 ]
    [ "$(_compose_calls)" -eq 0 ]
}

# --- ChromaDB: depends on the hub's external network -----------------------

@test "ChromaDB: enabled with no network configured is skipped with a warning" {
    export INSTALL_CHROMADB=true CHROMADB_EXTERNAL_NETWORK=""
    run install_services
    [ "$status" -eq 0 ]
    [[ "$output" == *"ChromaDB pulado"* ]]
    [ "$(_compose_calls)" -eq 0 ]
}

@test "ChromaDB: enabled but the hub network is missing is skipped with a warning" {
    export INSTALL_CHROMADB=true CHROMADB_EXTERNAL_NETWORK=seiryu_seiryu-network
    export AWB_TEST_NET_EXISTS=0
    run install_services
    [ "$status" -eq 0 ]
    [[ "$output" == *"não existe"* ]]
    [ "$(_compose_calls)" -eq 0 ]
}

@test "ChromaDB: enabled and the hub network exists, so it is started" {
    export INSTALL_CHROMADB=true CHROMADB_EXTERNAL_NETWORK=seiryu_seiryu-network
    export AWB_TEST_NET_EXISTS=1
    run install_services
    [ "$status" -eq 0 ]
    [ "$(_compose_calls)" -ge 1 ]
}

# --- secrets: never skipped, always abort ----------------------------------

@test "Postgres: the change-me placeholder aborts before any compose call" {
    export INSTALL_POSTGRES=true POSTGRES_PASSWORD=change-me
    run install_services
    [ "$status" -ne 0 ]
    [[ "$output" == *"change-me"* ]]
    [ "$(_compose_calls)" -eq 0 ]
}

# --- ComfyUI: GPU is explicit config, image is a local prerequisite --------

@test "ComfyUI: enabled with no GPU UUID aborts with a message that names the variable" {
    export INSTALL_COMFYUI=true COMFYUI_GPU_UUID=""
    run install_services
    [ "$status" -ne 0 ]
    [[ "$output" == *"COMFYUI_GPU_UUID"* ]]
    [ "$(_compose_calls)" -eq 0 ]
}

@test "ComfyUI: enabled with the GPU set but the local image missing is skipped with a warning" {
    export INSTALL_COMFYUI=true COMFYUI_GPU_UUID=GPU-test AWB_TEST_IMAGE_EXISTS=0
    run install_services
    [ "$status" -eq 0 ]
    [[ "$output" == *"ComfyUI pulado"* ]]
    [ "$(_compose_calls)" -eq 0 ]
}

@test "ComfyUI: enabled with the GPU set and the image present, so it is started" {
    export INSTALL_COMFYUI=true COMFYUI_GPU_UUID=GPU-test AWB_TEST_IMAGE_EXISTS=1
    run install_services
    [ "$status" -eq 0 ]
    [ "$(_compose_calls)" -ge 1 ]
}
