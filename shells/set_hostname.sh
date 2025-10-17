#!/usr/bin/env bash
# ===========================================
# 通用交互式主机名修改脚本（最终版）
# 支持大部分 Linux 发行版
# ===========================================

set -o errexit
set -o pipefail
set -o nounset

# 自动提权
if [ "$(id -u)" -ne 0 ]; then
    echo "🔒 正在提权..."
    exec sudo bash "$0" "$@"
fi

# 检测系统类型
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

# 交互式输入新主机名
while true; do
    read -rp "请输入新的主机名: " NEW_HOSTNAME
    NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | xargs)  # 去掉首尾空格

    # 校验主机名合法性
    if [[ "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; then
        # 二次确认
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

echo "🔧 正在修改主机名为: $NEW_HOSTNAME"

# 修改主机名
if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
else
    echo "$NEW_HOSTNAME" > /etc/hostname
    hostname "$NEW_HOSTNAME"
fi

# 更新 /etc/hosts
if grep -qE "127\.0\.1\.1" /etc/hosts; then
    sed -i "s/127\.0\.1\.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts
elif grep -qE "127\.0\.0\.1" /etc/hosts; then
    sed -i "s/127\.0\.0\.1.*/127.0.0.1 localhost $NEW_HOSTNAME/" /etc/hosts
else
    echo "127.0.0.1   localhost $NEW_HOSTNAME" >> /etc/hosts
fi

echo "✅ 主机名已成功修改为: $NEW_HOSTNAME"

# 显示验证信息
echo
echo "🌟 当前主机名状态："
hostnamectl status 2>/dev/null || hostname

echo
echo "🎉 完成！如果是远程连接，请重新登录以更新提示符。"
