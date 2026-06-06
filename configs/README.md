# 内核配置文件

这些文件是 BBR v3 发布构建使用的内核构建配置参考。

| 路径 | 目标 |
| --- | --- |
| `configs/x86_64/linux-bbrv3.config` | x86_64 / amd64 |
| `configs/arm64/linux-bbrv3.config` | ARM64 / aarch64 |

两份配置都保留 BBR 和受支持的队列算法：

- `CONFIG_TCP_CONG_BBR`
- `CONFIG_NET_SCH_FQ`
- `CONFIG_NET_SCH_FQ_PIE`
- `CONFIG_NET_SCH_CAKE`

ARM64 已配置为默认使用 BBR，与 x86_64 发布行为保持一致。
