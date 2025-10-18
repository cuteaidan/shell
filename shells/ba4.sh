#!/usr/bin/env bash
# Cloudflare DNS Auto Updater — Token + ZoneID + Domain + Subdomain
# Usage:
#   bash cf_dns_auto.sh [arg1] [arg2] [arg3] [arg4]
# Args can be in any order: token, zone_id, domain, subdomain
# If subdomain is missing, user will be prompted

set -euo pipefail

# --------------------- helpers ---------------------
# 兼容退格键显示 ^H
stty erase "$(tput kbs 2>/dev/null || echo '^H')" 2>/dev/null || true

has_cmd() {
  command -v "$1" >/dev/null 2>&1 || type "$1" >/dev/null 2>&1 || which "$1" >/dev/null 2>&1
}

install_pkg() {
  pkg="$1"
  if has_cmd apt; then apt update -y && apt install -y "$pkg"
  elif has_cmd yum; then yum install -y "$pkg"
  elif has_cmd dnf; then dnf install -y "$pkg"
  elif has_cmd apk; then apk add --no-cache "$pkg"
  elif has_cmd pacman; then pacman -Sy --noconfirm "$pkg"
  else echo "无法自动安装 $pkg，请手动安装后再运行脚本。" && exit 1
  fi
}

check_deps() {
  for c in curl jq; do
    if ! has_cmd "$c"; then
      echo "检测到未安装依赖: $c，尝试自动安装..."
      install_pkg "$c"
    fi
  done
}

get_ip() {
  ip="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  [[ -z "$ip" ]] && ip="$(curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)"
  [[ -z "$ip" ]] && ip="$(curl -fsS --max-time 8 https://ipv6.icanhazip.com 2>/dev/null || true)"
  echo "$ip"
}

prompt() {
  local q="$1"; local def="${2:-}"
  if [[ -n "$def" ]]; then
    read -rp "$q [$def]: " ans
    ans="${ans:-$def}"
  else
    read -rp "$q: " ans
  fi
  echo "$ans"
}

# --------------------- classify helpers ---------------------
is_zone_id() { [[ "$1" =~ ^[0-9a-fA-F]{24,64}$ ]]; }
is_domain() { [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; }
is_token_like() { [[ ${#1} -ge 20 && ! $(is_zone_id "$1") && ! $(is_domain "$1") ]]; }
classify() {
  local v="$1"
  if is_zone_id "$v"; then echo "zone"
  elif is_domain "$v"; then echo "domain"
  elif [[ ${#v} -ge 20 ]]; then echo "token"
  else echo "unknown"
  fi
}

# --------------------- parse args ---------------------
args=("$@")
cand_token=""; cand_zone=""; cand_domain=""; cand_sub=""; unknowns=()

for a in "${args[@]}"; do
  cls="$(classify "$a")"
  case "$cls" in
    token) cand_token="$a" ;;
    zone) cand_zone="$a" ;;
    domain) cand_domain="$a" ;;
    *) unknowns+=("$a") ;;
  esac
done

# 如果第四个参数存在，直接当作 subdomain
if [[ ${#args[@]} -ge 4 ]]; then
  cand_sub="${args[3]}"
fi

# 对未知参数尝试分配
for u in "${unknowns[@]}"; do
  [[ -z "$cand_token" ]] && cand_token="$u" && continue
  [[ -z "$cand_zone" ]] && cand_zone="$u" && continue
  [[ -z "$cand_domain" ]] && cand_domain="$u" && continue
  [[ -z "$cand_sub" ]] && cand_sub="$u" && continue
done

# --------------------- prompt for missing / confirm ---------------------
# 先提示前三个参数是否正确
if [[ ${#args[@]} -ge 3 ]]; then
  echo "检测到前三个参数智能识别结果："
  echo "  Token:  ${cand_token:-<未识别>}"
  echo "  ZoneID: ${cand_zone:-<未识别>}"
  echo "  Domain: ${cand_domain:-<未识别>}"
  echo "按 回车 接受识别结果并继续；输入 n 然后回车 以手动重新输入。"
  read -r -n1 -s -p "确认? (Enter=接受, n=重新输入) " CONF
  echo
  if [[ "$CONF" == "n" || "$CONF" == "N" ]]; then
    cand_token="$(prompt "请输入 API Token")"
    cand_zone="$(prompt "请输入 Zone ID")"
    cand_domain="$(prompt "请输入 主域名 (eg. example.com)")"
  fi
fi

# 如果前三个参数缺失，交互提示
[[ -z "$cand_token" ]] && cand_token="$(prompt "请输入 API Token")"
[[ -z "$cand_zone" ]] && cand_zone="$(prompt "请输入 Zone ID")"
[[ -z "$cand_domain" ]] && cand_domain="$(prompt "请输入 主域名 (eg. example.com)")"

# 提示第四个参数（子域名）
[[ -z "$cand_sub" ]] && cand_sub="$(prompt "请输入需要解析的子域名 (eg. node1)")"

# --------------------- final values ---------------------
CF_TOKEN="$cand_token"
ZONE_ID="$cand_zone"
DOMAIN="$cand_domain"
SUBDOMAIN="$cand_sub"
FULL_NAME="${SUBDOMAIN}.${DOMAIN}"

# --------------------- check deps ---------------------
check_deps

# --------------------- get IP ---------------------
IP="$(get_ip)"
if [[ -z "$IP" ]]; then
  IP="$(prompt "无法获取公网 IP，请手动输入 IP")"
  [[ -z "$IP" ]] && echo "未提供 IP，退出" && exit 1
fi

echo "🌐 将把 ${FULL_NAME} 解析到 ${IP} (ZoneID: ${ZONE_ID})"

RECORD_TYPE="A"
[[ "$IP" == *:* ]] && RECORD_TYPE="AAAA"

# --------------------- create or update DNS ---------------------
res="$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${FULL_NAME}" \
  -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json")"
RECORD_ID="$(echo "$res" | jq -r '.result[0].id // empty')"

if [[ -n "$RECORD_ID" ]]; then
  echo "已存在记录 (id: $RECORD_ID)，正在更新..."
  out="$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
    -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" \
    --data "{\"type\":\"${RECORD_TYPE}\",\"name\":\"${FULL_NAME}\",\"content\":\"${IP}\",\"ttl\":120,\"proxied\":false}")"
else
  echo "未发现记录，正在创建..."
  out="$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" \
    --data "{\"type\":\"${RECORD_TYPE}\",\"name\":\"${FULL_NAME}\",\"content\":\"${IP}\",\"ttl\":120,\"proxied\":false}")"
fi

ok="$(echo "$out" | jq -r '.success')"
if [[ "$ok" == "true" ]]; then
  echo "✅ 成功： ${FULL_NAME} → ${IP}"
else
  echo "❌ 操作失败，Cloudflare 返回："
  echo "$out" | jq -C .
  exit 1
fi
