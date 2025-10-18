#!/usr/bin/env bash
# Cloudflare DNS Auto Updater — Minimal Token Version
# Author: Moreanp
# Usage:
#   bash <(curl -LsSf https://raw.githubxxxxx.xxx/cf_dns.sh) <API_TOKEN> <ZONE_ID> <DOMAIN>

set -euo pipefail
stty erase ^? 2>/dev/null || true  # 修复退格键显示 ^H 的问题

# ======== 通用函数 ========

has_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  elif type "$1" >/dev/null 2>&1; then
    return 0
  elif which "$1" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

check_dep() {
  for cmd in curl jq; do
    if ! has_cmd "$cmd"; then
      echo "⚙️ 正在安装依赖: $cmd"
      if has_cmd apt; then
        apt update -y && apt install -y "$cmd"
      elif has_cmd yum; then
        yum install -y "$cmd"
      elif has_cmd dnf; then
        dnf install -y "$cmd"
      elif has_cmd apk; then
        apk add --no-cache "$cmd"
      elif has_cmd pacman; then
        pacman -Sy --noconfirm "$cmd"
      else
        echo "❌ 请手动安装 $cmd 后再运行脚本。"
        exit 1
      fi
    fi
  done
}

get_ip() {
  curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://ipv6.icanhazip.com || echo ""
}

# ======== 主流程 ========

echo "=============================="
echo " Cloudflare DNS 自动配置工具 "
echo "         (Token版)            "
echo "=============================="

check_dep

if [[ $# -lt 3 ]]; then
  echo "❌ 参数不足"
  echo "用法: bash $0 <API_TOKEN> <ZONE_ID> <DOMAIN>"
  exit 1
fi

CF_TOKEN="$1"
ZONE_ID="$2"
DOMAIN="$3"

IP=$(get_ip)
if [[ -z "$IP" ]]; then
  echo "❌ 无法获取公网 IP"
  exit 1
fi

echo "🌐 检测到公网 IP: $IP"
echo "📡 域名: $DOMAIN"

# 判断 IPv4 / IPv6
if [[ "$IP" == *:* ]]; then
  RECORD_TYPE="AAAA"
else
  RECORD_TYPE="A"
fi

# 检查是否已存在记录
EXISTING_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${DOMAIN}" \
  -H "Authorization: Bearer ${CF_TOKEN}" \
  -H "Content-Type: application/json")

RECORD_ID=$(echo "$EXISTING_RECORD" | jq -r '.result[0].id // empty')

if [[ -n "$RECORD_ID" ]]; then
  echo "🟡 发现已存在记录，正在更新..."
  curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
    -H "Authorization: Bearer ${CF_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"${RECORD_TYPE}\",\"name\":\"${DOMAIN}\",\"content\":\"${IP}\",\"ttl\":120,\"proxied\":false}" \
    >/dev/null
else
  echo "🟢 创建新记录..."
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CF_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"${RECORD_TYPE}\",\"name\":\"${DOMAIN}\",\"content\":\"${IP}\",\"ttl\":120,\"proxied\":false}" \
    >/dev/null
fi

echo "✅ Cloudflare 已配置完成: ${DOMAIN} → ${IP}"
