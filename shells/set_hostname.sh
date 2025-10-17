#!/usr/bin/env bash
# ===========================================
# 通用主机名修改脚本（by Moreanp）
# 适配：Ubuntu/Debian/CentOS/RHEL/Fedora/Arch/Alpine/openSUSE等主流系统
# ===========================================

set -o errexit
set -o pipefail
set -o nounset

# 自动提权
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本，或输入密码以提权..."
  exec sudo bash "$0" "$@"
fi

# 检查参数
NEW_HOSTNAME="${1:-}"

if [ -z "$NEW_HOSTNAME" ]; then
  echo "用法: $0 <新主机名>"
  echo "示例: $0 myserver01"
  exit 1
fi

# 确认输入是否合法
if [[ ! "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9\-.]{0,62}$ ]]; then
  echo "❌ 无效的主机名: $NEW_HOSTNAME"
  echo "主机名只能包含字母、数字、连字符(-)、点(.)，且长度不超过63个字符。"
  exit 1
fi

echo "🧭 检测系统类型中..."
OS=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  OS=$(uname -s)
fi

echo "🔍 检测到系统类型: $OS"

# 当前主机名
OLD_HOSTNAME="$(hostname)"
echo "当前主机名: $OLD_HOSTNAME"
echo "即将修改为: $NEW_HOSTNAME"
sleep 1

# 修改主机名
change_hostname() {
  echo "🔧 正在修改主机名..."

  # 通用 systemd 方法
  if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
  else
    # 旧系统 fallback 方法
    echo "$NEW_HOSTNAME" > /etc/hostname
    hostname "$NEW_HOSTNAME"
  fi

  # 修改 /etc/hosts 中的 localhost 行
  if grep -qE "127\.0\.1\.1" /etc/hosts; then
    sed -i "s/127\.0\.1\.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts
  elif grep -qE "127\.0\.0\.1" /etc/hosts; then
    sed -i "s/127\.0\.0\.1.*/127.0.0.1 localhost $NEW_HOSTNAME/" /etc/hosts
  else
    echo "127.0.0.1   localhost $NEW_HOSTNAME" >> /etc/hosts
  fi

  echo "✅ 主机名已修改成功：$NEW_HOSTNAME"
}

change_hostname

# 验证结果
echo
echo "🌟 验证结果："
hostnamectl status 2>/dev/null || hostname

echo
echo "🎉 完成！新的主机名已生效。"
echo "如果是远程连接，请重新登录以使提示符更新。"
