#!/usr/bin/env bats
# M5: `awb monitor` must not exit silently when a sensor tool has nothing to
# report. Under pipefail and set -e, a grep or nvidia-smi that fails inside a
# pipeline used to stop the whole monitor with no message. Hermetic: sensors
# and nvidia-smi are stubbed, so the real hardware is never read.

setup() {
    export AWB_ROOT HOME
    AWB_ROOT="$(mktemp -d)"
    HOME="${AWB_ROOT}/home"
    mkdir -p "$HOME" "${AWB_ROOT}/bin"
    PATH="${AWB_ROOT}/bin:${PATH}"
    source "${BATS_TEST_DIRNAME}/../../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/logger.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/utils.sh"
    source "${BATS_TEST_DIRNAME}/../../monitoring/temperature.sh"
    source "${BATS_TEST_DIRNAME}/../../monitoring/gpu.sh"
}

teardown() {
    rm -rf "$AWB_ROOT"
}

@test "monitor_temperature: sensors with no Celsius line returns 0 and says so (M5)" {
    cat > "${AWB_ROOT}/bin/sensors" <<'EOF'
#!/bin/sh
echo "No sensors found!"
EOF
    chmod +x "${AWB_ROOT}/bin/sensors"

    run monitor_temperature
    [ "$status" -eq 0 ]
    [[ "$output" == *"não reportou leituras em °C"* ]]
}

@test "monitor_temperature: sensors with a Celsius line prints it" {
    cat > "${AWB_ROOT}/bin/sensors" <<'EOF'
#!/bin/sh
echo "Core 0:  +45.0°C  (high = +80.0°C)"
EOF
    chmod +x "${AWB_ROOT}/bin/sensors"

    run monitor_temperature
    [ "$status" -eq 0 ]
    [[ "$output" == *"+45.0°C"* ]]
}

@test "monitor_gpu: nvidia-smi that fails returns 0 and says so (M5)" {
    cat > "${AWB_ROOT}/bin/nvidia-smi" <<'EOF'
#!/bin/sh
echo "NVIDIA-SMI has failed because it couldn't communicate with the driver" >&2
exit 9
EOF
    chmod +x "${AWB_ROOT}/bin/nvidia-smi"
    GPU_VENDOR=NVIDIA

    run monitor_gpu
    [ "$status" -eq 0 ]
    [[ "$output" == *"nvidia-smi não respondeu"* ]]
}
