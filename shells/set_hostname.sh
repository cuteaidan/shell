#!/usr/bin/env bash
# ===========================================
# 通用主机名修改脚本（增强最终版）
# 支持大部分 Linux 发行版
# 功能：
# 1. 支持命令行参数修改主机名
# 2. 不传参数时交互输入，支持左右箭头和退格
# 3. 自动修改 /etc/hostname 和 /etc/hosts
# 4. 远程安全：保留原有 localhost，不覆盖
# 5. 二次确认默认 Y
# ===========================================

set -o errexit
set -o pipefail
set -o nounset

# 自动提权
if [ "$(id -u)" -ne 0 ]; then
    echo "🔒 正在提权..."
    exec sudo bash "$0" "$@"
fi

# 系统类型
OS=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi
echo "🧭 检测到系统类型: $OS"

# 当前主机名
CURRENT_HOSTNAME=$(hostname)
echo "当前主机名: $CURRENT_HOSTNAME"

# 获取新主机名（支持参数和交互）
NEW_HOSTNAME=""
if [ $# -ge 1 ]; then
    NEW_HOSTNAME="$1"
else
    # 交互输入
    while true; do
        read -erp "请输入新的主机名: " NEW_HOSTNAME
        NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | xargs)  # 去掉首尾空格

        # 校验合法性
        if [[ "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; then
            # 二次确认（默认 Y）
            read -rp "确认将主机名修改为 '$NEW_HOSTNAME' 吗？[Y/n]: " CONFIRM
            CONFIRM=${CONFIRM:-Y}
            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                break
            else
                echo "请重新输入新的主机名。"
            fi
        else
            echo "❌ 无效主机名！只能包含字母、数字、短横线(-)、点(.)，长度不超过63个字符，请重新输入。"
        fi
    done
fi

echo "🔧 正在修改主机名为: $NEW_HOSTNAME"

# 修改主机名
if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
else
    echo "$NEW_HOSTNAME" > /etc/hostname
    hostname "$NEW_HOSTNAME"
fi

# 更新 /etc/hosts（远程安全）
if grep -q "127.0.0.1" /etc/hosts; then
    if ! grep -qE "127\.0\.0\.1.*\b$NEW_HOSTNAME\b" /etc/hosts; then
        # 追加新主机名到 127.0.0.1 行末
        sed -i "s/^\(127\.0\.0\.1.*\)$/\1 $NEW_HOSTNAME/" /etc/hosts
    fi
else
    echo "127.0.0.1   localhost $NEW_HOSTNAME" >> /etc/hosts
fi

# 检查 /etc/hosts 中 127.0.1.1（部分 Debian/Ubuntu 系统）
if grep -qE "^127\.0\.1\.1" /etc/hosts; then
    if ! grep -qE "^127\.0\.1\.1.*\b$NEW_HOSTNAME\b" /etc/hosts; then
        sed -i "s/^\(127\.0\.1\.1.*\)$/\1 $NEW_HOSTNAME/" /etc/hosts
    fi
fi

echo "✅ 主机名已成功修改为: $NEW_HOSTNAME"

# 显示验证信息
echo
echo "🌟 当前主机名状态："
hostnamectl status 2>/dev/null || hostname

echo
echo "🎉 完成！如果是远程连接，请重新登录以更新提示符。"
