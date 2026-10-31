#!/usr/bin/env bats
# Intel NPU userspace dependencies: libze1 (Level Zero loader) must be ensured
# even when the NPU driver is already installed. Hermetic — dpkg and sudo are
# stubbed, so no package manager, network or root is needed.

setup() {
    export AWB_ROOT HOME
    AWB_ROOT="$(mktemp -d)"
    HOME="${AWB_ROOT}/home"
    mkdir -p "$HOME" "${AWB_ROOT}/bin"
    PATH="${AWB_ROOT}/bin:${PATH}"
    export AWB_APT_UPDATED=1          # skip the real `apt-get update`
    export AWB_TEST_INSTALLED=""      # space-separated packages dpkg "has"
    export AWB_TEST_SUDO_RC=0         # exit status of the sudo stub
    source "${BATS_TEST_DIRNAME}/../../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/logger.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/utils.sh"
    source "${BATS_TEST_DIRNAME}/../../platforms/intel/npu.sh"

    # dpkg -s <pkg>: succeeds only for packages listed in AWB_TEST_INSTALLED.
    cat > "${AWB_ROOT}/bin/dpkg" <<'EOF'
#!/bin/sh
[ "$1" = "-s" ] || exit 1
for p in $AWB_TEST_INSTALLED; do [ "$p" = "$2" ] && exit 0; done
exit 1
EOF
    # sudo: record the call, then exit with the configured status.
    cat > "${AWB_ROOT}/bin/sudo" <<'EOF'
#!/bin/sh
echo "$*" >> "${AWB_ROOT}/sudo.log"
exit "${AWB_TEST_SUDO_RC:-0}"
EOF
    chmod +x "${AWB_ROOT}/bin/dpkg" "${AWB_ROOT}/bin/sudo"
}

teardown() {
    rm -rf "$AWB_ROOT"
}

@test "_npu_ensure_level_zero_loader: skips apt when libze1 is already installed" {
    export AWB_TEST_INSTALLED="libze1"
    run _npu_ensure_level_zero_loader
    [ "$status" -eq 0 ]
    [ ! -f "${AWB_ROOT}/sudo.log" ]
}

@test "_npu_ensure_level_zero_loader: installs libze1 when missing" {
    run _npu_ensure_level_zero_loader
    [ "$status" -eq 0 ]
    grep -qx 'apt-get install -y libze1' "${AWB_ROOT}/sudo.log"
}

@test "_npu_ensure_level_zero_loader: a failed install is non-fatal and warns" {
    export AWB_TEST_SUDO_RC=1
    run _npu_ensure_level_zero_loader
    [ "$status" -eq 0 ]
    [[ "$output" == *"libze1"* ]]
}

@test "install_intel_npu: ensures libze1 even when the driver is already installed" {
    export HAS_INTEL_NPU=true
    export AWB_TEST_INSTALLED="intel-driver-compiler-npu"
    run install_intel_npu
    [ "$status" -eq 0 ]
    grep -qx 'apt-get install -y libze1' "${AWB_ROOT}/sudo.log"
    [[ "$output" == *"already installed"* ]]
}

@test "install_intel_npu: touches nothing when no NPU is present" {
    export HAS_INTEL_NPU=false
    run install_intel_npu
    [ "$status" -eq 0 ]
    [ ! -f "${AWB_ROOT}/sudo.log" ]
}
