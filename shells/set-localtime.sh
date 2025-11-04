#!/usr/bin/env bash
# timezone_manager_final.sh
# 🌍 全球时区交互管理脚本（最终稳定版）
# 功能：颜色标记、自动检测、搜索、分页、无 ^H、去重、智能选择、时间准确性检测与校对

set -euo pipefail

# ====== 彩色定义 ======
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# ====== 时区路径 ======
ZONEINFO_DIR="/usr/share/zoneinfo"

# ====== 自动检测本机 IP 时区 ======
detect_timezone() {
  curl -fsSL --max-time 3 https://ipapi.co/timezone 2>/dev/null || echo "Unknown"
}

# ====== 获取所有时区 ======
get_all_timezones() {
  find "$ZONEINFO_DIR" -type f \
    | grep -Ev 'posix|right|Etc/UTC|zoneinfo/UTC|SystemV|Factory' \
    | sed "s|$ZONEINFO_DIR/||" \
    | sort
}

# ====== 初始化数据 ======
detected_tz=$(detect_timezone || echo "Unknown")
mapfile -t all_timezones < <(get_all_timezones || true)

unique_timezones=()
added=()

add_unique() {
  local tz="$1"
  [[ -z "$tz" || "$tz" == "Unknown" ]] && return
  if [[ ! " ${added[*]} " =~ " ${tz} " && -f "$ZONEINFO_DIR/$tz" ]]; then
    unique_timezones+=("$tz")
    added+=("$tz")
  fi
}

# 优先顺序：UTC → 上海 → 检测到的时区 → 其他
add_unique "Etc/UTC"
add_unique "Asia/Shanghai"
add_unique "$detected_tz"
for tz in "${all_timezones[@]}"; do
  add_unique "$tz"
done

timezones=("${unique_timezones[@]}")

# ====== 时间准确性检测 ======
NTP_SERVERS=(
  "time.aliyun.com"
  "time.cloudflare.com"
  "time.apple.com"
  "time.windows.com"
  "time.google.com"
)
check_time_accuracy() {
  declare -A offsets
  local sys_epoch=$(date +%s)
  for server in "${NTP_SERVERS[@]}"; do
    local ntp_time
    ntp_time=$(ntpdate -q "$server" 2>/dev/null | awk '/offset/ {print $10}' | tail -n1)
    offsets["$server"]="${ntp_time:-N/A}"
  done
  echo "${offsets[@]}"
  printf "%-15s" "${!offsets[@]}"
  echo
  for server in "${!offsets[@]}"; do
    local val="${offsets[$server]}"
    if [[ "$val" != "N/A" ]]; then
      printf "%-15s" "$(printf "%+.2fs" "$val")"
    else
      printf "%-15s" "N/A"
    fi
  done
  echo
}

# ====== 分页显示 ======
show_page() {
  local page=$1
  local per_page=5
  local total=${#timezones[@]}
  local start=$(( (page - 1) * per_page ))
  local end=$(( start + per_page ))
  (( end > total )) && end=$total

  clear
  echo "========= ⏱️ 当前时间准确性（偏差） ========="
  check_time_accuracy
  echo "----------------------------------------"
  echo "========= 🌏 全局时区选择（第 ${page} 页，共 $(( (total + per_page - 1) / per_page )) 页） ========="
  for ((i=start; i<end; i++)); do
    local tz="${timezones[$i]}"
    local idx=$((i+1))
    if [[ "$tz" == "Etc/UTC" ]]; then
      echo -e "[$idx] ${RED}${tz}${RESET}"
    elif [[ "$tz" == "Asia/Shanghai" ]]; then
      echo -e "[$idx] ${GREEN}${tz}${RESET}"
    elif [[ "$tz" == "$detected_tz" ]]; then
      echo -e "[$idx] ${YELLOW}${tz} (检测到的时区)${RESET}"
    else
      echo "[$idx] $tz"
    fi
  done
  echo "----------------------------------------"
  echo "输入编号选择 / 输入关键字搜索 / 0 校对时间 / n 下一页 / b 上一页 / q 退出"
}

# ====== 搜索功能 ======
search_timezone() {
  local query="$1"
  clear
  echo "🔍 搜索结果：$query"
  local found=0
  for i in "${!timezones[@]}"; do
    if [[ "${timezones[$i],,}" == *"${query,,}"* ]]; then
      echo "[$((i+1))] ${timezones[$i]}"
      found=1
    fi
  done
  [[ $found -eq 0 ]] && echo "未找到匹配的时区"
  echo "----------------------------------------"
  echo "输入编号选择 / q 返回列表"
}

# ====== 应用时区 ======
apply_timezone() {
  local tz="$1"
  if [[ -f "$ZONEINFO_DIR/$tz" ]]; then
    sudo ln -sf "$ZONEINFO_DIR/$tz" /etc/localtime
    echo -e "✅ 已将系统时区设置为 ${GREEN}$tz${RESET}"
    echo -e "🕒 当前时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
  else
    echo "❌ 时区文件不存在：$tz"
  fi
}

# ====== 校对时间 ======
sync_time() {
  read -r -p "是否将系统时间同步到网络时间? (Y/n) " yn
  yn=${yn:-Y}
  if [[ "$yn" =~ ^[Yy] ]]; then
    sudo ntpdate -u "${NTP_SERVERS[@]}" && echo "✅ 已同步系统时间"
  else
    echo "已取消"
  fi
}

# ====== 主循环 ======
page=1
while true; do
  show_page "$page"
  # 支持删除键，不显示 ^H
  IFS= read -r -e -p "> " input || input=""
  input="${input//$'\x7f'/}"  # 删除键处理

  case "$input" in
    0)
      sync_time
      ;;
    [0-9]*)
      idx=$((input - 1))
      if (( idx >= 0 && idx < ${#timezones[@]} )); then
        apply_timezone "${timezones[$idx]}"
        break
      else
        echo "❌ 无效编号"
      fi
      ;;
    n)
      (( page < ((${#timezones[@]} + 4) / 5) )) && ((page++))
      ;;
    b)
      (( page > 1 )) && ((page--))
      ;;
    q)
      echo "已退出。"
      exit 0
      ;;
    *)
      if [[ -n "$input" ]]; then
        search_timezone "$input"
        IFS= read -r -e -p "> " sub_input || sub_input=""
        sub_input="${sub_input//$'\x7f'/}"
        [[ "$sub_input" == "q" ]] && continue
        if [[ "$sub_input" =~ ^[0-9]+$ ]]; then
          idx=$((sub_input - 1))
          if (( idx >= 0 && idx < ${#timezones[@]} )); then
            apply_timezone "${timezones[$idx]}"
            break
          else
            echo "❌ 无效编号"
          fi
        fi
      fi
      ;;
  esac
done
