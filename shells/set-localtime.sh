#!/usr/bin/env bash
# timezone_manager_pro_final_v2.sh
# 🌍 全球时区交互管理脚本（最终优化版）
# 功能：颜色标记、自动检测、搜索、分页、退格支持、去重、智能选择
#       + 时间准确性表格显示 + 自动校对系统时间

set -euo pipefail

# ====== 彩色定义 ======
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# ====== 获取系统时区文件路径 ======
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

# ====== 检查时间准确性 ======
check_time_accuracy_table() {
  local sys_utc_ts=$(date -u +%s)
  local servers=("Aliyun:ntp.aliyun.com" "Cloudflare:time.cloudflare.com" "Bing:time.windows.com" "Apple:time.apple.com")
  local labels=()
  local diffs=()
  
  for s in "${servers[@]}"; do
    label="${s%%:*}"
    host="${s##*:}"
    labels+=("$label")
    net_date=$(curl -fsI --max-time 2 "https://$host" 2>/dev/null | grep -i '^Date:' | cut -d' ' -f2-)
    if [[ -n "$net_date" ]]; then
      net_ts=$(date -d "$net_date" +%s)
      diff=$(( net_ts - sys_utc_ts ))
      sign=""
      (( diff > 0 )) && sign="+"
      diffs+=("${sign}${diff}s")
    else
      diffs+=("N/A")
    fi
  done

  # 打印表格
  printf "%-12s" "${labels[@]}"
  echo
  printf "%-12s" "${diffs[@]}"
  echo
  echo "----------------------------------------"
  echo "输入 0 自动校对系统时间（需 sudo）"
}

# ====== 初始化数据 ======
detected_tz=$(detect_timezone)
mapfile -t all_timezones < <(get_all_timezones)

# 去重并保证 UTC 第1位、上海第2位、检测到的时区第3位
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

add_unique "Etc/UTC"          # 第1位
add_unique "Asia/Shanghai"     # 第2位
add_unique "$detected_tz"      # 第3位
for tz in "${all_timezones[@]}"; do
  add_unique "$tz"
done

timezones=("${unique_timezones[@]}")

# ====== 分页显示 ======
show_page() {
  local page=$1
  local per_page=5
  local total=${#timezones[@]}
  local start=$(( (page - 1) * per_page ))
  local end=$(( start + per_page ))
  (( end > total )) && end=$total

  clear
  check_time_accuracy_table
  echo "========= 🌏 全局时区选择（第 ${page} 页，共 $(( (total + per_page - 1) / per_page )) 页） ========="
  for ((i=start; i<end; i++)); do
    local tz="${timezones[$i]}"
    local idx=$((i+1))
    if [[ "$tz" == "Etc/UTC" ]]; then
      echo -e "[$idx] ${RED}$tz${RESET}"
    elif [[ "$tz" == "Asia/Shanghai" ]]; then
      echo -e "[$idx] ${GREEN}$tz${RESET}"
    elif [[ "$tz" == "$detected_tz" ]]; then
      echo -e "[$idx] ${YELLOW}$tz (检测到的时区)${RESET}"
    else
      echo "[$idx] $tz"
    fi
  done
  echo "----------------------------------------"
  echo "输入编号选择 / 输入关键字搜索 / n 下一页 / b 上一页 / q 退出"
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

# ====== 主循环 ======
page=1
while true; do
  show_page "$page"
  stty erase ^H
  read -r -e -p "> " input
  case "$input" in
    0)
      read -r -p "是否将系统时间校对为网络时间？(Y/n) " confirm
      [[ "$confirm" =~ ^[Yy]$ ]] || continue
      net_date=$(curl -fsI --max-time 2 https://google.com 2>/dev/null \
                 | grep -i '^Date:' | cut -d' ' -f2-)
      if [[ -n "$net_date" ]]; then
        sudo date -s "$net_date"
        echo "✅ 系统时间已校对为 $net_date"
        sleep 1
      else
        echo "❌ 无法获取网络时间"
        sleep 1
      fi
      continue
      ;;
    [0-9]*)
      idx=$((input - 1))
      if (( idx >= 0 && idx < ${#timezones[@]} )); then
        apply_timezone "${timezones[$idx]}"
        break
      else
        echo "❌ 无效的编号"
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
        read -r -e -p "> " sub_input
        [[ "$sub_input" == "q" ]] && continue
        if [[ "$sub_input" =~ ^[0-9]+$ ]]; then
          idx=$((sub_input - 1))
          if (( idx >= 0 && idx < ${#timezones[@]} )); then
            apply_timezone "${timezones[$idx]}"
            break
          else
            echo "❌ 无效的编号"
          fi
        fi
      fi
      ;;
  esac
done
