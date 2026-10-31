#!/usr/bin/env bats
# B8: the Ollama installer runs a remote script without an integrity check.
# That is an accepted trade-off, so it must be stated where a reader will find
# it: in the runtime's own comment (so nobody reads the shebang check as
# verification) and in README's security section. Documentation-only guard.

setup() {
    REPO="${BATS_TEST_DIRNAME}/../.."
}

@test "ollama runtime: the comment says the shebang check is not an integrity check" {
    grep -q "NOT an integrity check" "${REPO}/runtimes/ollama/install.sh"
}

@test "ollama runtime: the old 'avoids curl|sh' claim is gone" {
    ! grep -q "avoids the" "${REPO}/runtimes/ollama/install.sh"
}

@test "README: documents the Ollama installer trade-off in the security section" {
    grep -q "^## Segurança e trade-offs" "${REPO}/README.md"
    grep -q "Instalador do Ollama sem verificação de integridade" "${REPO}/README.md"
}
