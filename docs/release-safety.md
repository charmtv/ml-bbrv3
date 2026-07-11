# 发布与供应链安全说明

本仓库是安装器仓库，不是 BBR v3 内核构建仓库。安装脚本默认从 `byJoey/Actions-bbr-v3` 的 GitHub 发布页获取 `.deb` 包。

## 当前可信边界

- 本仓库维护安装脚本、配置说明、CI 和测试。
- 上游发布仓库维护内核 `.deb` 制品。
- 脚本会校验下载 URL 必须属于指定上游仓库、指定发布标签、匹配当前架构，并排除调试包。
- 如果上游发布页提供 SHA256 校验和资产，脚本会要求每个待安装 `.deb` 都存在对应校验项，并逐个执行 SHA256 校验。
- 如果上游发布页未提供校验和，脚本会提示只能完成 URL 和架构白名单校验。

## 建议的上游发布资产

每个发布版本建议至少包含：

```text
linux-image-..._<arch>.deb
linux-headers-..._<arch>.deb
linux-libc-dev_..._<arch>.deb
SHA256SUMS
```

如需生成校验和：

```bash
bash scripts/generate-checksums.sh /path/to/release-assets
```

生成后建议随 `.deb` 一起上传到同一个 GitHub 发布页。

## 持续集成门禁

本仓库拉取请求和 main 推送会运行：

- `bash -n` 语法检查
- `shellcheck`
- `shfmt -d -i 2 -ci -bn`
- `tests/test_install.sh`

GitHub Actions 使用只读 `contents` 权限，并将 `actions/checkout` 固定到 `v4` 当前解析的提交 SHA，降低动作浮动标签风险。

## 发布前检查

维护者发布前至少确认：

1. `install.sh --help` 正常输出。
2. `install.sh --latest --dry-run` 不执行系统写入。
3. `tests/test_install.sh` 通过。
4. 持续集成全部通过。
5. 上游发布标签同时存在 x86_64/arm64 资产，包名架构正确。
6. 如需要强校验，发布资产中存在 `SHA256SUMS`，并使用 `--require-checksums` 验证。

## 不做的事

- 不在安装脚本里绕过系统引导链。
- 不自动删除旧内核。
- 不吞掉 `dpkg` 或 `update-grub` 失败。
- 不在日志中打印密钥或访问令牌。
- 不把标签、README 或上游说明当成制品可信证明。
