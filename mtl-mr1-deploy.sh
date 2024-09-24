#!/bin/sh

set -x

echo "Start to deploy release"

grub_f="/etc/default/grub"
source_list="/etc/apt/sources.list.d/intel-mtl.list"
pref_cfg="/etc/apt/preferences.d/intel-mtl"
cmdl="i915.enable_guc=3 i915.max_vfs=7 i915.force_probe=* udmabuf.list_limit=8192"

sudo apt update
sudo apt upgrade -y

echo "Add source list"
if [ -f $source_list ]; then
        echo "source list $source_list already exists, did you apply the overlay before? Skip $source_list !"
else
        sudo tee -a $source_list << EOF
deb https://download.01.org/intel-linux-overlay/ubuntu jammy main non-free multimedia kernels
deb-src https://download.01.org/intel-linux-overlay/ubuntu jammy main non-free multimedia kernels
EOF
fi

sudo wget https://download.01.org/intel-linux-overlay/ubuntu/E6FA98203588250569758E97D176E3162086EE4C.gpg -O /etc/apt/trusted.gpg.d/mtl.gpg

if [ -f $pref_cfg ]; then
        echo "preference file $pref_cfg already exists, did you apply the overlay before? Skip $pref_cfg !"
else
        sudo tee -a $pref_cfg << EOF
Package: *
Pin: release o= intel-iot-linux-overlay
Pin-Priority: 2000
EOF
fi

sudo apt update

echo "Update kernel image"
sudo apt install -y linux-image-6.6-intel
sudo apt install -y linux-headers-6.6-intel

echo "Update app runtime"
sudo apt install vim ocl-icd-libopencl1 curl openssh-server net-tools gir1.2-gst-plugins-bad-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gstreamer-1.0 gir1.2-gst-rtsp-server-1.0 gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-opencv gstreamer1.0-plugins-bad gstreamer1.0-plugins-bad-apps gstreamer1.0-plugins-base gstreamer1.0-plugins-base-apps gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-pulseaudio gstreamer1.0-qt5 gstreamer1.0-rtsp gstreamer1.0-tools gstreamer1.0-wpe gstreamer1.0-x intel-media-va-driver-non-free itt-dev itt-staticdev jhi jhi-tests libdrm-amdgpu1 libdrm-common libdrm-dev libdrm-intel1 libdrm-nouveau2 libdrm-radeon1 libdrm-tests libdrm2 libgstrtspserver-1.0-dev libgstrtspserver-1.0-0 libgstreamer-gl1.0-0 libgstreamer-opencv1.0-0 libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-bad1.0-dev libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev libgstreamer-plugins-good1.0-0 libgstreamer-plugins-good1.0-dev libgstreamer1.0-0 libgstreamer1.0-dev libigdgmm-dev libigdgmm12 libigfxcmrt-dev libigfxcmrt7 libmfx-gen1.2 libtpms-dev libtpms0 libva-dev libva-drm2 libva-glx2 libva-wayland2 libva-x11-2 libva2 libwayland-bin libwayland-client0 libwayland-cursor0 libwayland-dev libwayland-doc libwayland-egl-backend-dev libwayland-egl1 libwayland-server0 libweston-9-0 libweston-9-dev libxatracker2 linux-firmware mesa-utils mesa-va-drivers mesa-vdpau-drivers mesa-vulkan-drivers libvpl-dev libmfx-gen-dev onevpl-tools ovmf ovmf-ia32 qemu qemu-efi qemu-block-extra qemu-guest-agent qemu-system qemu-system-arm qemu-system-common qemu-system-data qemu-system-gui qemu-system-mips qemu-system-misc qemu-system-ppc qemu-system-s390x qemu-system-sparc qemu-system-x86 qemu-system-x86-microvm qemu-user qemu-user-binfmt qemu-utils va-driver-all vainfo weston xserver-xorg-core libvirt0 libvirt-clients libvirt-daemon libvirt-daemon-config-network libvirt-daemon-config-nwfilter libvirt-daemon-driver-lxc libvirt-daemon-driver-qemu libvirt-daemon-driver-storage-gluster libvirt-daemon-driver-storage-iscsi-direct libvirt-daemon-driver-storage-rbd libvirt-daemon-driver-storage-zfs libvirt-daemon-driver-vbox libvirt-daemon-driver-xen libvirt-daemon-system libvirt-daemon-system-systemd libvirt-dev libvirt-doc libvirt-login-shell libvirt-sanlock libvirt-wireshark libnss-libvirt swtpm swtpm-tools bmap-tools adb autoconf automake libtool cmake g++ gcc git intel-gpu-tools libssl3 libssl-dev make mosquitto mosquitto-clients build-essential apt-transport-https default-jre docker-compose ffmpeg git-lfs gnuplot lbzip2 libglew-dev libglm-dev libsdl2-dev mc openssl pciutils python3-pandas python3-pip python3-seaborn terminator vim wmctrl wayland-protocols gdbserver ethtool iperf3 msr-tools powertop linuxptp lsscsi tpm2-tools tpm2-abrmd binutils cifs-utils i2c-tools xdotool gnupg lsb-release ethtool iproute2 -y --allow-downgrades

echo "Update cmdline"
grep -q "$cmdl" "$grub_f"
ret=$?
if [ $ret -eq 0 ]; then
        echo "$cmdl already in $grub_f, did you apply the overlay before? Skip $grub_f !"
else
        rep="GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash $cmdl\""
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\"/$rep/g" $grub_f
fi

echo "End deploy release"
