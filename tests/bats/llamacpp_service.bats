#!/usr/bin/env bats
# Unit tests for install_llama_cpp_service() in runtimes/llama.cpp/install.sh.
#
# This function generates a systemd unit, and generated config is invisible to
# every other check in this repo: shellcheck lints the generator rather than
# its output, `systemd-analyze verify` accepted the broken unit without
# complaint, and nothing else reads the file. The unit shipped emitting a
# literal ${AWB_DEFAULT_GGUF:-model.gguf} for systemd to expand — which systemd
# cannot do, since it supports only $VAR and ${VAR}, not bash's :- default
# form. llama-server got a nonexistent path, exited 1, and Restart=on-failure
# crash-looped it. It surfaced only when someone actually enabled the service.
#
# These run the real generator against a throwaway HOME with systemctl stubbed,
# then assert on the bytes it wrote. Run with:
#   bats tests/bats/llamacpp_service.bats

setup() {
    export AWB_ROOT
    AWB_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    # Hermetic: the generator writes into $HOME/.config/systemd/user and shells
    # out to systemctl. Neither may touch the real machine.
    export HOME="${BATS_TEST_TMPDIR}/home"
    export AI_HOME="${HOME}/ai"
    mkdir -p "$HOME"

    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$STUB_BIN"
    cat >"${STUB_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "${STUB_SYSTEMCTL_LOG}"
EOF
    chmod +x "${STUB_BIN}/systemctl"
    export STUB_SYSTEMCTL_LOG="${BATS_TEST_TMPDIR}/systemctl.log"
    : > "$STUB_SYSTEMCTL_LOG"
    export PATH="${STUB_BIN}:${PATH}"

    export INSTALL_LLAMACPP_SERVICE=true
    export AWB_DEFAULT_GGUF="test-model-Q8_0.gguf"

    source "${AWB_ROOT}/lib/colors.sh"
    source "${AWB_ROOT}/lib/logger.sh"
    source "${AWB_ROOT}/lib/utils.sh"
    source "${AWB_ROOT}/runtimes/llama.cpp/install.sh"

    UNIT="${HOME}/.config/systemd/user/llama-server.service"
    export UNIT
}

# --- the regression -------------------------------------------------------

@test "the generated unit contains no unexpanded shell variable" {
    # The bug in one assertion: systemd would have received these verbatim.
    install_llama_cpp_service
    run grep -n '\$' "$UNIT"
    [ "$status" -ne 0 ] || { echo "unexpanded '\$' left in the unit:"; echo "$output"; return 1; }
}

@test "the generated unit contains no bash-style default expansion" {
    # ${VAR:-default} is valid bash and meaningless to systemd. Called out
    # separately from the check above so a failure names the actual cause.
    install_llama_cpp_service
    run grep -n ':-' "$UNIT"
    [ "$status" -ne 0 ] || { echo "bash ':-' default left in the unit:"; echo "$output"; return 1; }
}

@test "ExecStart names the configured model file" {
    install_llama_cpp_service
    grep -q -- "--model ${AI_HOME}/models/gguf/test-model-Q8_0.gguf" "$UNIT" \
        || { echo "ExecStart does not reference the configured model:"; grep -- --model "$UNIT"; return 1; }
}

@test "every path in ExecStart is absolute" {
    # systemd requires an absolute ExecStart and has no cwd to resolve against.
    install_llama_cpp_service
    line="$(grep '^ExecStart=' "$UNIT")"
    [[ "$line" == "ExecStart=/"* ]] || { echo "ExecStart is not absolute: ${line}"; return 1; }
}

# --- configuration --------------------------------------------------------

@test "fails loud when AWB_DEFAULT_GGUF is unset rather than writing a broken unit" {
    unset AWB_DEFAULT_GGUF
    run install_llama_cpp_service
    [ "$status" -ne 0 ]
    [[ "$output" == *"AWB_DEFAULT_GGUF"* ]]
    [ ! -f "$UNIT" ] || { echo "a unit was written despite the failure"; return 1; }
}

@test "writes nothing when INSTALL_LLAMACPP_SERVICE is disabled" {
    export INSTALL_LLAMACPP_SERVICE=false
    run install_llama_cpp_service
    [ "$status" -eq 0 ]
    [ ! -f "$UNIT" ] || { echo "unit written despite INSTALL_LLAMACPP_SERVICE=false"; return 1; }
}

@test "honours AI_HOME instead of hardcoding ~/ai" {
    export AI_HOME="${BATS_TEST_TMPDIR}/elsewhere"
    install_llama_cpp_service
    grep -q "${BATS_TEST_TMPDIR}/elsewhere/bin/llama-server" "$UNIT" \
        || { echo "unit ignores AI_HOME:"; grep '^ExecStart=' "$UNIT"; return 1; }
}

@test "does not require the model file to exist yet" {
    # section_runtimes writes this unit before section_models downloads
    # anything, so a file-existence check here would break every clean install.
    [ ! -e "${AI_HOME}/models/gguf/test-model-Q8_0.gguf" ]
    run install_llama_cpp_service
    [ "$status" -eq 0 ]
}

# --- unit validity --------------------------------------------------------

@test "the unit has the sections and keys systemd needs to enable it" {
    install_llama_cpp_service
    for required in '[Unit]' '[Service]' '[Install]' 'ExecStart=' 'WantedBy='; do
        grep -qF "$required" "$UNIT" || { echo "unit is missing ${required}"; return 1; }
    done
}

@test "the unit is installed into the systemd --user directory" {
    install_llama_cpp_service
    [ -f "${HOME}/.config/systemd/user/llama-server.service" ]
}

@test "systemd is told to reload so the new unit is visible" {
    install_llama_cpp_service
    grep -q "daemon-reload" "$STUB_SYSTEMCTL_LOG" \
        || { echo "systemctl daemon-reload was never called"; return 1; }
}

@test "regenerating produces an identical unit" {
    install_llama_cpp_service
    first="$(cat "$UNIT")"
    install_llama_cpp_service
    [ "$first" = "$(cat "$UNIT")" ] || { echo "unit changed on a second run"; return 1; }
}
