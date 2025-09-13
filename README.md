# ✨ BBR 管理脚本 ✨

<div align="center">

![BBR Logo](https://img.shields.io/badge/BBR-v3-blue?style=for-the-badge&logo=linux)
![Platform](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-orange?style=for-the-badge)
![Architecture](https://img.shields.io/badge/Arch-x86_64%20%7C%20ARM64-green?style=for-the-badge)

**一个为 Debian/Ubuntu 用户设计的，简单、高效且功能丰富的 BBR 管理脚本**

无论是想一键安装最新的 **BBR v3** 内核，还是在不同的网络加速方案之间灵活切换，本脚本都能帮你轻松搞定。

> 🌟 **我们致力于提供优雅的界面和流畅的操作，让内核管理不再是件头疼事。**

</div>

---

## 🎯 目标用户与支持环境

<div align="center">

| 📋 项目 | ✅ 要求 |
|:---:|:---:|
| 🏗️ **支持架构** | `x86_64` / `aarch64` |
| 🐧 **支持系统** | Debian 10+ / Ubuntu 18.04+ |
| 💻 **目标设备** | **云服务器 (VPS/Cloud Server)** 或 **独立服务器** |
| 🔧 **引导方式** | 使用标准 `GRUB` 引导加载程序 |

</div>

> ⚠️ **重要说明**  
> 本脚本**不适用**于大多数单板计算机（SBC），例如**树莓派 (Raspberry Pi)、NanoPi** 等。这些设备通常使用 U-Boot 等非 GRUB 引导方式，脚本会执行失败。

---

---

## 🌟 功能列表

<div align="center">

| 🚀 核心功能 | 📝 详细描述 |
|:---:|:---|
| 👑 **一键安装** | 自动安装最新的 BBR v3 内核 |
| ⚡ **智能切换** | 支持 BBR+FQ、BBR+CAKE 等多种加速模式 |
| 🔧 **灵活控制** | 轻松开启/关闭 BBR 加速功能 |
| 🗑️ **安全卸载** | 一键卸载不需要的内核版本 |
| 👀 **实时监控** | 查看当前 TCP 拥塞算法和队列算法 |
| 🎨 **美观界面** | 美化的输出界面，让操作更有趣 |

</div>  

---

## 🚀 快速开始

<div align="center">

### 📥 一键安装

```bash
bash <(curl -l -s https://raw.githubusercontent.com/charmtv/ml-bbrv3/refs/heads/main/install.sh)
```

> 💡 **提示：** 复制上面的命令到终端执行即可开始使用！

</div>

---

## 🌟 操作界面

<div align="center">

### 🎮 交互式菜单

每次运行脚本，你都会进入一个活泼又实用的选项界面：

```bash
╭( ･ㅂ･)و ✧ 你可以选择以下操作哦：
  1. 🚀 安装或更新 BBR v3 (最新版)
  2. 📚 指定版本安装
  3. 🔍 检查 BBR v3 状态
  4. ⚡ 启用 BBR + FQ
  5. ⚡ 启用 BBR + FQ_PIE
  6. ⚡ 启用 BBR + CAKE
  7. 🗑️ 卸载 BBR 内核
```

> 💡 **小提示：** 如果选错了也没关系，脚本会乖乖告诉你该怎么办！

</div>  

---

## ❓ 常见问题

<div align="center">

| ❓ 问题 | 💡 解答 |
|:---:|:---|
| **为什么下载失败啦？** | 有可能是 GitHub 链接过期了，来群里吐槽一下吧！ |
| **我不是 BBR 专家，不知道选哪个加速方案？** | 放心，BBR + FQ 是最常见的方案，适用于大多数场景～ |
| **如果不小心把系统搞崩了怎么办？** | 别慌！记得备份你的内核，或者到 [米粒VPS交流群](https://t.me/mlkjfx6) 寻求帮助 |

</div>

---

## 🌈 作者信息

<div align="center">

### 👨‍💻 米粒儿

[![Telegram](https://img.shields.io/badge/Telegram-米粒VPS交流群-blue?style=for-the-badge&logo=telegram)](https://t.me/mlkjfx6)

**💬 欢迎加入我们的交流群，一起探讨技术问题！**

</div>

---

## ❤️ 开源协议

<div align="center">

欢迎使用、修改和传播这个脚本！如果你觉得它对你有帮助，记得来点个 Star ⭐ 哦～

> 💡 **免责声明：** 本脚本由作者热爱 Linux 的灵魂驱动编写，虽尽力确保安全，但任何使用问题请自负风险！

</div>

---

## 🌟 特别鸣谢

<div align="center">

感谢 [Naochen2799/Latest-Kernel-BBR3](https://github.com/Naochen2799/Latest-Kernel-BBR3) 项目提供的技术支持与灵感参考。

</div>

---

<div align="center">

## 🎉 快来体验不一样的 BBR 管理工具吧！ 🎉

[![Star](https://img.shields.io/github/stars/charmtv/ml-bbrv3?style=social)](https://github.com/charmtv/ml-bbrv3)
[![Fork](https://img.shields.io/github/forks/charmtv/ml-bbrv3?style=social)](https://github.com/charmtv/ml-bbrv3/fork)

</div>  
## Star History

<a href="https://star-history.com/#charmtv/ml-bbrv3&Timeline">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=charmtv/ml-bbrv3&type=Timeline&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=charmtv/ml-bbrv3&type=Timeline" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=charmtv/ml-bbrv3&type=Timeline" />
 </picture>
</a>
