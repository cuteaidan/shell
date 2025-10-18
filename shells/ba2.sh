#!/usr/bin/env bash
# Cloudflare DNS Auto Updater — API Token Version
# Compatible: Debian / Ubuntu / CentOS / Fedora / Arch / Alpine / etc.
# Author: Moreanp
# Usage:
#   bash <(curl -LsSf https://raw.githubxxxxx.xxx/cf_auto_dns_token.sh) <API_TOKEN>
#   或者直接运行（脚本会交互提示）

set -euo pipefail
stty erase ^? 2>/dev/null || true  # 修复退格键显示 ^H 的问题

# ======== 通用函数 ========

check_dep() {
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "❌ 缺少依赖：$cmd"
      echo "正在安装..."
      if command -v apt &>/dev/null; then
        apt update -y && apt install -y "$cmd"
      elif command -v yum &>/dev/null; then
        yum install -y "$cmd"
      elif command -v dnf &>/dev/null; then
        dnf install -y "$cmd"
      elif command -v apk &>/dev/null; then
        apk add --no-cache "$cmd"
      elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm "$cmd"
      else
        echo "请手动安装 $cmd 后再运行脚本。"
        exit 1
      fi
    fi
  done
}

get_ip() {
  echo "🔍 正在获取公网 IP..."
  local ip
  ip=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || echo "")
  if [[ -z "$ip" ]]; then
    ip=$(curl -s https://ipv6.icanhazip.com || echo "")
  fi
  echo "$ip"
}

prompt_input() {
  local var_name="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local input
  if [[ -n "$default_value" ]]; then
    read -rp "$prompt [$default_value]: " input
    input="${input:-$default_value}"
  else
    read -rp "$prompt: " input
  fi
  echo "$input"
}

update_dns() {
  local api_token="$1"
  local zone_id="$2"
  local domain="$3"
  local subdomain="$4"
  local ip="$5"

  local record_name="${subdomain}.${domain}"

  echo "🧩 正在检查 Cloudflare 记录: $record_name"

  local record_info
  record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${record_name}" \
    -H "Authorization: Bearer ${api_token}" \
    -H "Content-Type: application/json")

  local record_id
  record_id=$(echo "$record_info" | jq -r '.result[0].id // empty')

  local record_type
  if [[ "$ip" == *:* ]]; then
    record_type="AAAA"
  else
    record_type="A"
  fi

  if [[ -n "$record_id" ]]; then
    echo "🟡 已存在记录，正在更新..."
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}" \
      -H "Authorization: Bearer ${api_token}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"${record_type}\",\"name\":\"${record_name}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":false}" \
      | jq -r '.success'
  else
    echo "🟢 创建新记录..."
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
      -H "Authorization: Bearer ${api_token}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"${record_type}\",\"name\":\"${record_name}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":false}" \
      | jq -r '.success'
  fi

  echo "✅ Cloudflare 已配置完成: ${record_name} → ${ip}"
}

# ======== 主流程 ========

echo "=============================="
echo " Cloudflare DNS 自动配置工具 "
echo "         (API Token版)         "
echo "=============================="

check_dep

# 支持命令行参数传入 Token
if [[ $# -ge 1 ]]; then
  cf_token="$1"
  echo "🔑 已检测到传入的 Cloudflare API Token"
else
  cf_token=$(prompt_input "cf_token" "请输入 Cloudflare API Token")
fi

zone_id=$(prompt_input "zone_id" "请输入 Cloudflare Zone ID（你的主域名对应的）")
domain=$(prompt_input "domain" "请输入主域名（例如 example.com）")
subdomain=$(prompt_input "subdomain" "请输入子域名（例如 node1）")

ip_now=$(get_ip)
ip=$(prompt_input "ip" "请输入要解析到的 IP" "$ip_now")

update_dns "$cf_token" "$zone_id" "$domain" "$subdomain" "$ip"

echo "🎉 完成！请到 Cloudflare 控制台查看记录是否生效。"
