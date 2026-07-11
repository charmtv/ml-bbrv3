# ml-bbrv3

用于 Debian/Ubuntu 服务器的 BBR v3 内核安装与管理脚本。内核 `.deb` 包来自上游仓库 `byJoey/Actions-bbr-v3`。

## 适用范围

| 项目 | 支持范围 |
| --- | --- |
| 系统 | Debian 10+、Ubuntu 18.04+ |
| 架构 | `x86_64`、`aarch64` |
| 引导 | GRUB，需提供 `update-grub` |

树莓派、NanoPi、U-Boot 等非标准引导环境不建议直接使用。确认引导链兼容后，可显式添加 `--force-non-grub`。

## 快速使用

打开交互菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/charmtv/ml-bbrv3/main/install.sh)
```

无人值守安装最新版：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/charmtv/ml-bbrv3/main/install.sh) --latest --yes
```

安装前预演：

```bash
bash install.sh --latest --dry-run
```

`--latest` 选择版本号最高的标准构建，不会自动选择 `-max`。如需 `-max`，请通过 `--install-version` 显式指定标签。

## 常用命令

| 操作 | 命令 |
| --- | --- |
| 查看帮助 | `bash install.sh --help` |
| 查看状态 | `bash install.sh --status` |
| 列出版本 | `bash install.sh --list-versions` |
| 安装指定版本 | `bash install.sh --install-version x86_64-7.1.3` |
| 启用 BBR + FQ | `bash install.sh --enable fq --yes` |
| 启用 BBR + FQ_PIE | `bash install.sh --enable fq_pie --yes` |
| 启用 BBR + CAKE | `bash install.sh --enable cake --yes` |
| 卸载 BBR 内核包 | `bash install.sh --uninstall` |

## 注意事项

- 安装新内核前保留至少一个可启动的旧内核。
- 确认控制台、VNC 或救援系统可用。
- 脚本默认不删除旧内核，并会阻止不受支持的非 GRUB 安装。
- 如果上游提供 SHA256 文件，脚本会校验每个待安装包；使用 `--require-checksums` 可强制要求校验和。
- 上游未提供校验和时，只能验证下载 URL、发布标签、包名和架构。

## 文档

- [故障恢复](docs/recovery.md)
- [发布与供应链安全](docs/release-safety.md)
- [内核配置](configs/README.md)

## 其他

- Telegram：https://t.me/mlvps66
- 许可：MIT
- 致谢：`Naochen2799/Latest-Kernel-BBR3`、`byJoey/Actions-bbr-v3`
