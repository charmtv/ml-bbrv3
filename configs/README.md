# 内核配置

| 文件 | 架构 |
| --- | --- |
| `x86_64/linux-bbrv3.config` | x86_64 / amd64 |
| `arm64/linux-bbrv3.config` | ARM64 / aarch64 |

两份配置均启用 BBR、FQ、FQ_PIE 和 CAKE。ARM64 默认使用 BBR，与 x86_64 发布行为保持一致。
