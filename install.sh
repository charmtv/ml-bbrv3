#!/bin/bash

# 限制脚本仅支持基于 Debian/Ubuntu 的系统
if ! command -v apt-get &> /dev/null; then
    echo -e "\033[31m此脚本仅支持基于 Debian/Ubuntu 的系统，请在支持 apt-get 的系统上运行！\033[0m"
    exit 1
fi

# 检查并安装必要的依赖
REQUIRED_CMDS=("curl" "wget" "dpkg" "awk" "sed" "sysctl" "jq")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "\033[33m缺少依赖：$cmd，正在安装...\033[0m"
        sudo apt-get update && sudo apt-get install -y $cmd > /dev/null 2>&1
    fi
done

# 检测系统架构
ARCH=$(uname -m)
    if [[ "$ARCH" != "aarch64" && "$ARCH" != "x86_64" ]]; then
        echo -e "\033[31m此脚本只支持 ARM 和 x86_64 架构，您的系统架构是：$ARCH\033[0m"
        exit 1
    fi

# 获取当前 BBR 状态
CURRENT_ALGO=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
CURRENT_QDISC=$(sysctl net.core.default_qdisc | awk '{print $3}')

# sysctl 配置文件路径
SYSCTL_CONF="/etc/sysctl.d/99-joeyblog.conf"

# 函数：清理 sysctl.d 中的旧配置
clean_sysctl_conf() {
    sudo touch "$SYSCTL_CONF"
    sudo sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
    sudo sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"
}

# 函数：询问是否永久保存更改
ask_to_save() {
    echo -n -e "\033[36m是否要将这些配置永久保存到 $SYSCTL_CONF？(y/n): \033[0m"
    read -r SAVE
    if [[ "$SAVE" == "y" || "$SAVE" == "Y" ]]; then
        clean_sysctl_conf
        echo "net.core.default_qdisc=$QDISC" | sudo tee -a "$SYSCTL_CONF" > /dev/null
        echo "net.ipv4.tcp_congestion_control=$ALGO" | sudo tee -a "$SYSCTL_CONF" > /dev/null
        sudo sysctl --system > /dev/null 2>&1
        echo -e "\033[1;32m配置已永久保存\033[0m"
    else
        echo -e "\033[33m配置未永久保存\033[0m"
    fi
}

# 函数：获取已安装的 joeyblog 内核版本
get_installed_version() {
    dpkg -l | grep "linux-image" | grep "joeyblog" | awk '{print $2}' | sed 's/linux-image-//' | head -n 1
}

# 函数：智能更新引导加载程序
update_bootloader() {
    echo -e "\033[36m正在更新引导加载程序...\033[0m"
    if command -v update-grub &> /dev/null; then
        echo -e "\033[33m检测到 GRUB，正在执行 update-grub...\033[0m"
        if sudo update-grub; then
            echo -e "\033[1;32mGRUB 更新成功！\033[0m"
            return 0
        else
            echo -e "\033[1;31mGRUB 更新失败！\033[0m"
            return 1
        fi
    else
        echo -e "\033[33m未找到 'update-grub'。您的系统可能使用 U-Boot 或其他引导程序。\033[0m"
        echo -e "\033[33m在许多 ARM 系统上，内核安装包会自动处理引导更新，通常无需手动操作。\033[0m"
        echo -e "\033[33m如果重启后新内核未生效，您可能需要手动更新引导配置，请参考您系统的文档。\033[0m"
        return 0
    fi
}

# 函数：安全地安装下载的包
install_packages() {
    if ! ls /tmp/linux-*.deb &> /dev/null; then
        echo -e "\033[31m错误：未在 /tmp 目录下找到内核文件，安装中止。\033[0m"
        return 1
    fi
    
    echo -e "\033[36m开始卸载旧版内核... \033[0m"
    INSTALLED_PACKAGES=$(dpkg -l | grep "joeyblog" | awk '{print $2}' | tr '\n' ' ')
    if [[ -n "$INSTALLED_PACKAGES" ]]; then
        sudo apt-get remove --purge $INSTALLED_PACKAGES -y > /dev/null 2>&1
    fi

    echo -e "\033[36m开始安装新内核... \033[0m"
    if sudo dpkg -i /tmp/linux-*.deb && update_bootloader; then
        echo -e "\033[1;32m内核安装并配置完成！\033[0m"
        echo -n -e "\033[33m需要重启系统来加载新内核。是否立即重启？ (y/n): \033[0m"
        read -r REBOOT_NOW
        if [[ "$REBOOT_NOW" == "y" || "$REBOOT_NOW" == "Y" ]]; then
            echo -e "\033[36m系统即将重启...\033[0m"
            sudo reboot
        else
            echo -e "\033[33m操作完成。请记得稍后手动重启 ('sudo reboot') 来应用新内核。\033[0m"
        fi
    else
        echo -e "\033[1;31m内核安装或引导更新失败！系统可能处于不稳定状态。请不要重启并寻求手动修复！\033[0m"
    fi
}

# 函数：检查并安装最新版本
install_latest_version() {
    echo -e "\033[36m正在从 GitHub 获取最新版本信息...\033[0m"
    
    # 主仓库
    BASE_URL="https://api.github.com/repos/charmtv/ml-bbrv3/releases"
    RELEASE_DATA=$(curl -sL "$BASE_URL")
    
    # 如果主仓库没有数据，尝试备用仓库
    if [[ -z "$RELEASE_DATA" || "$RELEASE_DATA" == "[]" ]]; then
        echo -e "\033[33m主仓库暂无版本，尝试备用仓库...\033[0m"
        BASE_URL="https://api.github.com/repos/byJoey/Actions-bbr-v3/releases"
        RELEASE_DATA=$(curl -sL "$BASE_URL")
    fi
    
    if [[ -z "$RELEASE_DATA" ]]; then
        echo -e "\033[31m从 GitHub 获取版本信息失败。\033[0m"
        echo -e "\033[33m可能的原因：\033[0m"
        echo -e "\033[37m  1. 网络连接问题\033[0m"
        echo -e "\033[37m  2. GitHub API 访问限制\033[0m"
        echo -e "\033[37m  3. 仓库不存在或权限问题\033[0m"
        echo -e "\033[36m建议：\033[0m"
        echo -e "\033[37m  - 检查网络连接\033[0m"
        echo -e "\033[37m  - 稍后重试\033[0m"
        echo -e "\033[37m  - 联系作者获取帮助：https://t.me/mlkjfx6\033[0m"
        return 1
    fi

    local ARCH_FILTER=""
    [[ "$ARCH" == "aarch64" ]] && ARCH_FILTER="arm64"
    [[ "$ARCH" == "x86_64" ]] && ARCH_FILTER="x86_64"

    LATEST_TAG_NAME=$(echo "$RELEASE_DATA" | jq -r --arg filter "$ARCH_FILTER" 'map(select(.tag_name | test($filter; "i"))) | sort_by(.published_at) | .[-1].tag_name')

    if [[ -z "$LATEST_TAG_NAME" || "$LATEST_TAG_NAME" == "null" ]]; then
        echo -e "\033[31m未找到适合当前架构 ($ARCH) 的最新版本。\033[0m"
        echo -e "\033[33m调试信息：\033[0m"
        echo -e "\033[37m  当前架构：$ARCH\033[0m"
        echo -e "\033[37m  搜索过滤：$ARCH_FILTER\033[0m"
        echo -e "\033[33m可能的原因：\033[0m"
        echo -e "\033[37m  1. 网络连接问题，无法访问 GitHub API\033[0m"
        echo -e "\033[37m  2. 仓库中暂无适合您架构的版本\033[0m"
        echo -e "\033[37m  3. GitHub API 限制或临时故障\033[0m"
        echo -e "\033[36m建议：\033[0m"
        echo -e "\033[37m  - 检查网络连接\033[0m"
        echo -e "\033[37m  - 稍后重试\033[0m"
        echo -e "\033[37m  - 联系作者获取帮助：https://t.me/mlkjfx6\033[0m"
        return 1
    fi
    echo -e "\033[36m检测到最新版本：\033[0m\033[1;32m$LATEST_TAG_NAME\033[0m"

    INSTALLED_VERSION=$(get_installed_version)
    echo -e "\033[36m当前已安装版本：\033[0m\033[1;32m${INSTALLED_VERSION:-"未安装"}\033[0m"

    CORE_LATEST_VERSION="${LATEST_TAG_NAME#x86_64-}"
    CORE_LATEST_VERSION="${CORE_LATEST_VERSION#arm64-}"

    if [[ -n "$INSTALLED_VERSION" && "$INSTALLED_VERSION" == "$CORE_LATEST_VERSION"* ]]; then
        echo -e "\033[1;32m您已安装最新版本，无需更新\033[0m"
        return 0
    fi

    echo -e "\033[33m发现新版本或未安装内核，准备下载...\033[0m"
    ASSET_URLS=$(echo "$RELEASE_DATA" | jq -r --arg tag "$LATEST_TAG_NAME" '.[] | select(.tag_name == $tag) | .assets[].browser_download_url')
    
    rm -f /tmp/linux-*.deb

    for URL in $ASSET_URLS; do
        echo -e "\033[36m正在下载文件：$URL\033[0m"
        wget -q --show-progress "$URL" -P /tmp/ || { echo -e "\033[31m下载失败：$URL\033[0m"; return 1; }
    done
    
    install_packages
}

# 函数：安装指定版本
install_specific_version() {
    echo -e "\033[36m正在从 GitHub 获取版本列表...\033[0m"
    
    # 主仓库
    BASE_URL="https://api.github.com/repos/charmtv/ml-bbrv3/releases"
    RELEASE_DATA=$(curl -s "$BASE_URL")
    
    # 如果主仓库没有数据，尝试备用仓库
    if [[ -z "$RELEASE_DATA" || "$RELEASE_DATA" == "[]" ]]; then
        echo -e "\033[33m主仓库暂无版本，尝试备用仓库...\033[0m"
        BASE_URL="https://api.github.com/repos/byJoey/Actions-bbr-v3/releases"
        RELEASE_DATA=$(curl -s "$BASE_URL")
    fi
    
    if [[ -z "$RELEASE_DATA" ]]; then
        echo -e "\033[31m从 GitHub 获取版本信息失败。\033[0m"
        echo -e "\033[33m可能的原因：\033[0m"
        echo -e "\033[37m  1. 网络连接问题\033[0m"
        echo -e "\033[37m  2. GitHub API 访问限制\033[0m"
        echo -e "\033[37m  3. 仓库不存在或权限问题\033[0m"
        echo -e "\033[36m建议：\033[0m"
        echo -e "\033[37m  - 检查网络连接\033[0m"
        echo -e "\033[37m  - 稍后重试\033[0m"
        echo -e "\033[37m  - 联系作者获取帮助：https://t.me/mlkjfx6\033[0m"
        return 1
    fi

    local ARCH_FILTER=""
    [[ "$ARCH" == "aarch64" ]] && ARCH_FILTER="arm64"
    [[ "$ARCH" == "x86_64" ]] && ARCH_FILTER="x86_64"
    
    MATCH_TAGS=$(echo "$RELEASE_DATA" | jq -r --arg filter "$ARCH_FILTER" '.[] | select(.tag_name | test($filter; "i")) | .tag_name')

    if [[ -z "$MATCH_TAGS" ]]; then
        echo -e "\033[31m未找到适合当前架构的版本。\033[0m"
        return 1
    fi

    echo -e "\033[36m以下为适用于当前架构的版本：\033[0m"
    IFS=$'\n' read -rd '' -a TAG_ARRAY <<<"$MATCH_TAGS"

    for i in "${!TAG_ARRAY[@]}"; do
        echo -e "\033[33m $((i+1)). ${TAG_ARRAY[$i]}\033[0m"
    done

    echo -n -e "\033[36m请输入要安装的版本编号（例如 1）：\033[0m"
    read -r CHOICE
    
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#TAG_ARRAY[@]} )); then
        echo -e "\033[31m输入无效编号，取消操作。\033[0m"
        return 1
    fi
    
    INDEX=$((CHOICE-1))
    SELECTED_TAG="${TAG_ARRAY[$INDEX]}"
    echo -e "\033[36m已选择版本：\033[0m\033[1;32m$SELECTED_TAG\033[0m"

    ASSET_URLS=$(echo "$RELEASE_DATA" | jq -r --arg tag "$SELECTED_TAG" '.[] | select(.tag_name == $tag) | .assets[].browser_download_url')
    
    rm -f /tmp/linux-*.deb
    
    for URL in $ASSET_URLS; do
        echo -e "\033[36m下载中：$URL\033[0m"
        wget -q --show-progress "$URL" -P /tmp/ || { echo -e "\033[31m下载失败：$URL\033[0m"; return 1; }
    done

    install_packages
}

# 简洁的分隔线
print_separator() {
    echo -e "\033[90m─────────────────────────────────────────────\033[0m"
}

# --- 主要执行流程 ---

clear
echo -e "\033[1;36m米粒儿BBR一键脚本\033[0m"
print_separator
echo -e "\033[37m当前 TCP 拥塞控制算法：\033[0m\033[1;32m$CURRENT_ALGO\033[0m"
echo -e "\033[37m当前队列管理算法：    \033[0m\033[1;32m$CURRENT_QDISC\033[0m"
print_separator
echo -e "\033[1;33m作者：米粒儿\033[0m"
echo -e "\033[1;33mTG交流群：https://t.me/mlkjfx6\033[0m"
echo -e "\033[1;33mNL论坛：https://www.nodeloc.com/\033[0m"
print_separator

echo -e "\033[1;37m请选择操作：\033[0m"
echo -e "\033[37m 1. 安装或更新 BBR v3 (最新版)\033[0m"
echo -e "\033[37m 2. 指定版本安装\033[0m"
echo -e "\033[37m 3. 检查 BBR v3 状态\033[0m"
echo -e "\033[37m 4. 启用 BBR + FQ\033[0m"
echo -e "\033[37m 5. 启用 BBR + FQ_PIE\033[0m"
echo -e "\033[37m 6. 启用 BBR + CAKE\033[0m"
echo -e "\033[37m 7. 卸载 BBR 内核\033[0m"
print_separator
echo -n -e "\033[37m请输入选项 (1-7): \033[0m"
read -r ACTION

case "$ACTION" in
    1)
        echo -e "\033[1;32m正在安装或更新 BBR v3...\033[0m"
        install_latest_version
        ;;
    2)
        echo -e "\033[1;32m正在安装指定版本的 BBR...\033[0m"
        install_specific_version
        ;;
    3)
        echo -e "\033[1;32m检查 BBR v3 状态...\033[0m"
        BBR_MODULE_INFO=$(modinfo tcp_bbr 2>/dev/null)
        if [[ -z "$BBR_MODULE_INFO" ]]; then
            echo -e "\033[31m未加载 tcp_bbr 模块，无法检查版本。请先安装内核并重启。\033[0m"
            exit 1
        fi
        BBR_VERSION=$(echo "$BBR_MODULE_INFO" | awk '/^version:/ {print $2}')
        if [[ "$BBR_VERSION" == "3" ]]; then
            echo -e "\033[36mBBR 模块版本：\033[0m\033[1;32m$BBR_VERSION (v3)\033[0m"
        else
            echo -e "\033[33m检测到 BBR 模块，但版本是：$BBR_VERSION，不是 v3\033[0m"
        fi
        
        CURRENT_ALGO=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
        if [[ "$CURRENT_ALGO" == "bbr" ]]; then
            echo -e "\033[36mTCP 拥塞控制算法：\033[0m\033[1;32m$CURRENT_ALGO\033[0m"
        else
            echo -e "\033[31m当前算法不是 bbr，而是：$CURRENT_ALGO\033[0m"
        fi

        if [[ "$BBR_VERSION" == "3" && "$CURRENT_ALGO" == "bbr" ]]; then
            echo -e "\033[1;32m检测完成，BBR v3 已正确安装并生效\033[0m"
        else
            echo -e "\033[33mBBR v3 未完全生效。请确保已安装内核并重启，然后使用选项 4/5/6 启用\033[0m"
        fi
        ;;
    4)
        echo -e "\033[1;32m启用 BBR + FQ 加速\033[0m"
        ALGO="bbr"
        QDISC="fq"
        ask_to_save
        ;;
    5)
        echo -e "\033[1;32m启用 BBR + FQ_PIE 加速\033[0m"
        ALGO="bbr"
        QDISC="fq_pie"
        ask_to_save
        ;;
    6)
        echo -e "\033[1;32m启用 BBR + CAKE 加速\033[0m"
        ALGO="bbr"
        QDISC="cake"
        ask_to_save
        ;;
    7)
        echo -e "\033[1;32m正在卸载 BBR 内核\033[0m"
        PACKAGES_TO_REMOVE=$(dpkg -l | grep "joeyblog" | awk '{print $2}' | tr '\n' ' ')
        if [[ -n "$PACKAGES_TO_REMOVE" ]]; then
            echo -e "\033[36m将要卸载以下内核包: \033[33m$PACKAGES_TO_REMOVE\033[0m"
            sudo apt-get remove --purge $PACKAGES_TO_REMOVE -y
            update_bootloader
            echo -e "\033[1;32m内核包已卸载。请记得重启系统。\033[0m"
        else
            echo -e "\033[33m未找到由本脚本安装的 'joeyblog' 内核包。\033[0m"
        fi
        ;;
    *)
        echo -e "\033[31m无效的选项，请输入 1-7 之间的数字\033[0m"
        ;;
esac
