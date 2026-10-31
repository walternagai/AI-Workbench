#!/usr/bin/env bats
# M7: derivatives of Ubuntu must resolve to the Ubuntu base the repositories
# serve. Linux Mint reports its own VERSION_CODENAME (wilma) and a VERSION_ID
# (22.1) that is not an Ubuntu version. Docker's repo, NVIDIA's repo and the
# Intel NPU assets are keyed by Ubuntu codename and tag. The fixtures are
# os-release files; AWB_OS_RELEASE points the helpers at them, as validation does.
#
# The Linux Mint fixture reflects how Mint's os-release is documented to look
# (UBUNTU_CODENAME names the base). It is NOT verified on a real Mint host, which
# is still a pending step of M7.

setup() {
    REPO="${BATS_TEST_DIRNAME}/../.."
    export AWB_OS_RELEASE
    AWB_OS_RELEASE="$(mktemp)"
    source "${REPO}/lib/colors.sh"
    source "${REPO}/lib/logger.sh"
    source "${REPO}/lib/utils.sh"
}

teardown() {
    rm -f "$AWB_OS_RELEASE"
}

_os_release() {
    printf '%s\n' "$@" > "$AWB_OS_RELEASE"
}

@test "Linux Mint: the codename is the Ubuntu base, not Mint's own" {
    _os_release 'ID=linuxmint' 'ID_LIKE="ubuntu debian"' 'VERSION_ID="22.1"' \
                'VERSION_CODENAME=wilma' 'UBUNTU_CODENAME=noble'
    [ "$(awb_ubuntu_codename)" = "noble" ]
}

@test "Linux Mint: the asset tag is ubuntu2404, not ubuntu221" {
    _os_release 'ID=linuxmint' 'VERSION_ID="22.1"' 'VERSION_CODENAME=wilma' 'UBUNTU_CODENAME=noble'
    OS_VERSION=22.1
    [ "$(awb_ubuntu_tag)" = "ubuntu2404" ]
}

@test "Pop!_OS: resolves to noble and ubuntu2404" {
    _os_release 'ID=pop' 'ID_LIKE="ubuntu debian"' 'VERSION_ID="24.04"' \
                'VERSION_CODENAME=noble' 'UBUNTU_CODENAME=noble'
    OS_VERSION=24.04
    [ "$(awb_ubuntu_codename)" = "noble" ]
    [ "$(awb_ubuntu_tag)" = "ubuntu2404" ]
}

@test "Ubuntu: no UBUNTU_CODENAME field, so VERSION_CODENAME is the base" {
    _os_release 'ID=ubuntu' 'VERSION_ID="22.04"' 'VERSION_CODENAME=jammy'
    OS_VERSION=22.04
    [ "$(awb_ubuntu_codename)" = "jammy" ]
    [ "$(awb_ubuntu_tag)" = "ubuntu2204" ]
}

@test "an unknown codename keeps the VERSION_ID-based tag" {
    _os_release 'ID=ubuntu' 'VERSION_ID="24.10"' 'VERSION_CODENAME=oracular'
    OS_VERSION=24.10
    [ "$(awb_ubuntu_tag)" = "ubuntu2410" ]
}

@test "the NPU and NVIDIA repo helpers no longer build the tag from VERSION_ID (M7)" {
    ! grep -q 'ubuntu${OS_VERSION' "${REPO}/platforms/intel/npu.sh"
    ! grep -q 'ubuntu${OS_VERSION' "${REPO}/platforms/nvidia/repo.sh"
    grep -q 'awb_ubuntu_tag' "${REPO}/platforms/intel/npu.sh"
    grep -q 'awb_ubuntu_tag' "${REPO}/platforms/nvidia/repo.sh"
}

@test "install.sh reads the Ubuntu base codename through the helper (M7)" {
    ! grep -q "/^VERSION_CODENAME=/{print" "${REPO}/install.sh"
    grep -q 'awb_ubuntu_codename' "${REPO}/install.sh"
}
