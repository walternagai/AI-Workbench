#!/usr/bin/env bats
# M4: `grep -q` inside a pipeline under `pipefail` gives a false negative. grep
# exits on the first match, the producer then dies of SIGPIPE, and the pipeline
# reports failure even though the pattern was present. Shell scripts here run
# with pipefail, so the guards that depend on this read "absent" for a package
# that is installed. Hermetic: dpkg, apt-cache and sudo are stubbed, and the
# stub listings are large enough to fill the pipe buffer.

setup() {
    export AWB_ROOT HOME
    AWB_ROOT="$(mktemp -d)"
    HOME="${AWB_ROOT}/home"
    mkdir -p "$HOME" "${AWB_ROOT}/bin"
    PATH="${AWB_ROOT}/bin:${PATH}"
    export AWB_APT_UPDATED=1
    source "${BATS_TEST_DIRNAME}/../../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/logger.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/utils.sh"

    # sudo: record the call; apt-get install is then a no-op success.
    cat > "${AWB_ROOT}/bin/sudo" <<'EOF'
#!/bin/sh
echo "$*" >> "${AWB_ROOT}/sudo.log"
exit 0
EOF
    chmod +x "${AWB_ROOT}/bin/sudo"
}

teardown() {
    rm -rf "$AWB_ROOT"
}

# A dpkg -l listing of ~30000 lines (~2 MB, far past the 64 KB pipe buffer),
# with `ii  nvidia-cudnn` placed in the middle, so grep matches early.
# `exec awk` matters: the stub must BE the producer. If the shell stayed in
# charge, the SIGPIPE would kill only the awk child, and the stub's own exit
# status would hide it. Real dpkg dies of SIGPIPE itself, so this matches it.
_stub_dpkg_big_listing() {
    cat > "${AWB_ROOT}/bin/dpkg" <<'EOF'
#!/bin/sh
if [ "$1" = "-l" ]; then
    exec awk 'BEGIN { for (i = 1; i <= 30000; i++) {
        if (i == 10000) print "ii  nvidia-cudnn 9.1.0-1 amd64 cuDNN 9 metapackage";
        printf "ii  pkg%05d 1.0 amd64 padding padding padding padding padding\n", i } }'
fi
exit 1
EOF
    chmod +x "${AWB_ROOT}/bin/dpkg"
}

@test "cuDNN guard: an installed package in a long dpkg listing is seen (M4)" {
    _stub_dpkg_big_listing
    source "${BATS_TEST_DIRNAME}/../../platforms/nvidia/cudnn.sh"
    # The repo setup is not under test here; stub it so no network is used.
    _ensure_nvidia_cuda_apt_repo() { return 0; }

    run install_nvidia_cudnn
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    # No apt install must have been attempted for cuDNN.
    [ ! -f "${AWB_ROOT}/sudo.log" ] || ! grep -q 'cudnn' "${AWB_ROOT}/sudo.log"
}

@test "oneapi guard: a configured apt repo with a long search result is detected (M4)" {
    cat > "${AWB_ROOT}/bin/apt-cache" <<'EOF'
#!/bin/sh
if [ "$1" = "search" ]; then
    exec awk 'BEGIN { for (i = 1; i <= 30000; i++) print "intel-oneapi-runtime-opencl-" i " - runtime" }'
fi
exit 0
EOF
    chmod +x "${AWB_ROOT}/bin/apt-cache"
    source "${BATS_TEST_DIRNAME}/../../platforms/intel/oneapi.sh"

    run install_intel_oneapi_runtime
    [ "$status" -eq 0 ]
    [[ "$output" != *"not configured"* ]]
    grep -q 'intel-oneapi-runtime-opencl' "${AWB_ROOT}/sudo.log"
}
