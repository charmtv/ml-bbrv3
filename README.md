# ml-bbrv3

`ml-bbrv3` 是面向 Debian/Ubuntu 服务器的 BBR v3 内核安装与管理脚本。仓库本身不构建内核制品，安装脚本会从上游仓库 `byJoey/Actions-bbr-v3` 的 GitHub 发布页获取 `.deb` 包。

## 支持范围

| 项目 | 说明 |
| --- | --- |
| 系统 | Debian 10+ / Ubuntu 18.04+ |
| 架构 | `x86_64` / `aarch64` |
| 引导 | 默认要求 GRUB 与 `update-grub` |
| 目标设备 | VPS、云服务器、独立服务器 |

不建议直接用于树莓派、NanoPi 等非标准 GRUB 引导的 SBC。确需在非 GRUB 环境使用时，必须自行确认内核包安装后引导链会更新，并显式传入 `--force-non-grub`。

## 快速开始

打开交互菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/charmtv/ml-bbrv3/main/install.sh)
```

进入菜单后，按 `1` 安装或更新最新版 BBR v3，按 `4` 查看当前状态，按 `0` 退出。

需要无人值守一键安装最新版：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/charmtv/ml-bbrv3/main/install.sh) --latest --yes
```

预演一键安装，不执行系统写入：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/charmtv/ml-bbrv3/main/install.sh) --latest --dry-run
```

查看帮助：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/charmtv/ml-bbrv3/main/install.sh) --help
```

启用 BBR + FQ 并持久化：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/charmtv/ml-bbrv3/main/install.sh) --enable fq --yes
```

## 常用命令

```bash
# 列出当前架构可用版本
bash install.sh --list-versions

# 安装指定版本
bash install.sh --install-version x86_64-7.0.5

# 查看状态
bash install.sh --status

# 启用不同队列算法
bash install.sh --enable fq
bash install.sh --enable fq_pie
bash install.sh --enable cake

# 卸载 joeyblog BBR 内核包
bash install.sh --uninstall
```

## 安全改进

新版脚本相比旧版本做了以下收口：

- 使用 `mktemp -d` 专属下载目录，不再删除或安装 `/tmp/linux-*.deb` 通配文件。
- 下载使用 `curl -fL`、连接超时、总超时和有限重试，同时校验文件非空。
- 上游发布资产必须匹配 GitHub URL、发布标签、架构和 `.deb` 包名白名单。
- 默认排除 `-dbg` 调试包，避免无意安装巨大的调试内核镜像。
- 默认不先卸载旧内核，安装成功后再由用户自行决定清理旧版本。
- 默认要求 `update-grub`；非 GRUB 环境必须显式 `--force-non-grub`。
- 支持 `--dry-run` 和 `--yes`，便于自动化和发布前预演。
- 支持 `--require-checksums`。如果上游发布页提供 SHA256 文件，脚本会自动校验；未提供时会提示只能执行 URL/架构白名单校验。

## 目录结构

```text
install.sh                         主安装器入口
configs/arm64/linux-bbrv3.config   ARM64 内核配置
configs/x86_64/linux-bbrv3.config  x86_64 内核配置
docs/recovery.md                   故障恢复与回滚建议
docs/release-safety.md             发布与供应链安全说明
scripts/generate-checksums.sh      生成本地 SHA256SUMS 的辅助脚本
tests/test_install.sh              Bash 级脚本测试
.github/workflows/ci.yml           持续集成：bash -n、shellcheck、shfmt、测试
```

## 配置说明

两份内核配置都保留 BBR、FQ、FQ_PIE、CAKE 和常见云服务器虚拟化驱动。ARM64 配置已调整为默认 BBR，并关闭发布分发中不必要的调试信息，以减小制品体积。

## 恢复与风险

安装内核属于高风险系统操作。执行前建议保留旧内核、确认控制台/VNC/救援系统可用，并阅读 [恢复手册](docs/recovery.md)。

如果下载校验、GRUB 更新、`dpkg -i` 或重启后启动失败，请先不要继续重复执行安装，按恢复手册保留现场并回滚。

## 交流与反馈

Telegram 群：https://t.me/mlvps66

## 致谢

感谢 `Naochen2799/Latest-Kernel-BBR3` 和 `byJoey/Actions-bbr-v3` 项目提供的技术参考与发布制品来源。

## 许可证

MIT
