# RK3566 泰山派 (TaiShan Pi) 开发与调试日志

本手册记录了基于 Debian Bookworm 构建泰山派主线 Linux 系统过程中遇到的核心问题、分析思路及解决方案。

---

## 1. 硬件连接与基础启动 (U-Boot)
### 1.1 常见 U-Boot 报错
*   **现象**：`Card did not respond to voltage select! : -110`
*   **分析**：U-Boot 在轮询启动设备。此报错仅表示 MicroSD 卡槽未插卡，不影响从 eMMC 启动。
*   **现象**：`Cannot persist EFI variables...`
*   **分析**：系统使用 `extlinux` 启动，未配置 EFI 分区，此报错可忽略。

---

## 2. 无线通信修复 (WiFi/BT)
### 2.1 WiFi 扫描失败 (Error -52)
*   **原因**：AP6212 模块缺少 `brcmfmac43430-sdio.clm_blob` 文件，导致射频参数无法加载。
*   **修复**：在 `/lib/firmware/brcm/` 中存入正确的 `clm_blob` 文件。

### 2.2 无线国家码报错 (Error -2)
*   **现象**：`failed to load regulatory.db`。
*   **修复**：安装 `wireless-regdb` 软件包。

### 2.3 蓝牙初始化超时 (Reset failed -110)
*   **原因**：
    1.  设备树中 `max-speed` 设为 3Mbps，板载 UART 信号完整性不足导致丢包。
    2.  `compatible` 字符串不精确。
*   **修复**：
    1.  修改 DTS，将 `max-speed` 降至 **1.5Mbps** (1500000)。
    2.  将 `compatible` 更新为 `brcm,bcm43430a1-bt`。
    3.  **注意**：不要加载外部 `.hcd` 补丁，AP6212 在 1.5M 下使用内置 ROM 固件最稳定。

---

## 3. 网络与系统优化
### 3.1 网络默认路由冲突
*   **现象**：开启 USB Gadget 后，系统默认路由被 `usb0` 抢占，导致 WiFi 无法上网。
*   **修复**：
    1.  配置 NetworkManager 禁用 `usb0` 自动连接。
    2.  在 `/etc/NetworkManager/conf.d/` 中设置 `route-metric`，确保 `wlan0` (100) 优先级高于其他网卡。
    3.  清理 `/etc/rc.local`，删除手动 `ip route add default` 的暴力指令。

### 3.2 系统时间重置
*   **现象**：无 RTC 电池，开机时间回退到 2017 年，导致 SSL 校验和 APT 更新失败。
*   **修复**：配置 `systemd-timesyncd` 使用阿里云/腾讯云 NTP 服务器，确保联网后秒级同步。

---

## 4. 存储与自动化构建
### 4.1 分区自动扩容
*   **机制**：在 `rc.local` 中加入检测逻辑。若 `/etc/resized` 不存在，则执行 `sfdisk` 扩展第二分区并调用 `resize2fs`，随后创建 flag 文件。

### 4.2 镜像一致性 (UUID)
*   **风险**：每次构建随机生成的 UUID 会导致 `fstab` 挂载失败进入 Emergency Mode。
*   **修复**：在构建脚本中使用 `mkfs.ext4 -U` 手动指定硬编码的 **PARTUUID**，并在 `fstab` 中匹配。

---

## 5. 图形界面 (XFCE4)
### 5.1 桌面点不亮 (Can't launch X server)
*   **原因**：通过 `debootstrap` 安装了 `xfce4` 但漏装了核心组件 `xserver-xorg`。
*   **修复**：安装 `xserver-xorg` 及其依赖。内核 DRM 驱动会自动分配 `fb0`。

---

## 6. 上游贡献 (Upstreaming)
### 6.1 蓝牙稳定性补丁
*   **成果**：生成了符合 Linux Mainline 规范的 Patch：`0001-arm64-dts-rockchip-Fix-Bluetooth-stability...patch`。
*   **发送**：配置 `git-email` 通过 126 SMTP 代理（解决 Gmail 墙的问题）向 `linux-rockchip` 邮件列表投递。

---

## 7. 自动化构建体系
*   **`build_rootfs_from_scratch.sh`**：从零下载、配置、加固 RootFS 的核心脚本。
*   **`build_complete_image_v4.sh`**：集成内核编译、固件注入、镜像组装的全自动化流水线。

---
**Robin & Ming Wang | 2026-02-06**
