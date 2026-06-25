#!/bin/bash
# Intel Platform Software Installer
#
# Default (PPA install):
#   sudo ./installer.sh <os_version> <platform> <kernel_variant> [OPTIONS]
#
# Build kernel from source:
#   sudo ./installer.sh <os_version> <platform> <kernel_variant> --build-kernel <release_tag> [OPTIONS]
#
#   os_version      UBUNTU_JAMMY | UBUNTU_NOBLE
#   platform        ADL | ARL | ASL | BTL | MTL | NVL | PTL | RPL | TWL | WCL
#   kernel_variant  default | rt
#
# Options:
#   --build-kernel <release_tag>
#                   Build kernel from source using the given overlay tag.
#                   (e.g. lts-v6.18.15-deb-overlay-260310T050801Z)
#   --proxy <url>   HTTP/HTTPS proxy for all downloads (curl, apt, git).
#                   Overrides the PROXY_URL variable set in the script.
#                   (e.g. http://proxy.example.com:911)
#   -h, --help      Show usage and exit
#
# Re-entrant: completed steps are tracked in .installer_state/ and skipped on re-run.
# To force a step to re-run, delete its marker file in .installer_state/.

set -euo pipefail

# script version
readonly VERSION="version 2026.0.9"

# ── PPA URL ───────────────────────────────────────────────────────────────────
readonly PPA_URL="https://download.01.org/intel-linux-overlay/ubuntu"

# ── Deb Package URLs ──────────────────────────────────────────────────────────
# To upgrade a package, update its URL here. One constant = one package.

# Noble: Intel Graphics Compiler
readonly DEB_NOBLE_IGC_CORE="https://github.com/intel/intel-graphics-compiler/releases/download/v2.28.4/intel-igc-core-2_2.28.4+20760_amd64.deb"
readonly DEB_NOBLE_IGC_OPENCL="https://github.com/intel/intel-graphics-compiler/releases/download/v2.28.4/intel-igc-opencl-2_2.28.4+20760_amd64.deb"

# Noble: Compute Runtime
readonly DEB_NOBLE_OCLOC="https://github.com/intel/compute-runtime/releases/download/26.05.37020.3/intel-ocloc_26.05.37020.3-0_amd64.deb"
readonly DEB_NOBLE_OPENCL_ICD="https://github.com/intel/compute-runtime/releases/download/26.05.37020.3/intel-opencl-icd_26.05.37020.3-0_amd64.deb"
readonly DEB_NOBLE_ZE_GPU="https://github.com/intel/compute-runtime/releases/download/26.05.37020.3/libze-intel-gpu1_26.05.37020.3-0_amd64.deb"

# Noble: Level Zero
readonly DEB_NOBLE_LEVEL_ZERO="https://github.com/oneapi-src/level-zero/releases/download/v1.22.4/level-zero_1.22.4+u24.04_amd64.deb"
readonly DEB_NOBLE_LEVEL_ZERO_DEV="https://github.com/oneapi-src/level-zero/releases/download/v1.22.4/level-zero-devel_1.22.4+u24.04_amd64.deb"

# Jammy: Intel Graphics Compiler
readonly DEB_JAMMY_IGC_CORE="https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.16510.2/intel-igc-core_1.0.16510.2_amd64.deb"
readonly DEB_JAMMY_IGC_OPENCL="https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.16510.2/intel-igc-opencl_1.0.16510.2_amd64.deb"

# Jammy: Compute Runtime
readonly DEB_JAMMY_LZ_GPU="https://github.com/intel/compute-runtime/releases/download/24.13.29138.7/intel-level-zero-gpu_1.3.29138.7_amd64.deb"
readonly DEB_JAMMY_OPENCL_ICD="https://github.com/intel/compute-runtime/releases/download/24.13.29138.7/intel-opencl-icd_24.13.29138.7_amd64.deb"

# Jammy: NPU Driver
readonly DEB_JAMMY_NPU_COMPILER="https://github.com/intel/linux-npu-driver/releases/download/v1.2.0/intel-driver-compiler-npu_1.2.0.20240404-8553879914_ubuntu22.04_amd64.deb"
readonly DEB_JAMMY_NPU_FW="https://github.com/intel/linux-npu-driver/releases/download/v1.2.0/intel-fw-npu_1.2.0.20240404-8553879914_ubuntu22.04_amd64.deb"
readonly DEB_JAMMY_NPU_LZ="https://github.com/intel/linux-npu-driver/releases/download/v1.2.0/intel-level-zero-npu_1.2.0.20240404-8553879914_ubuntu22.04_amd64.deb"

# Jammy: Level Zero
readonly DEB_JAMMY_LEVEL_ZERO="https://github.com/oneapi-src/level-zero/releases/download/v1.16.1/level-zero_1.16.1+u22.04_amd64.deb"

# Platform-specific NPU driver tarball (Noble, replaces bundled Jammy NPU packages)
readonly DEB_PTL_NPU_TARBALL="https://github.com/intel/linux-npu-driver/releases/download/v1.32.0/linux-npu-driver-v1.32.0.20260402-23905121947-ubuntu2404.tar.gz"
#readonly DEB_PTL_NPU_LZ="https://snapshot.ppa.launchpadcontent.net/kobuk-team/intel-graphics/ubuntu/20260324T100000Z/pool/main/l/level-zero-loader/libze1_1.27.0-1~24.04~ppa2_amd64.deb"

# ── Proxy Configuration ───────────────────────────────────────────────────────
# Set PROXY_URL to route all outbound traffic (curl, apt-get, git) through a proxy.
# Leave empty for direct connectivity.
# Example: PROXY_URL="http://proxy.example.com:911"
PROXY_URL=""

# ── Platform Configuration ────────────────────────────────────────────────────

declare -A PLATFORM_KERNEL_VERSION=(
    [ADL]="6.18"  [RPL]="6.18"  [MTL]="6.18"
    [ARL]="6.18"  [BTL]="6.18"  [ASL]="6.18"
    [TWL]="6.18"  [PTL]="6.18"  [WCL]="6.18"
    [NVL]="6.19"
)

# Platforms where RT kernel is not supported
declare -A RT_UNSUPPORTED=( [ARL]=1 [MTL]=1 )

# ── Argument Parsing ──────────────────────────────────────────────────────────

BUILD_KERNEL=false

usage() {
    echo "${VERSION}"
    cat <<EOF
Usage:
  PPA install (default):
    sudo $0 <os_version> <platform> <kernel_variant> [OPTIONS]

  Build from source:
    sudo $0 <os_version> <platform> <kernel_variant> --build-kernel <release_tag> [OPTIONS]

  os_version      UBUNTU_JAMMY | UBUNTU_NOBLE
  platform        ADL | ARL | ASL | BTL | MTL | NVL | PTL | RPL | TWL | WCL
  kernel_variant  default | rt

Options:
  --build-kernel <release_tag>
                  Build kernel from source using the given overlay tag.
                  (e.g. lts-v6.18.15-deb-overlay-260310T050801Z)
  --proxy <url>   HTTP/HTTPS proxy for all downloads (curl, apt, git).
                  (e.g. http://proxy.example.com:911)
  -h, --help      Show this help

Examples:
  sudo $0 UBUNTU_NOBLE BTL default
  sudo $0 UBUNTU_NOBLE PTL rt --build-kernel lts-v6.18.15-deb-overlay-260310T050801Z
  sudo $0 UBUNTU_NOBLE BTL default --proxy http://proxy.example.com:911
EOF
    exit "${1:-0}"
}

positional=()
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
    arg="${args[$i]}"
    case "${arg}" in
        --build-kernel)
            BUILD_KERNEL=true
            i=$(( i + 1 ))
            if [[ $i -lt ${#args[@]} ]] && [[ "${args[$i]}" != -* ]]; then
                RELEASE_TAG="${args[$i]}"
            else
                echo "ERROR: --build-kernel requires a <release_tag> argument." >&2
                usage 1
            fi
            ;;
        --proxy)
            i=$(( i + 1 ))
            if [[ $i -lt ${#args[@]} ]] && [[ "${args[$i]}" != -* ]]; then
                PROXY_URL="${args[$i]}"
            else
                echo "ERROR: --proxy requires a <url> argument." >&2
                usage 1
            fi
            ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: ${arg}" >&2; usage 1 ;;
        *)  positional+=("${arg}") ;;
    esac
    i=$(( i + 1 ))
done

# Both modes share the same 3 positional args: <os_version> <platform> <kernel_variant>
[[ ${#positional[@]} -ge 3 ]] || usage 1
OS_VERSION="${positional[0]}"
PLATFORM="${positional[1]}"
KERNEL_VARIANT="${positional[2]}"
[[ "${BUILD_KERNEL}" == "false" ]] && RELEASE_TAG=""

case "${OS_VERSION}" in
    UBUNTU_JAMMY|UBUNTU_NOBLE) ;;
    *) echo "ERROR: Invalid os_version '${OS_VERSION}'. Must be UBUNTU_JAMMY or UBUNTU_NOBLE." >&2; exit 1 ;;
esac

[[ -v PLATFORM_KERNEL_VERSION["${PLATFORM}"] ]] \
    || { echo "ERROR: Invalid platform '${PLATFORM}'. Valid values: ${!PLATFORM_KERNEL_VERSION[*]}" >&2; exit 1; }
KERNEL_VERSION="${PLATFORM_KERNEL_VERSION[${PLATFORM}]}"

case "${KERNEL_VARIANT}" in
    default|rt) ;;
    *) echo "ERROR: Invalid kernel_variant '${KERNEL_VARIANT}'. Must be 'default' or 'rt'." >&2; exit 1 ;;
esac

if [[ "${KERNEL_VARIANT}" == "rt" ]] && [[ -v RT_UNSUPPORTED["${PLATFORM}"] ]]; then
    echo "ERROR: RT kernel is not supported on platform ${PLATFORM}." >&2; exit 1
fi

if [[ "${BUILD_KERNEL}" == "true" ]]; then
    [[ "${RELEASE_TAG}" == *"${KERNEL_VERSION}"* ]] \
        || { echo "ERROR: release_tag '${RELEASE_TAG}' does not contain expected kernel version ${KERNEL_VERSION} for platform ${PLATFORM}." >&2; exit 1; }
fi

# ── Logging & State Tracking ──────────────────────────────────────────────────

SCRIPT_DIR="$PWD"
LOG_FILE="${SCRIPT_DIR}/$(date +%Y%m%d)_${KERNEL_VARIANT}_installer.log"
STATE_DIR="${SCRIPT_DIR}/.installer_state"
CACHE_DIR="${SCRIPT_DIR}/.installer_cache"
TEMP_DIR=$(mktemp -d)
# Written by setup_proxy() when a proxy is configured; removed on exit.
APT_PROXY_CONF="/etc/apt/apt.conf.d/99installer-proxy"
# trap 'rm -rf "${TEMP_DIR}"; rm -f "${APT_PROXY_CONF}"' EXIT

mkdir -p "${STATE_DIR}" "${CACHE_DIR}"

# CURL_PROXY_ARGS is injected into every curl invocation.
# Populated by setup_proxy(); empty array = no proxy args added.
CURL_PROXY_ARGS=()

# Apply proxy to curl, apt-get, and git when PROXY_URL is set.
setup_proxy() {
    if [[ -n "${PROXY_URL}" ]]; then
        # Explicit --proxy flag for curl (more reliable than env vars across builds).
        CURL_PROXY_ARGS=(--proxy "${PROXY_URL}")

        # git and other tools that honour standard env vars.
        export http_proxy="${PROXY_URL}"
        export https_proxy="${PROXY_URL}"
        export HTTP_PROXY="${PROXY_URL}"
        export HTTPS_PROXY="${PROXY_URL}"
        export no_proxy="localhost,127.0.0.1,::1"
        export NO_PROXY="${no_proxy}"

        # apt on Ubuntu 24.04 uses its own HTTPS transport (libapt-pkg) which does
        # not reliably inherit env vars for HTTPS sources — an apt.conf.d entry is
        # required. The file is removed by the EXIT trap after the script finishes.
        printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' \
            "${PROXY_URL}" "${PROXY_URL}" > "${APT_PROXY_CONF}"
    fi
}

log() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "${msg}" | tee -a "${LOG_FILE}"
}

die() {
    log "ERROR: $*"
    exit 1
}

run() {
    log "CMD: $*"
    "$@"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Mark a step as completed so it is skipped on re-entry.
step_done() { touch "${STATE_DIR}/$1"; }

# Returns 0 (true) if the step has already been completed.
step_skip() {
    if [[ -f "${STATE_DIR}/$1" ]]; then
        log "SKIP: step '$1' already completed. Delete ${STATE_DIR}/$1 to re-run."
        return 0
    fi
    return 1
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "This script must be run as root (use sudo)."
}

# ── Package Lists ─────────────────────────────────────────────────────────────
# One package per line for readability and easy diffing.

PACKAGES_NOBLE=(
    # Core utilities
    vim curl openssh-server net-tools pciutils
    make gcc g++ git git-lfs cmake autoconf automake libtool
    build-essential binutils openssl libssl3 libssl-dev
    apt-transport-https default-jre gnupg lsb-release
    rpc-go lms metee

    # Intel GPU / media
    libigfxcmrt-dev libigfxcmrt7
    intel-media-va-driver-non-free
    libdrm-amdgpu1 libdrm-common libdrm-dev libdrm-intel1 libdrm-nouveau2
    libdrm-radeon1 libdrm-tests libdrm2
    libva-dev libva-drm2 libva-glx2 libva-wayland2 libva-x11-2 libva2
    va-driver-all vainfo
    mesa-utils mesa-vulkan-drivers
    libigdgmm-dev libigdgmm12
    libmfx-gen1.2 libmfx-gen-dev libvpl-dev libvpl-tools onevpl-tools
    ocl-icd-libopencl1
    intel-gpu-tools

    # GStreamer
    gir1.2-gst-plugins-bad-1.0 gir1.2-gst-plugins-base-1.0
    gir1.2-gstreamer-1.0 gir1.2-gst-rtsp-server-1.0
    gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-opencv
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-bad-apps
    gstreamer1.0-plugins-base gstreamer1.0-plugins-base-apps
    gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly
    gstreamer1.0-pulseaudio gstreamer1.0-qt5 gstreamer1.0-rtsp
    gstreamer1.0-tools gstreamer1.0-x
    libgstrtspserver-1.0-dev libgstrtspserver-1.0-0
    libgstreamer-gl1.0-0 libgstreamer-opencv1.0-0
    libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-bad1.0-dev
    libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev
    libgstreamer-plugins-good1.0-0 libgstreamer-plugins-good1.0-dev
    libgstreamer1.0-0 libgstreamer1.0-dev

    # Wayland / display
    libwayland-bin libwayland-client0 libwayland-cursor0 libwayland-dev
    libwayland-doc libwayland-egl-backend-dev libwayland-egl1 libwayland-server0
    weston xserver-xorg-core linux-firmware

    # QEMU / virtualisation
    ovmf ovmf-ia32
    qemu-block-extra qemu-guest-agent qemu-system qemu-system-arm
    qemu-system-common qemu-system-data qemu-system-gui qemu-system-mips
    qemu-system-misc qemu-system-ppc qemu-system-s390x qemu-system-sparc
    qemu-system-x86 qemu-system-modules-opengl
    qemu-user qemu-user-binfmt qemu-utils
    libvirt0 libvirt-clients libvirt-daemon
    libvirt-daemon-config-network libvirt-daemon-config-nwfilter
    libvirt-daemon-driver-lxc libvirt-daemon-driver-qemu
    libvirt-daemon-driver-storage-gluster libvirt-daemon-driver-storage-iscsi-direct
    libvirt-daemon-driver-storage-rbd libvirt-daemon-driver-storage-zfs
    libvirt-daemon-driver-vbox libvirt-daemon-driver-xen
    libvirt-daemon-system libvirt-daemon-system-systemd
    libvirt-dev libvirt-doc libvirt-login-shell libvirt-sanlock libvirt-wireshark
    libnss-libvirt swtpm swtpm-tools libtpms-dev libtpms0

    # Networking / debug tools
    socat virt-viewer spice-client-gtk
    ethtool iproute2 xdp-tools libxdp-dev libxdp1
    iperf3 msr-tools powertop linuxptp lsscsi
    tpm2-tools tpm2-abrmd bmap-tools
    gdbserver i2c-tools cifs-utils

    # Dev / multimedia tools
    adb docker-compose ffmpeg gnuplot lbzip2
    libglew-dev libglm-dev libsdl2-dev mc
    python3-pandas python3-pip python3-seaborn
    terminator wmctrl xdotool mosquitto mosquitto-clients

    # Noble-specific
    util-linux-extra dbus-x11 sg3-utils rpm
)

PACKAGES_JAMMY=(
    # Core utilities
    vim curl openssh-server net-tools pciutils
    make gcc g++ git git-lfs cmake autoconf automake libtool
    build-essential binutils openssl libssl3 libssl-dev
    apt-transport-https default-jre gnupg lsb-release

    # Intel GPU / media
    libigfxcmrt-dev libigfxcmrt7
    intel-media-va-driver-non-free
    libdrm-amdgpu1 libdrm-common libdrm-dev libdrm-intel1 libdrm-nouveau2
    libdrm-radeon1 libdrm-tests libdrm2
    libxatracker2
    libva-dev libva-drm2 libva-glx2 libva-wayland2 libva-x11-2 libva2
    va-driver-all vainfo
    mesa-utils mesa-va-drivers mesa-vdpau-drivers mesa-vulkan-drivers
    libigdgmm-dev libigdgmm12
    libmfx-gen1.2 libmfx-gen-dev libvpl-dev onevpl-tools
    ocl-icd-libopencl1
    intel-gpu-tools

    # GStreamer
    gir1.2-gst-plugins-bad-1.0 gir1.2-gst-plugins-base-1.0
    gir1.2-gstreamer-1.0 gir1.2-gst-rtsp-server-1.0
    gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-opencv
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-bad-apps
    gstreamer1.0-plugins-base gstreamer1.0-plugins-base-apps
    gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly
    gstreamer1.0-pulseaudio gstreamer1.0-qt5 gstreamer1.0-rtsp
    gstreamer1.0-tools gstreamer1.0-wpe gstreamer1.0-x
    libgstrtspserver-1.0-dev libgstrtspserver-1.0-0
    libgstreamer-gl1.0-0 libgstreamer-opencv1.0-0
    libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-bad1.0-dev
    libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev
    libgstreamer-plugins-good1.0-0 libgstreamer-plugins-good1.0-dev
    libgstreamer1.0-0 libgstreamer1.0-dev

    # Wayland / display
    libwayland-bin libwayland-client0 libwayland-cursor0 libwayland-dev
    libwayland-doc libwayland-egl-backend-dev libwayland-egl1 libwayland-server0
    libweston-9-0 libweston-9-dev
    weston xserver-xorg-core wayland-protocols linux-firmware

    # QEMU / virtualisation
    ovmf ovmf-ia32 qemu qemu-efi
    qemu-block-extra qemu-guest-agent qemu-system qemu-system-arm
    qemu-system-common qemu-system-data qemu-system-gui qemu-system-mips
    qemu-system-misc qemu-system-ppc qemu-system-s390x qemu-system-sparc
    qemu-system-x86 qemu-system-x86-microvm
    qemu-user qemu-user-binfmt qemu-utils
    libvirt0 libvirt-clients libvirt-daemon
    libvirt-daemon-config-network libvirt-daemon-config-nwfilter
    libvirt-daemon-driver-lxc libvirt-daemon-driver-qemu
    libvirt-daemon-driver-storage-gluster libvirt-daemon-driver-storage-iscsi-direct
    libvirt-daemon-driver-storage-rbd libvirt-daemon-driver-storage-zfs
    libvirt-daemon-driver-vbox libvirt-daemon-driver-xen
    libvirt-daemon-system libvirt-daemon-system-systemd
    libvirt-dev libvirt-doc libvirt-login-shell libvirt-sanlock libvirt-wireshark
    libnss-libvirt swtpm swtpm-tools libtpms-dev libtpms0

    # Networking / debug tools
    ethtool iproute2 socat virt-viewer spice-client-gtk
    iperf3 msr-tools powertop linuxptp lsscsi
    tpm2-tools tpm2-abrmd bmap-tools
    gdbserver i2c-tools cifs-utils

    # Dev / multimedia tools
    adb docker-compose ffmpeg gnuplot lbzip2
    libglew-dev libglm-dev libsdl2-dev mc
    python3-pandas python3-pip python3-seaborn
    terminator wmctrl xdotool mosquitto mosquitto-clients
)

# ── Step: setup_ppa ───────────────────────────────────────────────────────────

step_setup_ppa() {
    step_skip "ppa_setup" && return 0

    log "--- Setting up Intel PPA ---"

    local sources_file="/etc/apt/sources.list.d/intel-${PLATFORM}.list"
    local gpg_target="/etc/apt/trusted.gpg.d/${PLATFORM}.gpg"
    local pin_file="/etc/apt/preferences.d/intel-${PLATFORM}"

    command_exists curl || run apt-get update && apt-get install -y curl

    # GPG key: download only if not already present
    if [[ ! -f "${gpg_target}" ]]; then
        log "Fetching GPG key from ${PPA_URL}/..."
        local html gpg_filename
        html=$(curl -k --fail --silent "${CURL_PROXY_ARGS[@]}" "${PPA_URL}/") \
            || die "Cannot reach PPA at ${PPA_URL}"
        gpg_filename=$(echo "${html}" | grep -ioP '(?<=href=")[^"]*\.gpg' | head -1)
        [[ -n "${gpg_filename}" ]] || die "No .gpg key found at ${PPA_URL}/"
        gpg_filename=$(basename "${gpg_filename}")
        log "Downloading GPG key: ${gpg_filename}"
        run curl -k --fail --silent --location "${CURL_PROXY_ARGS[@]}" \
            "${PPA_URL}/${gpg_filename}" -o "${gpg_target}"
    else
        log "GPG key already present: ${gpg_target}"
    fi

    # Sources list
    if [[ ! -f "${sources_file}" ]]; then
        local codename
        [[ "${OS_VERSION}" == "UBUNTU_NOBLE" ]] && codename="noble" || codename="jammy"

        printf 'deb %s/ %s multimedia main non-free kernels\ndeb-src %s/ %s multimedia main non-free kernels\n' \
                "${PPA_URL}" "${codename}" "${PPA_URL}" "${codename}" \
                | tee "${sources_file}"
    else
        log "Sources list already present: ${sources_file}"
    fi

    # APT pin preferences
    if [[ ! -f "${pin_file}" ]]; then
        if [[ "${OS_VERSION}" == "UBUNTU_NOBLE" ]]; then
            printf 'Package: *\nPin: release o=intel-iot-linux-overlay-noble\nPin-Priority: 2000\n' \
                | tee "${pin_file}"
        else
            printf 'Package: *\nPin: release o=intel-iot-linux-overlay\nPin-Priority: 2000\n' \
                | tee "${pin_file}"
        fi
    else
        log "APT pin file already present: ${pin_file}"
    fi

    run apt-get update

    step_done "ppa_setup"
    log "PPA setup complete."
}

# ── Step: pre_install_deps ───────────────────────────────────────────────────

step_pre_install_deps() {
    step_skip "pre_install_deps" && return 0

    log "--- Installing common pre-requisites ---"
    run apt-get install -y --allow-downgrades ethtool libbpf1 wayland-protocols

    step_done "pre_install_deps"
    log "Pre-install deps done."
}

# ── Step: install_packages ────────────────────────────────────────────────────

step_install_packages() {
    step_skip "packages_installed" && return 0

    log "--- Installing user-space packages ---"
    run apt-get update

    local packages
    if [[ "${OS_VERSION}" == "UBUNTU_NOBLE" ]]; then
        packages=("${PACKAGES_NOBLE[@]}")
    else
        packages=("${PACKAGES_JAMMY[@]}")
    fi

    run apt-get install -y --allow-downgrades "${packages[@]}"

    step_done "packages_installed"
    log "User-space packages installed."
}

# ── Step: install_deb_packages ────────────────────────────────────────────────

step_install_deb_packages() {
    step_skip "deb_packages_installed" && return 0

    log "--- Installing Intel compute/graphics deb packages ---"

    # Use a persistent cache dir so re-runs skip already-downloaded files.
    local deb_dir="${CACHE_DIR}/intel_debs"
    mkdir -p "${deb_dir}"

    local urls=()
    if [[ "${OS_VERSION}" == "UBUNTU_NOBLE" ]]; then
        urls=(
            "${DEB_NOBLE_IGC_CORE}"
            "${DEB_NOBLE_IGC_OPENCL}"
            "${DEB_NOBLE_OCLOC}"
            "${DEB_NOBLE_OPENCL_ICD}"
            "${DEB_NOBLE_ZE_GPU}"
            "${DEB_NOBLE_LEVEL_ZERO}"
            "${DEB_NOBLE_LEVEL_ZERO_DEV}"
        )
    else
        urls=(
            "${DEB_JAMMY_IGC_CORE}"
            "${DEB_JAMMY_IGC_OPENCL}"
            "${DEB_JAMMY_LZ_GPU}"
            "${DEB_JAMMY_OPENCL_ICD}"
            "${DEB_JAMMY_NPU_COMPILER}"
            "${DEB_JAMMY_NPU_FW}"
            "${DEB_JAMMY_NPU_LZ}"
            "${DEB_JAMMY_LEVEL_ZERO}"
        )
    fi

    for url in "${urls[@]}"; do
        local filename
        filename=$(basename "${url}")
        if [[ ! -f "${deb_dir}/${filename}" ]]; then
            log "Downloading: ${filename}"
            run curl -k --fail --location "${CURL_PROXY_ARGS[@]}" "${url}" -o "${deb_dir}/${filename}"
        else
            log "Already downloaded: ${filename}"
        fi
    done

    # Selected platforms purge bundled NPU driver and replace with platform-specific version.
    if [[ "${PLATFORM}" == "PTL" || "${PLATFORM}" == "WCL" || "${PLATFORM}" == "MTL" || "${PLATFORM}" == "ARL" || "${PLATFORM}" == "NVL" ]]; then
        log "${PLATFORM}: Replacing NPU driver with platform-specific version..."
        # Allow failure only when package is not installed; other errors are logged.
        run dpkg --purge --force-remove-reinstreq \
            intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu \
            intel-level-zero-npu-dbgsym || true

        local tarball npu_extract npu_sentinel deb_npu_lz
        tarball=$(basename "${DEB_PTL_NPU_TARBALL}")
        npu_extract="${deb_dir}/npu_${PLATFORM,,}"
        npu_sentinel="${npu_extract}/.extracted"
        mkdir -p "${npu_extract}"

        if [[ ! -f "${deb_dir}/${tarball}" ]]; then
            run curl -k --fail --location "${CURL_PROXY_ARGS[@]}" "${DEB_PTL_NPU_TARBALL}" -o "${deb_dir}/${tarball}"
        fi
        if [[ ! -f "${npu_sentinel}" ]]; then
            run tar -xf "${deb_dir}/${tarball}" -C "${npu_extract}"
            touch "${npu_sentinel}"
        else
            log "NPU tarball already extracted."
        fi
        
        #deb_npu_lz=$(basename "${DEB_PTL_NPU_LZ}")
        #if [[ ! -f "${deb_dir}/${deb_npu_lz}" ]]; then
        #   run curl -k --fail --location "${CURL_PROXY_ARGS[@]}" "${DEB_PTL_NPU_LZ}" -o "${deb_dir}/${deb_npu_lz}"
        #else
        #   log "NPU level zero deb already exist."
        #fi

        run apt-get install -y --allow-downgrades libtbb12
        run dpkg -i "${npu_extract}"/*.deb
        #run dpkg -i "${deb_dir}/${deb_npu_lz}"
    fi

    # Install only the directly downloaded .deb files (not the npu_ptl subdir or the tarball).
    local main_debs=("${deb_dir}"/*.deb)
    run dpkg -i "${main_debs[@]}"

    step_done "deb_packages_installed"
    log "Deb packages installed."
}

# ── Step: install_kernel_ppa (default) ───────────────────────────────────────

step_install_kernel_ppa() {
    step_skip "kernel_installed" && return 0

    log "--- Installing kernel ${KERNEL_VERSION} (${KERNEL_VARIANT}) from PPA ---"
    log "Platform: ${PLATFORM}"

    # Discover the kernel image package dynamically from the PPA.
    # Package names vary across releases; apt-cache search is authoritative.
    local img_pkg headers_pkg

    if [[ "${KERNEL_VARIANT}" == "rt" ]]; then
        img_pkg=$(apt-cache search "linux-image" 2>/dev/null \
            | awk '{print $1}' \
            | grep "${KERNEL_VERSION}" \
            | grep -i "intel" \
            | grep -i "rt" \
            | grep -iv "dbg\|debug" \
            | sort | tail -1)
    else
        img_pkg=$(apt-cache search "linux-image" 2>/dev/null \
            | awk '{print $1}' \
            | grep "${KERNEL_VERSION}" \
            | grep -i "intel" \
            | grep -iv "rt\|dbg\|debug" \
            | sort | tail -1)
    fi

    [[ -n "${img_pkg}" ]] \
        || die "No kernel image package found for ${KERNEL_VERSION} ${KERNEL_VARIANT} in PPA." \
               "Verify PPA setup or use --build-kernel to build from source."

    # Derive the headers package by substituting the package name prefix.
    headers_pkg="${img_pkg/linux-image/linux-headers}"

    log "Kernel packages selected: ${img_pkg}  ${headers_pkg}"
    run apt-get install -y --allow-downgrades \
        "${img_pkg}" "${headers_pkg}"

    step_done "kernel_installed"
    log "Kernel installed from PPA."
}

# ── Step: build_kernel_source (--build-kernel) ────────────────────────────────

step_build_kernel_source() {
    step_skip "kernel_installed" && return 0

    log "--- Building kernel from source (tag: ${RELEASE_TAG}, variant: ${KERNEL_VARIANT}) ---"

    local image_name="${KERNEL_VERSION}-intel"
    local repo_dir="${CACHE_DIR}/linux-kernel-overlay"

    run apt-get install -y --allow-downgrades \
        git quilt libssl-dev kernel-wedge liblz4-tool libelf-dev flex bison libdw-dev

    run sh -c "printf 'install esp4 /bin/false\ninstall esp6 /bin/false\ninstall rxrpc /bin/false\n' > /etc/modprobe.d/dirtyfrag.conf; rmmod esp4 esp6 rxrpc 2>/dev/null; echo 3 > /proc/sys/vm/drop_caches; true"

    log "Cloning linux-kernel-overlay at tag ${RELEASE_TAG}..."
    run git clone https://github.com/intel/linux-kernel-overlay.git \
        --branch "${RELEASE_TAG}" --depth 1 "${repo_dir}"

    run sed -i \
        "s|KERNELRELEASE=\`make kernelversion\`-\${customized_kver_string}-\${timestamp,,}|KERNELRELEASE=${image_name}|g" \
        "${repo_dir}/build.sh"

    (
        cd "${repo_dir}"
        if [[ "${OS_VERSION}" == "UBUNTU_JAMMY" ]]; then
            run ./build.sh
        elif [[ "${KERNEL_VARIANT}" == "rt" ]]; then
            run ./build.sh -r yes
        else
            run ./build.sh -r no
        fi

        run dpkg -i linux-image-*.deb
        run dpkg -i linux-headers-*.deb
    )

    step_done "kernel_installed"
    log "Kernel built and installed from source."
}

# ── GRUB Helpers ──────────────────────────────────────────────────────────────

# Read a GRUB parameter value from /etc/default/grub, stripping surrounding quotes.
_grub_get() {
    local param="$1" line val
    line=$(grep -E "^${param}=" /etc/default/grub 2>/dev/null | head -1)
    [[ -z "${line}" ]] && return 0
    val="${line#"${param}="}"
    val="${val#\"}" ; val="${val%\"}"
    val="${val#\'}" ; val="${val%\'}"
    printf '%s' "${val}"
}

# Normalize a cmdline string: sort tokens so order differences don't matter.
_grub_normalize() {
    local input="$1"
    # Split on spaces, sort, rejoin with single spaces.
    tr ' ' '\n' <<< "${input}" | sort | tr '\n' ' ' | sed 's/ $//'
}

# Returns 0 if the current GRUB_CMDLINE_LINUX exactly matches the desired set
# (ignoring token order). Logs the diff if they differ.
_grub_cmdline_matches() {
    local desired="$1"
    local current norm_current norm_desired

    current=$(_grub_get "GRUB_CMDLINE_LINUX")
    norm_current=$(_grub_normalize "${current}")
    norm_desired=$(_grub_normalize "${desired}")

    if [[ "${norm_current}" != "${norm_desired}" ]]; then
        log "  GRUB cmdline differs."
        log "    current: ${current}"
        log "    desired: ${desired}"
        return 1
    fi
    return 0
}

# ── Step: configure_grub ──────────────────────────────────────────────────────

step_configure_grub() {
    step_skip "grub_configured" && return 0

    log "--- Configuring GRUB ---"

    local kernel_pkg kernel_entry
    kernel_pkg=$(apt list --installed 2>/dev/null \
        | grep "linux-image-${KERNEL_VERSION}" \
        | grep -iv "dbg\|debug" \
        | head -1 \
        | cut -d/ -f1)

    [[ -n "${kernel_pkg}" ]] \
        || die "No installed linux-image-${KERNEL_VERSION} package found. Cannot configure GRUB."

    kernel_entry="${kernel_pkg#linux-image-}"

    # Build desired cmdline for this platform/variant combination
    local cmdline
    if [[ "${PLATFORM}" == "PTL" || "${PLATFORM}" == "WCL" || "${PLATFORM}" == "NVL" ]]; then
        if [[ "${KERNEL_VARIANT}" == "rt" ]]; then
            cmdline="modprobe.blacklist=i915 processor.max_cstate=0 intel.max_cstate=0"
            cmdline+=" processor_idle.max_cstate=0 intel_idle.max_cstate=0"
            cmdline+=" clocksource=tsc tsc=reliable nowatchdog intel_pstate=disable"
            cmdline+=" idle=poll nosmt isolcpus=2,3 rcu_nocbs=2,3"
            cmdline+=" rcupdate.rcu_cpu_stall_suppress=1 rcu_nocb_poll irqaffinity=0"
            cmdline+=" mce=off hpet=disable numa_balancing=disable"
            cmdline+=" igb.blacklist=no nmi_watchdog=0 nosoftlockup"
        else
            cmdline="xe.max_vfs=7 xe.force_probe=* modprobe.blacklist=i915"
            cmdline+=" udmabuf.list_limit=8192 console=tty0 console=ttyS0,115200n8"
        fi
    else
        if [[ "${KERNEL_VARIANT}" == "rt" ]]; then
            cmdline="i915.enable_guc=3 i915.max_vfs=7 i915.force_probe=*"
            cmdline+=" udmabuf.list_limit=8192"
            cmdline+=" processor.max_cstate=0 intel.max_cstate=0"
            cmdline+=" processor_idle.max_cstate=0 intel_idle.max_cstate=0"
            cmdline+=" clocksource=tsc tsc=reliable nowatchdog intel_pstate=disable"
            cmdline+=" idle=poll noht isolcpus=2,3 rcu_nocbs=2,3"
            cmdline+=" rcupdate.rcu_cpu_stall_suppress=1 rcu_nocb_poll irqaffinity=0"
            cmdline+=" i915.enable_rc6=0 i915.enable_dc=0 i915.disable_power_well=0"
            cmdline+=" mce=off hpet=disable numa_balancing=disable"
            cmdline+=" igb.blacklist=no efi=runtime art=virtallow iommu=pt"
            cmdline+=" nmi_watchdog=0 nosoftlockup hugepages=1024"
            cmdline+=" console=tty0 console=ttyS0,115200n8 intel_iommu=on"
        else
            cmdline="i915.enable_guc=3 i915.max_vfs=7 i915.force_probe=*"
            cmdline+=" udmabuf.list_limit=8192 console=tty0 console=ttyS0,115200n8"
        fi
    fi

    # ── Check what's already correctly set ────────────────────────────────────
    local desired_default="Advanced options for Ubuntu>Ubuntu, with Linux ${kernel_entry}"
    local needs_update=false

    # GRUB_DEFAULT
    local cur_default
    cur_default=$(_grub_get "GRUB_DEFAULT")
    if [[ "${cur_default}" != "${desired_default}" ]]; then
        log "  GRUB_DEFAULT differs — current: '${cur_default}'"
        log "                         desired: '${desired_default}'"
        needs_update=true
    fi

    # GRUB_TIMEOUT_STYLE must not be 'hidden'
    if grep -qE '^GRUB_TIMEOUT_STYLE=hidden' /etc/default/grub 2>/dev/null; then
        log "  GRUB_TIMEOUT_STYLE=hidden needs to be disabled"
        needs_update=true
    fi

    # GRUB_TIMEOUT
    local cur_timeout
    cur_timeout=$(_grub_get "GRUB_TIMEOUT")
    if [[ "${cur_timeout}" != "5" ]]; then
        log "  GRUB_TIMEOUT differs — current: '${cur_timeout}', desired: '5'"
        needs_update=true
    fi

    # GRUB_CMDLINE_LINUX — check token by token
    if ! _grub_cmdline_matches "${cmdline}"; then
        needs_update=true
    fi

    if [[ "${needs_update}" == "false" ]]; then
        log "GRUB already configured correctly — no changes needed."
        step_done "grub_configured"
        return 0
    fi

    # ── Apply changes ──────────────────────────────────────────────────────────
    log "Applying GRUB configuration for kernel entry: ${kernel_entry}"

    if grep -qE '^GRUB_DEFAULT=' /etc/default/grub; then
        run sed -i \
            "s|GRUB_DEFAULT=.*|GRUB_DEFAULT=\"${desired_default}\"|" \
            /etc/default/grub
    else
        echo "GRUB_DEFAULT=\"${desired_default}\"" >> /etc/default/grub
    fi

    run sed -i 's|^GRUB_TIMEOUT_STYLE=hidden|# GRUB_TIMEOUT_STYLE=hidden|' \
        /etc/default/grub

    if grep -qE '^GRUB_TIMEOUT=' /etc/default/grub; then
        run sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=5|' /etc/default/grub
    else
        echo "GRUB_TIMEOUT=5" >> /etc/default/grub
    fi

    if grep -qE '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
        run sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${cmdline}\"|" \
            /etc/default/grub
    else
        echo "GRUB_CMDLINE_LINUX=\"${cmdline}\"" >> /etc/default/grub
    fi

    run update-grub

    step_done "grub_configured"
    log "GRUB configured."
}

# ── Step: validate_packages ───────────────────────────────────────────────────

step_validate_packages() {
    log "--- Validating installed package versions against PPA ---"

    local codename
    [[ "${OS_VERSION}" == "UBUNTU_NOBLE" ]] && codename="noble" || codename="jammy"

    # Noble has no 'kernels' component in its sources.list
    local components
    #if [[ "${OS_VERSION}" == "UBUNTU_NOBLE" ]]; then
    #    components=(multimedia main non-free)
    #else
        components=(multimedia main non-free kernels)
    #fi

    local bom_file="/opt/Bom-list.txt"
    local names_file="${SCRIPT_DIR}/installedPackagesNameList.txt"
    local versions_file="${SCRIPT_DIR}/installedPackagesVersionList.txt"
    rm -f "${versions_file}"

    run apt list --installed 2>&1 | tee "${bom_file}"

    local packages
    if [[ "${OS_VERSION}" == "UBUNTU_NOBLE" ]]; then
        packages=("${PACKAGES_NOBLE[@]}")
    else
        packages=("${PACKAGES_JAMMY[@]}")
    fi
    printf '%s\n' "${packages[@]}" > "${names_file}"

    # Fetch PPA package index files
    for component in "${components[@]}"; do
        local idx_file="${SCRIPT_DIR}/Packages_${component}"
        run curl -k --fail --silent "${CURL_PROXY_ARGS[@]}" \
            "${PPA_URL}/dists/${codename}/${component}/binary-amd64/Packages" \
            -o "${idx_file}" || {
            log "WARNING: Could not fetch Packages index for component '${component}' — skipping."
            rm -f "${idx_file}"
        }
    done

    local any_mismatch=0
    while IFS= read -r pkg_name; do
        [[ -z "${pkg_name}" ]] && continue

        # Find expected version in PPA index files
        local ppa_version=""
        for component in "${components[@]}"; do
            local idx_file="${SCRIPT_DIR}/Packages_${component}"
            [[ -f "${idx_file}" ]] || continue
            local v
            v=$(awk -v pkg="${pkg_name}" '
                /^Package: / { found = ($2 == pkg) }
                found && /^Version: / { print $2; exit }
            ' "${idx_file}")
            if [[ -n "${v}" ]]; then
                ppa_version="${v}"
                break
            fi
        done

        # Package not in PPA (from main Ubuntu repos) — skip validation
        [[ -z "${ppa_version}" ]] && continue

        if grep -q "^${pkg_name}/" "${bom_file}"; then
            local installed_ver
            installed_ver=$(grep "^${pkg_name}/" "${bom_file}" | awk '{print $2}')
            echo "${pkg_name}=${ppa_version}" >> "${versions_file}"
            if [[ "${installed_ver}" != "${ppa_version}" ]]; then
                log "MISMATCH: ${pkg_name}  installed=${installed_ver}  ppa=${ppa_version}"
                any_mismatch=1
            else
                log "OK: ${pkg_name}=${installed_ver}"
            fi
        else
            log "NOT FOUND: ${pkg_name} not in installed package list"
            any_mismatch=1
        fi
    done < "${names_file}"

    [[ "${any_mismatch}" -eq 0 ]] || die "Package version mismatches detected. Review log: ${LOG_FILE}"
    log "All package versions validated successfully."
}

# ── Step: permission and grp fixup ────────────────────────────────────────────

step_configure_groups() {
    step_skip "group_configured" && return 0
    
    log "Permission and groups fixup for NPU driver"
    
    # TODO: shall we add udev rules to fixup /dev/accel/accel0 to be root.render?
    # echo 'SUBSYSTEM==\"accel\", KERNEL==\"accel*\", GROUP=\"render\", MODE=\"0660\"' > /etc/udev/rules.d/10-intel-vpu.rules

    log "Add current user: ${SUDO_USER} to render group"
    gpasswd -a ${SUDO_USER} render
    
    step_done "group_configured"
    
    log "Permission and groups fixup for NPU driver done"
}

# ── Reboot Prompt ─────────────────────────────────────────────────────────────

prompt_reboot() {
    local timeout=10

    log "Installation complete. Prompting for reboot."

    # In non-interactive sessions (e.g. piped or CI), reboot immediately.
    if [[ ! -t 0 ]]; then
        log "Non-interactive session — rebooting now."
        reboot
        return
    fi

    echo ""
    echo "======================================================="
    echo "  Installation complete."
    echo ""
    echo "  System will reboot in ${timeout} seconds."
    echo "  Press ENTER to reboot now, or Ctrl+C to cancel."
    echo "======================================================="
    echo ""

    local confirmed=false
    read -r -t "${timeout}" _ 2>/dev/null && confirmed=true || true

    if [[ "${confirmed}" == "true" ]]; then
        log "User confirmed reboot."
    else
        echo ""
        log "Timeout reached (${timeout}s) — rebooting automatically."
    fi

    log "Rebooting..."
    reboot
}

# ── Main ──────────────────────────────────────────────────────────────────────

require_root
setup_proxy
# Suppress apt-get interactive prompts for all child processes.
export DEBIAN_FRONTEND=noninteractive

log "========================================"
log " Intel Platform Software Installer ${VERSION}"
log "========================================"
log " USER: ${USER} ORG: ${SUDO_USER}"
log " OS:            ${OS_VERSION}"
log " Platform:      ${PLATFORM}"
log " Kernel:        ${KERNEL_VERSION} (${KERNEL_VARIANT})"
log " Build kernel:  ${BUILD_KERNEL}"
if [[ "${BUILD_KERNEL}" == "true" ]]; then
    log " Release tag:   ${RELEASE_TAG}"
fi
log " Proxy:         ${PROXY_URL:-"(none)"}"
log " State dir:     ${STATE_DIR}"
log " Log file:      ${LOG_FILE}"
log "========================================"

step_setup_ppa
step_pre_install_deps
step_install_packages
step_install_deb_packages

if [[ "${BUILD_KERNEL}" == "true" ]]; then
    step_build_kernel_source
else
    step_install_kernel_ppa
fi

step_configure_grub
step_validate_packages
step_configure_groups

prompt_reboot
