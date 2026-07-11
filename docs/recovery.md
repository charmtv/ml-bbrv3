# 故障恢复

## 安装前

确认当前内核、已安装内核和 GRUB：

```bash
uname -a
dpkg -l | grep '^ii.*linux-image'
command -v update-grub
```

先运行预演，并保留至少一个可启动的旧内核：

```bash
bash install.sh --latest --dry-run
```

## 安装失败

`dpkg -i` 失败时修复依赖并重新生成 GRUB 配置：

```bash
sudo apt-get -f install
sudo dpkg --configure -a
sudo update-grub
```

如果 `update-grub` 失败，不要重启。检查 `/boot` 空间和已安装包：

```bash
ls -lah /boot
dpkg -l | grep joeyblog
```

## 无法启动

1. 通过控制台进入 GRUB。
2. 选择旧内核启动。
3. 运行 `uname -r` 确认当前内核。
4. 执行 `bash install.sh --uninstall`。
5. 执行 `sudo update-grub` 后再重启。

## BBR 未生效

```bash
sysctl net.ipv4.tcp_available_congestion_control
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
```

如果可用算法中没有 `bbr`，请确认已经重启到新内核。启用常用组合：

```bash
bash install.sh --enable fq --yes
```

## 非 GRUB 环境

仅在确认系统会自动处理 Debian 内核包引导更新时使用：

```bash
bash install.sh --latest --force-non-grub
```
