# 恢复手册

本项目会安装 Linux 内核 `.deb` 包并更新引导配置。执行前请确认你能通过云厂商控制台、VNC、串口或救援系统进入机器。

## 执行前检查

1. 确认当前内核：

   ```bash
   uname -a
   dpkg -l | grep '^ii' | grep 'linux-image'
   ```

2. 确认 GRUB 可用：

   ```bash
   command -v update-grub
   grep -E 'GRUB_DEFAULT|GRUB_TIMEOUT' /etc/default/grub
   ```

3. 先跑预演：

   ```bash
   bash install.sh --latest --dry-run
   ```

4. 保留至少一个可启动的旧内核。不要在安装新内核前清理旧内核。

## 安装失败

如果 `dpkg -i` 失败：

```bash
sudo apt-get -f install
sudo dpkg --configure -a
sudo update-grub
```

如果 `update-grub` 失败，不要重启。先检查：

```bash
sudo update-grub
ls -lah /boot
dpkg -l | grep 'joeyblog'
```

## 重启后无法启动

1. 从云厂商控制台进入 GRUB 菜单。
2. 选择旧内核启动。
3. 进入系统后确认当前内核：

   ```bash
   uname -r
   ```

4. 卸载 joeyblog 内核包：

   ```bash
   bash install.sh --uninstall
   ```

5. 更新引导：

   ```bash
   sudo update-grub
   ```

## BBR 未生效

检查当前可用算法和当前算法：

```bash
sysctl net.ipv4.tcp_available_congestion_control
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
```

启用常见组合：

```bash
bash install.sh --enable fq --yes
```

如果 `tcp_available_congestion_control` 中没有 `bbr`，说明当前启动的内核不包含或未加载 BBR，需要确认是否已经重启进入新内核。

## 非 GRUB 环境

脚本默认阻断没有 `update-grub` 的环境。只有确认你的系统会自动处理 Debian 内核包的引导更新时，才使用：

```bash
bash install.sh --latest --force-non-grub
```

在单板计算机（SBC）、U-Boot、定制云镜像上使用前，请先准备控制台或救援系统。
