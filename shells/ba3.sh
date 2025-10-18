#!/usr/bin/env bash
# cf_dns_auto.sh
# Minimal + smart param detection
# Usage:
#   bash cf_dns_auto.sh [arg1] [arg2] [arg3]
# Where args may be in any order and represent: <API_TOKEN> <ZONE_ID> <DOMAIN>
set -euo pipefail
stty erase ^? 2>/dev/null || true  # 修复退格键显示 ^H 的问题

# ---------------- helpers ----------------
has_cmd() {
  if command -v "$1" >/dev/null 2>&1; then return 0; fi
  if type "$1" >/dev/null 2>&1; then return 0; fi
  if which "$1" >/dev/null 2>&1; then return 0; fi
  return 1
}

install_pkg() {
  pkg="$1"
  if has_cmd apt; then
    apt update -y && apt install -y "$pkg"
  elif has_cmd yum; then
    yum install -y "$pkg"
  elif has_cmd dnf; then
    dnf install -y "$pkg"
  elif has_cmd apk; then
    apk add --no-cache "$pkg"
  elif has_cmd pacman; then
    pacman -Sy --noconfirm "$pkg"
  else
    echo "无法自动安装 $pkg，请手动安装后重试。"
    exit 1
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
  # 尽量简单可靠
  ip="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(curl -fsS --max-time 8 https://ipv6.icanhazip.com 2>/dev/null || true)"
  fi
  ip="${ip:-}"
  echo "$ip"
}

prompt() {
  # prompt "Question" "default"
  local q="$1"; local def="${2:-}"
  if [[ -n "$def" ]]; then
    read -rp "$q [$def]: " ans
    ans="${ans:-$def}"
  else
    read -rp "$q: " ans
  fi
  echo "$ans"
}

# ---------------- detection logic ----------------
is_zone_id() {
  # Cloudflare Zone ID usually 32 hex characters
  [[ "$1" =~ ^[0-9a-fA-F]{32}$ ]]
}

is_domain() {
  # basic domain check: contains a dot and TLD-like ending (2+ alpha)
  [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]
}

is_token_like() {
  # token is typically long (>=20) and not a zone id nor domain
  local s="$1"
  if is_zone_id "$s" || is_domain "$s"; then
    return 1
  fi
  [[ ${#s} -ge 20 ]]
}

# classify an input string, returns token/zone/domain/unknown
classify() {
  local v="$1"
  if is_zone_id "$v"; then
    echo "zone"
  elif is_domain "$v"; then
    echo "domain"
  elif is_token_like "$v"; then
    echo "token"
  else
    echo "unknown"
  fi
}

# ---------------- parse args ----------------
args=()
for a in "$@"; do args+=("$a"); done

# prepare placeholders
candidate_token=""
candidate_zone=""
candidate_domain=""
unknowns=()

for a in "${args[@]}"; do
  cls="$(classify "$a")"
  case "$cls" in
    token) candidate_token="$a" ;;
    zone)  candidate_zone="$a" ;;
    domain) candidate_domain="$a" ;;
    *) unknowns+=("$a") ;;
  esac
done

# If unknowns remain, try to assign them by heuristic:
# prefer token for long strings, domain for anything with dot, zone if hex-like even if not exact
for u in "${unknowns[@]}"; do
  if [[ -z "$candidate_token" && ${#u} -ge 20 ]]; then
    candidate_token="$u"; continue
  fi
  if [[ -z "$candidate_domain" && "$u" == *.* ]]; then
    candidate_domain="$u"; continue
  fi
  if [[ -z "$candidate_zone" && "$u" =~ ^[0-9a-fA-F]{24,64}$ ]]; then
    candidate_zone="$u"; continue
  fi
  # fallback assign to first empty in order token->zone->domain
  if [[ -z "$candidate_token" ]]; then candidate_token="$u"; continue; fi
  if [[ -z "$candidate_zone" ]]; then candidate_zone="$u"; continue; fi
  if [[ -z "$candidate_domain" ]]; then candidate_domain="$u"; continue; fi
done

# If user passed exactly 3 args and they are already in the correct order token,zone,domain
if [[ ${#args[@]} -eq 3 ]]; then
  arg1="${args[0]}"
  arg2="${args[1]}"
  arg3="${args[2]}"
  if is_token_like "$arg1" && is_zone_id "$arg2" && is_domain "$arg3"; then
    # perfect — use as-is, no confirmation
    CF_TOKEN="$arg1"; ZONE_ID="$arg2"; DOMAIN="$arg3"
  else
    # We have a detected mapping, present to user and ask confirm
    CF_TOKEN="${candidate_token:-}"
    ZONE_ID="${candidate_zone:-}"
    DOMAIN="${candidate_domain:-}"
    echo "检测到你传入了 3 个参数，脚本尝试识别为："
    echo "  Token: ${CF_TOKEN:-<未识别>}"
    echo "  ZoneID: ${ZONE_ID:-<未识别>}"
    echo "  Domain: ${DOMAIN:-<未识别>}"
    echo
    echo "按 回车 接受识别结果并继续；输入 n 然后回车 以手动重新输入三个参数。"
    read -r -n1 -s -p "确认? (Enter=接受, n=重新输入) " CONF
    echo
    if [[ "$CONF" == "n" || "$CONF" == "N" ]]; then
      CF_TOKEN="$(prompt "请输入 API Token (will be hidden if your terminal supports it)" "")"
      ZONE_ID="$(prompt "请输入 Zone ID" "")"
      DOMAIN="$(prompt "请输入 主域名 (eg. example.com)" "")"
    else
      # if any missing after detection, prompt only for missing ones
      if [[ -z "$CF_TOKEN" ]]; then CF_TOKEN="$(prompt "未识别到 Token，请输入 API Token" "")"; fi
      if [[ -z "$ZONE_ID" ]]; then ZONE_ID="$(prompt "未识别到 Zone ID，请输入 Zone ID" "")"; fi
      if [[ -z "$DOMAIN" ]]; then DOMAIN="$(prompt "未识别到 域名，请输入 主域名 (eg. example.com)" "")"; fi
    fi
  fi
else
  # not exactly 3 args — prompt for missing ones, use detected candidates as defaults
  CF_TOKEN="${candidate_token:-}"
  ZONE_ID="${candidate_zone:-}"
  DOMAIN="${candidate_domain:-}"

  if [[ -z "$CF_TOKEN" ]]; then
    CF_TOKEN="$(prompt "请输入 API Token" "")"
  else
    CF_TOKEN="$(prompt "API Token" "$CF_TOKEN")"
  fi

  if [[ -z "$ZONE_ID" ]]; then
    ZONE_ID="$(prompt "请输入 Zone ID" "")"
  else
    ZONE_ID="$(prompt "Zone ID" "$ZONE_ID")"
  fi

  if [[ -z "$DOMAIN" ]]; then
    DOMAIN="$(prompt "请输入 主域名 (eg. example.com)" "")"
  else
    DOMAIN="$(prompt "主域名" "$DOMAIN")"
  fi
fi

# final sanity checks
if [[ -z "$CF_TOKEN" || -z "$ZONE_ID" || -z "$DOMAIN" ]]; then
  echo "参数不足或识别失败，脚本终止。"
  exit 1
fi

# ---------------- do the job ----------------
echo "正在检查依赖并准备运行..."
check_deps

IP="$(get_ip)"
if [[ -z "$IP" ]]; then
  echo "无法自动获取公网 IP，请确保能访问外部网络或手动输入。"
  IP="$(prompt "请输入要解析到的 IP (或回车重试获取)" "")"
  if [[ -z "$IP" ]]; then
    echo "未提供 IP，退出"
    exit 1
  fi
fi

echo "将把 ${DOMAIN} 解析到 ${IP} (Zone: ${ZONE_ID})"

if [[ "$IP" == *:* ]]; then RECORD_TYPE="AAAA"; else RECORD_TYPE="A"; fi

# query existing record for the exact name
res="$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${DOMAIN}" \
  -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json")"

# try to extract record id
RECORD_ID="$(echo "$res" | jq -r '.result[0].id // empty')"

if [[ -n "$RECORD_ID" ]]; then
  echo "已存在记录 (id: $RECORD_ID)，正在更新..."
  out="$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
    -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" \
    --data "{\"type\":\"${RECORD_TYPE}\",\"name\":\"${DOMAIN}\",\"content\":\"${IP}\",\"ttl\":120,\"proxied\":false}")"
else
  echo "未发现记录，正在创建..."
  out="$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" \
    --data "{\"type\":\"${RECORD_TYPE}\",\"name\":\"${DOMAIN}\",\"content\":\"${IP}\",\"ttl\":120,\"proxied\":false}")"
fi

ok="$(echo "$out" | jq -r '.success')"
if [[ "$ok" == "true" ]]; then
  echo "✅ 成功： ${DOMAIN} → ${IP}"
else
  echo "❌ 操作失败，Cloudflare 返回："
  echo "$out" | jq -C .
  exit 1
fi
