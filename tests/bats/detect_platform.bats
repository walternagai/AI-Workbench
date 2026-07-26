#!/usr/bin/env bats
# Unit tests for resolve_platform_target() in detect.sh — the function that
# turns detection flags into the single PLATFORM_TARGET that install.sh
# branches on for the whole platform stack, and that doctor.sh uses to decide
# which acceleration checks even apply.
#
# The priority ladder (nvidia > amd > intel > cpu) is documented in CLAUDE.md
# and is load-bearing: the GPU misclassification that sent an Intel iGPU
# machine down the ROCm path did its damage through this function. Run with:
#   bats tests/bats/detect_platform.bats

setup() {
    export AWB_ROOT
    AWB_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${AWB_ROOT}/lib/colors.sh"
    source "${AWB_ROOT}/lib/logger.sh"
    source "${AWB_ROOT}/lib/utils.sh"
    source "${AWB_ROOT}/detect.sh"

    # Baseline: no GPU of any kind. Each test raises only what it means to.
    export HAS_NVIDIA_GPU=false HAS_AMD_GPU=false GPU_VENDOR=""
}

@test "resolve_platform_target: NVIDIA wins" {
    HAS_NVIDIA_GPU=true
    resolve_platform_target
    [ "$PLATFORM_TARGET" = "nvidia" ]
}

@test "resolve_platform_target: AMD wins when there is no NVIDIA" {
    HAS_AMD_GPU=true
    resolve_platform_target
    [ "$PLATFORM_TARGET" = "amd" ]
}

@test "resolve_platform_target: Intel wins when there is neither NVIDIA nor AMD" {
    GPU_VENDOR=Intel
    resolve_platform_target
    [ "$PLATFORM_TARGET" = "intel" ]
}

@test "resolve_platform_target: falls back to cpu with no GPU at all" {
    resolve_platform_target
    [ "$PLATFORM_TARGET" = "cpu" ]
}

@test "resolve_platform_target: NVIDIA outranks AMD in a mixed machine" {
    HAS_NVIDIA_GPU=true
    HAS_AMD_GPU=true
    resolve_platform_target
    [ "$PLATFORM_TARGET" = "nvidia" ]
}

@test "resolve_platform_target: a discrete AMD card outranks the Intel iGPU beside it" {
    # The common desktop case: an Intel CPU with integrated graphics plus a
    # discrete Radeon. The discrete card must win.
    HAS_AMD_GPU=true
    GPU_VENDOR=Intel
    resolve_platform_target
    [ "$PLATFORM_TARGET" = "amd" ]
}

@test "resolve_platform_target: NVIDIA outranks everything at once" {
    HAS_NVIDIA_GPU=true
    HAS_AMD_GPU=true
    GPU_VENDOR=Intel
    resolve_platform_target
    [ "$PLATFORM_TARGET" = "nvidia" ]
}

@test "resolve_platform_target: an unrecognised vendor falls back to cpu, not intel" {
    GPU_VENDOR="Matrox"
    resolve_platform_target
    [ "$PLATFORM_TARGET" = "cpu" ]
}

@test "resolve_platform_target: GPU_VENDOR is matched exactly, not case-insensitively" {
    # detect_gpu exports the literal string "Intel"; anything else means
    # detection changed shape and the platform branch must not guess.
    GPU_VENDOR="intel"
    resolve_platform_target
    [ "$PLATFORM_TARGET" = "cpu" ]
}

@test "resolve_platform_target: always resolves to one of the four known targets" {
    for n in true false; do
        for a in true false; do
            for v in NVIDIA AMD Intel "" Matrox; do
                HAS_NVIDIA_GPU=$n HAS_AMD_GPU=$a GPU_VENDOR=$v
                resolve_platform_target
                case "$PLATFORM_TARGET" in
                    nvidia|amd|intel|cpu) ;;
                    *) echo "unexpected target '${PLATFORM_TARGET}' for n=$n a=$a v=$v"; return 1 ;;
                esac
            done
        done
    done
}

@test "resolve_platform_target: install.sh handles every target this can emit" {
    # install.sh's section_platform has a case arm per target and a fail_loud
    # default; a new target added here without an arm there aborts the install.
    for target in nvidia amd intel cpu; do
        grep -qE "^ *${target}\)" "${AWB_ROOT}/install.sh" \
            || { echo "install.sh section_platform has no arm for '${target}'"; return 1; }
    done
}
