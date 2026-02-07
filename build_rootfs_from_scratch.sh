#!/bin/bash
set -e

# ==============================================================================
# Debian RootFS 从零构建脚本 V1.0
# 目标：RK3566 (ARM64) - Debian Bookworm
# ==============================================================================

ROOTFS_DIR="$(pwd)/rootfs"
ARCH="arm64"
RELEASE="bookworm"
MIRROR="http://mirrors.ustc.edu.cn/debian"

# 1. 检查权限和依赖
if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

if ! command -v debootstrap >/dev/null; then
    echo "错误：请安装 debootstrap (sudo apt install debootstrap)"
    exit 1
fi

# 2. 清理旧目录
if [ -d "$ROOTFS_DIR" ]; then
    echo ">>> 清理旧的 rootfs 目录..."
    rm -rf "$ROOTFS_DIR"
fi
mkdir -p "$ROOTFS_DIR"

# 3. 第一阶段：debootstrap 下载基础包
echo ">>> [1/3] 开始下载基础系统 (第一阶段)..."
debootstrap --arch=$ARCH --foreign $RELEASE "$ROOTFS_DIR" $MIRROR

# 4. 配置 QEMU
echo ">>> 配置 QEMU 环境..."
cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"

# 5. 第二阶段：进入 chroot 完成安装
echo ">>> [2/3] 完成系统安装 (第二阶段)..."
chroot "$ROOTFS_DIR" /bin/bash -c "/debootstrap/debootstrap --second-stage"

# 6. 第三阶段：系统配置与包安装
echo ">>> [3/3] 配置系统环境..."
cat <<EOF > "$ROOTFS_DIR/setup.sh"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# 设置国内源
cat <<EOR > /etc/apt/sources.list
deb http://mirrors.ustc.edu.cn/debian bookworm main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian bookworm-updates main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian bookworm-backports main contrib non-free non-free-firmware
EOR

apt-get update
apt-get install -y --no-install-recommends locales bash-completion vim nano sudo network-manager wpasupplicant iputils-ping net-tools ssh curl wget usbutils pciutils systemd-timesyncd wireless-regdb bluez bluez-tools openssh-server xfce4 lightdm xfce4-goodies xserver-xorg

# 设置 NTP 国内加速
cat <<EON > /etc/systemd/timesyncd.conf
[Time]
NTP=ntp.aliyun.com ntp.tencent.com
FallbackNTP=0.debian.pool.ntp.org 1.debian.pool.ntp.org
EON

# 优化 DNS 解析：优先使用 IPv4
echo "precedence ::ffff:0:0/96 100" >> /etc/gai.conf

# 设置 NetworkManager 默认优先级 (确保 wlan0 优先于虚拟网卡)
mkdir -p /etc/NetworkManager/conf.d/
cat <<EON > /etc/NetworkManager/conf.d/10-prioritize-wlan.conf
[connection]
ipv4.route-metric=100
ipv6.route-metric=100
EON

# 设置默认启动为图形界面
systemctl set-default graphical.target

# 设置主机名
echo "tspi" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.1.1 tspi" >> /etc/hosts

# 设置时区
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 设置 Root 密码为 root
echo "root:root" | chpasswd

# 允许 Root SSH 登录
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# 清理
apt-get clean
rm /setup.sh
EOF

chmod +x "$ROOTFS_DIR/setup.sh"
chroot "$ROOTFS_DIR" /setup.sh

# 7. 清理 QEMU 静态文件
rm "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"

echo "=============================================================================="
echo " RootFS 构建成功！"
echo " 路径：$ROOTFS_DIR"
echo " 默认账号：root / 密码：root"
echo "=============================================================================="
