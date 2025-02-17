#/bin/sh

echo "Upgrade i915 fw to latest"
cd /lib/firmware/i915/
sudo wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/i915/mtl_dmc.bin
sudo wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/i915/mtl_gsc_1.bin
sudo wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/i915/mtl_guc_70.bin
sudo update-initramfs -u

echo "Upgrade GPU drivers"
mkdir ~/neo
cd ~/neo
sudo apt update; sudo apt install -y ocl-icd-libopencl1
wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.2.3/intel-igc-core-2_2.2.3+18220_amd64.deb
wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.2.3/intel-igc-opencl-2_2.2.3+18220_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/24.48.31907.7/intel-level-zero-gpu_1.6.31907.7_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/24.48.31907.7/intel-opencl-icd_24.48.31907.7_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/24.48.31907.7/libigdgmm12_22.5.4_amd64.deb
sudo dpkg -i *.deb

echo "Upgrade NPU drivers"
mkdir ~/npu-drivers
cd ~/npu-drivers
sudo apt install -y libtbb12
wget https://github.com/intel/linux-npu-driver/releases/download/v1.10.1/intel-driver-compiler-npu_1.10.1.20241220-12430270326_ubuntu22.04_amd64.deb
wget https://github.com/intel/linux-npu-driver/releases/download/v1.10.1/intel-fw-npu_1.10.1.20241220-12430270326_ubuntu22.04_amd64.deb
wget https://github.com/intel/linux-npu-driver/releases/download/v1.10.1/intel-level-zero-npu_1.10.1.20241220-12430270326_ubuntu22.04_amd64.deb
wget https://github.com/oneapi-src/level-zero/releases/download/v1.17.44/level-zero_1.17.44+u22.04_amd64.deb
sudo dpkg -i *.deb

echo "Add current user as render group"
sudo gpasswd -a ${USER} render

echo "Modify NPU driver node to root:render since boot"
sudo bash -c "echo 'SUBSYSTEM==\"accel\", KERNEL==\"accel*\", GROUP=\"render\", MODE=\"0660\"' > /etc/udev/rules.d/10-intel-vpu.rules"

echo "OV environment setup done, now will reboot system in 5 seconds, ctrl-c twice if you don't want to reboot"
sleep 5
echo "Reboot!!"
sudo reboot
