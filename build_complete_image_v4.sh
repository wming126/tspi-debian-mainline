#!/bin/bash
set -e

# ==============================================================================
# 终极构建脚本 V4.4 (Fix Symlink Loop)
# ==============================================================================
WORKDIR=$(pwd)
SRC_UBOOT="$WORKDIR/src/u-boot"
SRC_LINUX="$WORKDIR/src/linux"
SRC_RKBIN="$WORKDIR/src/rkbin"
ROOTFS_DIR="$WORKDIR/rootfs"
OUTPUT_DIR="$WORKDIR/output"
FIRMWARE_DIR="$WORKDIR/firmware"
CROSS_COMPILE="aarch64-linux-gnu-"
ROOT_UUID="614e0000-0000-4b53-8000-1d2d00005452"
BOOT_UUID="b6b2eea7-a643-49fb-9f7d-354fcba226eb"

# 1. Environment & Firmware Check
echo ">>> [Init] Checking Environment..."
if ! command -v qemu-aarch64-static >/dev/null; then
    echo "Error: qemu-user-static not found."
    exit 1
fi

BL31=$(find $SRC_RKBIN -name "rk3568_bl31_v*.elf" -o -name "rk3568_bl31_*.elf" | head -n 1)
DDR=$(find $SRC_RKBIN -name "rk3566_ddr_1056MHz*.bin" | sort -r | head -n 1)
if [ -z "$DDR" ]; then DDR=$(find $SRC_RKBIN -name "rk3566_ddr_*.bin" | sort -r | head -n 1); fi

if [ -z "$BL31" ] || [ -z "$DDR" ]; then echo "Error: Firmware missing!"; exit 1; fi
echo "  BL31: $(basename $BL31)"
echo "  DDR:  $(basename $DDR)"

if [ ! -f "$FIRMWARE_DIR/brcmfmac43430-sdio.AP6212.txt" ]; then
    echo "Error: WiFi config missing in firmware!"
    exit 1
fi

mkdir -p $OUTPUT_DIR

# ------------------------------------------------------------------------------
# 2. Build U-Boot
# ------------------------------------------------------------------------------
echo ">>> [1/6] Building U-Boot..."
cd $SRC_UBOOT
#make distclean >/dev/null
make CROSS_COMPILE=$CROSS_COMPILE lckfb-tspi-rk3566_defconfig >/dev/null
./scripts/config --enable CONFIG_BUTTON
./scripts/config --enable CONFIG_BUTTON_ADC
make CROSS_COMPILE=$CROSS_COMPILE olddefconfig >/dev/null
make CROSS_COMPILE=$CROSS_COMPILE BL31=$BL31 ROCKCHIP_TPL=$DDR all -j$(nproc) >/dev/null
cp idbloader.img u-boot.itb $OUTPUT_DIR/

# ------------------------------------------------------------------------------
# 3. Build Kernel
# ------------------------------------------------------------------------------
echo ">>> [2/6] Building Kernel..."
cd $SRC_LINUX
#make ARCH=arm64 distclean >/dev/null
make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE defconfig >/dev/null
make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE modules_prepare >/dev/null
make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE Image dtbs -j$(nproc) >/dev/null
make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE modules -j$(nproc) >/dev/null

echo "  Installing Modules..."
if [ -d "$ROOTFS_DIR/lib/modules" ]; then sudo rm -rf "$ROOTFS_DIR/lib/modules"/*; fi
sudo make ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE INSTALL_MOD_PATH=$ROOTFS_DIR modules_install >/dev/null

cp arch/arm64/boot/Image arch/arm64/boot/dts/rockchip/rk3566-lckfb-tspi.dtb $OUTPUT_DIR/

# ------------------------------------------------------------------------------
# 4. Inject Firmware (With Clean-up)
# ------------------------------------------------------------------------------
echo ">>> [3/6] Injecting Firmware..."
FW_DIR="$ROOTFS_DIR/lib/firmware/brcm"
sudo mkdir -p $FW_DIR

# CLEANUP: Remove old files/symlinks to avoid loops
echo "  Cleaning old WiFi firmware..."
sudo rm -f "$FW_DIR/brcmfmac43430-sdio."*

# Copy Files
sudo cp "$FIRMWARE_DIR/brcmfmac43430-sdio.bin" "$FW_DIR/"
sudo cp "$FIRMWARE_DIR/brcmfmac43430-sdio.AP6212.txt" "$FW_DIR/"
if [ -f "$FIRMWARE_DIR/brcmfmac43430-sdio.clm_blob" ]; then
    sudo cp "$FIRMWARE_DIR/brcmfmac43430-sdio.clm_blob" "$FW_DIR/"
fi

echo "  Linking WiFi configs..."
sudo ln -sf brcmfmac43430-sdio.bin "$FW_DIR/brcmfmac43430-sdio.lckfb,tspi-rk3566.bin"
# Standard name
sudo ln -sf brcmfmac43430-sdio.AP6212.txt "$FW_DIR/brcmfmac43430-sdio.txt"
# Device Tree name
sudo ln -sf brcmfmac43430-sdio.AP6212.txt "$FW_DIR/brcmfmac43430-sdio.lckfb,tspi-rk3566.txt"

# Bluetooth firmware injection disabled as it causes timeout issues with current patch
# (Chip works fine with ROM firmware at 1.5Mbps)
# HCD="$FIRMWARE_DIR/BCM43430A1.hcd"
# if [ -f "$HCD" ]; then
#     sudo cp "$HCD" "$FW_DIR/"
#     echo "  Linking Bluetooth firmware..."
#     sudo ln -sf BCM43430A1.hcd "$FW_DIR/BCM43430A1.lckfb,tspi-rk3566.hcd"
#     sudo ln -sf BCM43430A1.hcd "$FW_DIR/BCM.lckfb,tspi-rk3566.hcd"
#     sudo ln -sf BCM43430A1.hcd "$FW_DIR/BCM.hcd"
# fi

# ------------------------------------------------------------------------------
# 5. Repair RootFS
# ------------------------------------------------------------------------------
echo ">>> [4/6] Repairing RootFS..."
sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"

cat <<EOF > $WORKDIR/repair_rootfs.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export LANG=C

echo "Configuring APT..."
cat <<EOR > /etc/apt/sources.list
deb http://mirrors.ustc.edu.cn/debian bookworm main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian bookworm-updates main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian bookworm-backports main contrib non-free non-free-firmware
EOR

apt-get update
apt-get install -y --no-install-recommends \
    openssh-server network-manager wpasupplicant wireless-regdb bluez bluez-tools \
    parted sudo net-tools iputils-ping \
    vim nano curl wget git htop usbutils pciutils bash-completion rsync \
    build-essential python3 ca-certificates ntpdate systemd-timesyncd

echo "Generating fstab..."
cat <<EOR > /etc/fstab
PARTUUID=$ROOT_UUID / ext4 defaults 0 1
PARTUUID=$BOOT_UUID /boot ext4 defaults 0 2
EOR

systemctl enable NetworkManager ssh systemd-timesyncd
echo "NTP=pool.ntp.org ntp.aliyun.com" >> /etc/systemd/timesyncd.conf

sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

mkdir -p /etc/NetworkManager/system-connections
cat <<EOC > /etc/NetworkManager/system-connections/DDKK.nmconnection
[connection]
id=DDKK
uuid=$(uuidgen)
type=wifi
autoconnect=true
[wifi]
ssid=DDKK
hidden=true
mode=infrastructure
[wifi-security]
key-mgmt=wpa-psk
psk=147258369
[ipv4]
method=auto
[ipv6]
method=auto
EOC
chmod 600 /etc/NetworkManager/system-connections/DDKK.nmconnection

apt-get clean
EOF

chmod +x $WORKDIR/repair_rootfs.sh
sudo cp $WORKDIR/repair_rootfs.sh "$ROOTFS_DIR/repair_rootfs.sh"
sudo chroot "$ROOTFS_DIR" /repair_rootfs.sh
sudo rm "$ROOTFS_DIR/repair_rootfs.sh"
sudo rm "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"

# rc.local
RC_LOCAL="$ROOTFS_DIR/etc/rc.local"
sudo bash -c "cat > $RC_LOCAL" <<EOF
#!/bin/bash

# First Boot Resize
if [ ! -f /etc/resized ]; then
    echo "Expanding Partition..."
    echo ", +" | sfdisk -N 2 --force /dev/mmcblk1
    partprobe /dev/mmcblk1
    resize2fs /dev/mmcblk1p2
    touch /etc/resized
fi

# USB Gadget
mount -t configfs none /sys/kernel/config
modprobe libcomposite
modprobe u_ether
modprobe usb_f_rndis
mkdir -p /sys/kernel/config/usb_gadget/g1
cd /sys/kernel/config/usb_gadget/g1
echo 0x1d6b > idVendor
echo 0x0104 > idProduct
mkdir -p strings/0x409
echo "Rockchip" > strings/0x409/manufacturer
echo "RK3566" > strings/0x409/product
mkdir -p configs/c.1/strings/0x409
echo "RNDIS" > configs/c.1/strings/0x409/configuration
mkdir -p functions/rndis.usb0
ln -sf functions/rndis.usb0 configs/c.1/
ls /sys/class/udc | head -n 1 > UDC
# [Debugging] Uncomment the following lines to enable manual USB networking
# ip link set usb0 up
# ip addr add 192.168.7.2/24 dev usb0
# ip route add default via 192.168.7.1
# echo "nameserver 8.8.8.8" > /etc/resolv.conf

# WiFi Fix
modprobe -r brcmfmac
modprobe brcmfmac

# Sync Time
# (Already handled by systemd-timesyncd, but keeping as backup)
( sleep 10; ntpdate ntp.aliyun.com ) &

exit 0
EOF
sudo chmod +x $RC_LOCAL

SERVICE_FILE="$ROOTFS_DIR/etc/systemd/system/rc-local.service"
if [ ! -f "$SERVICE_FILE" ]; then
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=/etc/rc.local
ConditionFileIsExecutable=/etc/rc.local
[Service]
Type=forking
ExecStart=/etc/rc.local
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99
[Install]
WantedBy=multi-user.target
EOF
    sudo ln -sf /etc/systemd/system/rc-local.service "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/rc-local.service"
fi

# ------------------------------------------------------------------------------
# 6. Pack Images
# ------------------------------------------------------------------------------
echo ">>> [5/6] Packing Images..."
cd $OUTPUT_DIR

# Boot
dd if=/dev/zero of=boot.img bs=1M count=128 status=none
mkfs.ext4 -F -L boot -U $BOOT_UUID boot.img
mkdir -p mnt_boot
sudo mount boot.img mnt_boot
sudo cp Image rk3566-lckfb-tspi.dtb mnt_boot/
sudo mkdir -p mnt_boot/extlinux
echo "label Linux-Mainline" | sudo tee mnt_boot/extlinux/extlinux.conf
echo "    kernel /Image" | sudo tee -a mnt_boot/extlinux/extlinux.conf
echo "    fdt /rk3566-lckfb-tspi.dtb" | sudo tee -a mnt_boot/extlinux/extlinux.conf
echo "    append root=PARTUUID=$ROOT_UUID rootwait console=ttyS2,1500000 console=tty1 earlycon rw" | sudo tee -a mnt_boot/extlinux/extlinux.conf
sudo umount mnt_boot
rmdir mnt_boot

# RootFS
echo "  Packing RootFS (3.5GB)..."
dd if=/dev/zero of=rootfs.img bs=1M count=3500 status=none
mkfs.ext4 -F -L rootfs -U $ROOT_UUID rootfs.img
mkdir -p mnt_root
sudo mount rootfs.img mnt_root
sudo cp -a $ROOTFS_DIR/. mnt_root/
sudo umount mnt_root
rmdir mnt_root

# ------------------------------------------------------------------------------
# 7. Assemble
# ------------------------------------------------------------------------------
echo ">>> [6/6] Assembling..."
IMG="tspi_unified_image_v4.img"
ROOTFS_SECTORS=$(($(stat -c%s "rootfs.img") / 512))
OFF_IDB=64; OFF_UBOOT=16384; OFF_BOOT=32768; OFF_ROOTFS=294912
TOTAL_SECTORS=$((OFF_ROOTFS + ROOTFS_SECTORS + 2048))

dd if=/dev/zero of=$IMG bs=512 count=0 seek=$TOTAL_SECTORS status=none
dd if=idbloader.img of=$IMG bs=512 seek=$OFF_IDB conv=notrunc status=none
dd if=u-boot.itb of=$IMG bs=512 seek=$OFF_UBOOT conv=notrunc status=none
dd if=boot.img of=$IMG bs=512 seek=$OFF_BOOT conv=notrunc status=none
dd if=rootfs.img of=$IMG bs=512 seek=$OFF_ROOTFS conv=notrunc status=none

sgdisk -Z $IMG
sgdisk -a 1 -n 1:32768:294911  -c 1:"boot"     -t 1:8300 -u 1:$BOOT_UUID $IMG
sgdisk -a 1 -n 2:294912:$((294912 + ROOTFS_SECTORS - 1)) -c 2:"rootfs" -t 2:8300 -u 2:$ROOT_UUID $IMG

echo "=============================================================================="
echo " BUILD V4.4 SUCCESSFUL!"
echo " Image: $OUTPUT_DIR/$IMG"
echo " Flash: sudo upgrade_tool wl 0 $OUTPUT_DIR/$IMG"
echo "=============================================================================="
