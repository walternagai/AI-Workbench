#!/usr/bin/env bats
# Unit tests for the Vulkan/OpenCL detection fallbacks in detect.sh.
#
# The regression this guards: on a machine with the NVIDIA driver installed but
# vulkan-tools/clinfo not yet installed, detect_vulkan/detect_opencl used to
# report "false" — a false negative that doctor.sh then surfaced as a hard
# failure on a healthy machine. The ICD fallback must report "icd-only" (and
# HAS_*="true") whenever a vendor ICD is on disk, and "none" only when neither
# a tool result nor an ICD exists. Run with:
#   bats tests/bats/detect_accel.bats

setup() {
    export AWB_ROOT
    AWB_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    # Stub the diagnostic tools; each test writes STUB_TOOL_OUT.
    STUB_BIN="$(mktemp -d)"
    export STUB_BIN
    export STUB_TOOL_OUT="${STUB_BIN}/tool.out"
    cat >"${STUB_BIN}/vulkaninfo" <<'EOF'
#!/usr/bin/env bash
cat "${STUB_TOOL_OUT}"
EOF
    cat >"${STUB_BIN}/clinfo" <<'EOF'
#!/usr/bin/env bash
cat "${STUB_TOOL_OUT}"
EOF
    chmod +x "${STUB_BIN}/vulkaninfo" "${STUB_BIN}/clinfo"
    export PATH="${STUB_BIN}:${PATH}"

    # Point the ICD lookups at a sandbox instead of the real system dirs.
    export VULKAN_ICD_DIRS="${STUB_BIN}/vulkan-icd.d"
    export OPENCL_ICD_DIR="${STUB_BIN}/opencl-icd.d"
    export ICD_LIB_DIR="${STUB_BIN}/lib"
    mkdir -p "$VULKAN_ICD_DIRS" "$OPENCL_ICD_DIR" "$ICD_LIB_DIR"

    source "${AWB_ROOT}/detect.sh"
}

teardown() {
    rm -rf "$STUB_BIN"
}

# --- Vulkan ----------------------------------------------------------------

@test "detect_vulkan: functional when vulkaninfo lists a device" {
    echo 'deviceName = NVIDIA GeForce RTX 4070 Ti SUPER' >"$STUB_TOOL_OUT"

    detect_vulkan

    [ "$HAS_VULKAN" = "true" ]
    [ "$VULKAN_STATE" = "functional" ]
    [ "$VULKAN_DEVICE" = "NVIDIA GeForce RTX 4070 Ti SUPER" ]
}

@test "detect_vulkan: icd-only when vulkaninfo is missing but an NVIDIA ICD exists" {
    : >"$STUB_TOOL_OUT"
    rm -f "${STUB_BIN}/vulkaninfo"
    cat >"$VULKAN_ICD_DIRS/nvidia_icd.json" <<'EOF'
{"ICD": {"library_path": "libGLX_nvidia.so.0", "api_version": "1.4.312"}}
EOF
    # The ICD's library_path is relative; the fallback resolves it under
    # ICD_LIB_DIR, so stub that resolution with a real file.
    touch "${ICD_LIB_DIR}/libGLX_nvidia.so.0"

    detect_vulkan

    [ "$HAS_VULKAN" = "true" ]
    [ "$VULKAN_STATE" = "icd-only" ]
}

@test "detect_vulkan: none when neither tool nor ICD exists" {
    : >"$STUB_TOOL_OUT"
    rm -f "${STUB_BIN}/vulkaninfo"

    detect_vulkan

    [ "$HAS_VULKAN" = "false" ]
    [ "$VULKAN_STATE" = "none" ]
}

# --- OpenCL ----------------------------------------------------------------

@test "detect_opencl: functional when clinfo lists a device" {
    echo 'Platform #0: NVIDIA CUDA
  Device #0: NVIDIA GeForce RTX 4070 Ti SUPER' >"$STUB_TOOL_OUT"

    detect_opencl

    [ "$HAS_OPENCL" = "true" ]
    [ "$OPENCL_STATE" = "functional" ]
    [ "$OPENCL_DEVICE" = "NVIDIA GeForce RTX 4070 Ti SUPER" ]
}

@test "detect_opencl: icd-only when clinfo is missing but an NVIDIA ICD exists" {
    : >"$STUB_TOOL_OUT"
    rm -f "${STUB_BIN}/clinfo"
    cat >"$OPENCL_ICD_DIR/nvidia.icd" <<'EOF'
libnvidia-opencl.so.1
EOF
    touch "${ICD_LIB_DIR}/libnvidia-opencl.so.1"

    detect_opencl

    [ "$HAS_OPENCL" = "true" ]
    [ "$OPENCL_STATE" = "icd-only" ]
}

@test "detect_opencl: none when neither tool nor ICD exists" {
    : >"$STUB_TOOL_OUT"
    rm -f "${STUB_BIN}/clinfo"

    detect_opencl

    [ "$HAS_OPENCL" = "false" ]
    [ "$OPENCL_STATE" = "none" ]
}
