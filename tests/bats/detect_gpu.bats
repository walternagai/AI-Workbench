#!/usr/bin/env bats
# Unit tests for detect_gpu() in detect.sh, driven by a stubbed `lspci` so no
# real hardware is required. Run with:
#   bats tests/bats/detect_gpu.bats

setup() {
    export AWB_ROOT
    AWB_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    # Stub lspci ahead of the real one; each test writes STUB_LSPCI_OUT.
    STUB_BIN="$(mktemp -d)"
    export STUB_BIN
    export STUB_LSPCI_OUT="${STUB_BIN}/lspci.out"
    cat >"${STUB_BIN}/lspci" <<'EOF'
#!/usr/bin/env bash
cat "${STUB_LSPCI_OUT}"
EOF
    chmod +x "${STUB_BIN}/lspci"
    export PATH="${STUB_BIN}:${PATH}"

    source "${AWB_ROOT}/detect.sh"
}

teardown() {
    rm -rf "$STUB_BIN"
}

# --- vendor classification ---------------------------------------------------

@test "detect_gpu: Intel iGPU is not misread as AMD" {
    # Regression: 'ati' as a substring matched both "VGA compatible controller"
    # and "Intel Corporation", classifying every non-NVIDIA GPU as AMD.
    echo '00:02.0 "VGA compatible controller" "Intel Corporation" "Meteor Lake-P [Intel Arc Graphics]" -r08 -p00 "Samsung Electronics Co Ltd" "Meteor Lake-P [Intel Arc Graphics]"' >"$STUB_LSPCI_OUT"

    detect_gpu

    [ "$GPU_VENDOR" = "Intel" ]
    [ "$HAS_AMD_GPU" = "false" ]
    [ "$HAS_INTEL_ARC" = "true" ]
    [ "$GPU_MODEL" = "Meteor Lake-P [Intel Arc Graphics]" ]
}

@test "detect_gpu: AMD discrete GPU is detected" {
    echo '03:00.0 "VGA compatible controller" "Advanced Micro Devices, Inc. [AMD/ATI]" "Navi 31 [Radeon RX 7900 XTX]" -rc8 -p00 "Sapphire Technology Limited" "Navi 31"' >"$STUB_LSPCI_OUT"

    detect_gpu

    [ "$GPU_VENDOR" = "AMD" ]
    [ "$HAS_AMD_GPU" = "true" ]
    [ "$HAS_NVIDIA_GPU" = "false" ]
}

@test "detect_gpu: legacy ATI vendor string is detected as AMD" {
    echo '01:00.0 "VGA compatible controller" "ATI Technologies Inc" "RV770 [Radeon HD 4850]" -r00 -p00 "Dell" "RV770"' >"$STUB_LSPCI_OUT"

    detect_gpu

    [ "$GPU_VENDOR" = "AMD" ]
    [ "$HAS_AMD_GPU" = "true" ]
}

@test "detect_gpu: NVIDIA discrete GPU is detected" {
    echo '01:00.0 "VGA compatible controller" "NVIDIA Corporation" "AD104 [GeForce RTX 4070]" -ra1 -p00 "ASUSTeK" "AD104"' >"$STUB_LSPCI_OUT"

    detect_gpu

    [ "$GPU_VENDOR" = "NVIDIA" ]
    [ "$HAS_NVIDIA_GPU" = "true" ]
    [ "$HAS_AMD_GPU" = "false" ]
}

@test "detect_gpu: non-Arc Intel iGPU does not set HAS_INTEL_ARC" {
    echo '00:02.0 "VGA compatible controller" "Intel Corporation" "HD Graphics 620" -r02 -p00 "Lenovo" "HD Graphics 620"' >"$STUB_LSPCI_OUT"

    detect_gpu

    [ "$GPU_VENDOR" = "Intel" ]
    [ "$HAS_INTEL_ARC" = "false" ]
    [ "$HAS_AMD_GPU" = "false" ]
}

@test "detect_gpu: no graphics controller leaves vendor unset" {
    : >"$STUB_LSPCI_OUT"

    detect_gpu

    [ "$GPU_VENDOR" = "none" ]
    [ "$HAS_AMD_GPU" = "false" ]
    [ "$HAS_NVIDIA_GPU" = "false" ]
}
