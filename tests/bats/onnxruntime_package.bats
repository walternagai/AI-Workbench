#!/usr/bin/env bats
# M6: the ONNX Runtime wheel is chosen per platform. doctor.sh used to check a
# fixed onnxruntime-openvino, so an NVIDIA or CPU host with a correct install
# got a false warning. The mapping now lives in one place, lib/utils.sh, and
# both the installer and doctor call it. Hermetic: no pip, no network.

setup() {
    REPO="${BATS_TEST_DIRNAME}/../.."
    source "${REPO}/lib/colors.sh"
    source "${REPO}/lib/logger.sh"
    source "${REPO}/lib/utils.sh"
}

@test "onnxruntime_package_for: nvidia gets the GPU wheel" {
    [ "$(onnxruntime_package_for nvidia)" = "onnxruntime-gpu" ]
}

@test "onnxruntime_package_for: intel gets the OpenVINO wheel" {
    [ "$(onnxruntime_package_for intel)" = "onnxruntime-openvino" ]
}

@test "onnxruntime_package_for: cpu and amd get the plain wheel" {
    [ "$(onnxruntime_package_for cpu)" = "onnxruntime" ]
    [ "$(onnxruntime_package_for amd)" = "onnxruntime" ]
}

@test "doctor.sh no longer hard-codes the OpenVINO wheel name (M6)" {
    ! grep -q 'onnxruntime-openvino' "${REPO}/doctor.sh"
    grep -q 'onnxruntime_package_for' "${REPO}/doctor.sh"
}

@test "the runtime installer no longer hard-codes the wheel names (M6)" {
    ! grep -q 'onnxruntime-openvino\|onnxruntime-gpu' "${REPO}/runtimes/onnxruntime/install.sh"
}
