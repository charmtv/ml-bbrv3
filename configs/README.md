# Kernel config files

These files are kernel build configuration references for BBR v3 release builds.

| Path | Target |
| --- | --- |
| `configs/x86_64/linux-bbrv3.config` | x86_64 / amd64 |
| `configs/arm64/linux-bbrv3.config` | ARM64 / aarch64 |

Both configs keep BBR and the supported queue disciplines available:

- `CONFIG_TCP_CONG_BBR`
- `CONFIG_NET_SCH_FQ`
- `CONFIG_NET_SCH_FQ_PIE`
- `CONFIG_NET_SCH_CAKE`

ARM64 is configured to default to BBR, matching the x86_64 release behavior.
