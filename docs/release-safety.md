# 发布与供应链安全

本仓库维护安装脚本，不构建内核。默认制品来自 `byJoey/Actions-bbr-v3`。

## 校验范围

脚本会检查：

- GitHub 仓库和发布标签
- CPU 架构与 `.deb` 包名
- 下载 URL 白名单
- 调试包排除规则
- 每个待安装包的 SHA256 校验项（上游提供时）

上游未提供 SHA256 文件时，脚本会明确提示。需要强制校验时使用 `--require-checksums`。

## 发布资产

建议每个版本包含：

```text
linux-image-..._<arch>.deb
linux-headers-..._<arch>.deb
linux-libc-dev_..._<arch>.deb
SHA256SUMS
```

生成校验和：

```bash
bash scripts/generate-checksums.sh /path/to/release-assets
```

## CI

`main` 推送和拉取请求会运行：

- Bash 语法检查
- ShellCheck
- shfmt
- `tests/test_install.sh`

工作流仅授予只读 `contents` 权限，`actions/checkout` 固定到 v6 提交 SHA。

## 发布检查

1. 运行 `bash install.sh --help`。
2. 运行 `bash install.sh --latest --dry-run`。
3. 运行 `bash tests/test_install.sh`。
4. 确认 CI 通过。
5. 确认 x86_64 和 arm64 资产完整、命名正确。
6. 需要强校验时，确认存在 `SHA256SUMS` 并测试 `--require-checksums`。

脚本不会自动删除旧内核、绕过引导链或忽略 `dpkg`、`update-grub` 失败。
