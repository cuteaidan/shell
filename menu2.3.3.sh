#!/usr/bin/env bash
# 终极版 - 精确对齐中英文 + 橘色边框 + 全角填充

set -euo pipefail

CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10
BOX_WIDTH=50

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"
mapfile -t ALL_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")
TOTAL=${#ALL_LINES[@]}
PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))

# 颜色
C_RESET="\033[0m"
C_BOX="\033[38;5;208m"
C_KEY="\033[1;32m"
C_NAME="\033[1;38;5;39m"
C_TITLE="\033[1;38;5;202m"
C_DIV="\033[38;5;240m"

# ====== 工具函数 ======
# 获取显示宽度（中英文混排）
str_width() {
  local s="$1"
  local width=0
  # 用 awk 逐字符判断：ASCII 计 1，其他计 2
  width=$(awk -v s="$s" 'BEGIN {
    n = split(s, a, "")
    w = 0
    for (i=1; i<=n; i++) {
      c = a[i]
      if (c ~ /[ -~]/) w += 1
      else w += 2
    }
    print w
  }')
  echo "$width"
}

# 全角空白填充
pad_to_width() {
  local text="$1"
  local target="$2"
  local width
  width=$(str_width "$text")
  local diff=$((target - width))
  local fill=""
  while (( diff > 0 )); do
    if (( diff >= 2 )); then
      fill+="　"  # 全角空格
      diff=$((diff - 2))
    else
      fill+=" "
      diff=$((diff - 1))
    fi
  done
  printf "%s%s" "$text" "$fill"
}

# 绘制框
draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }

# 绘制文本行（自动对齐）
draw_text() {
  local text="$1"
  local padded
  padded=$(pad_to_width "$text" $((BOX_WIDTH-4)))
  printf "%b║ %s ║%b\n" "$C_BOX" "$padded" "$C_RESET"
}

# 打印菜单页
print_page() {
  local page="$1"
  local start=$(( (page - 1) * PER_PAGE ))
  local end=$(( start + PER_PAGE - 1 ))
  (( end >= TOTAL )) && end=$(( TOTAL - 1 ))

  clear
  draw_line
  draw_text "脚本管理器 (by Moreanp)"
  draw_mid

  for slot in $(seq 0 $((PER_PAGE-1))); do
    local idx=$(( start + slot ))
    if (( idx <= end )); then
      name="${ALL_LINES[idx]%%|*}"
      local line="[$slot] $name"
      local colored="${C_KEY}[${slot}]${C_BOX} ${C_NAME}${name}${C_RESET}"
      local padded
      padded=$(pad_to_width "$line" $((BOX_WIDTH-4)))
      # 手动替换带色版
      printf "%b║ %s%*s║%b\n" "$C_BOX" "$colored" 0 "" "$C_RESET"
    else
      draw_text ""
    fi
  done

  draw_mid
  draw_text "第 $page/$PAGES 页　共 $TOTAL 项"
  draw_text "[ n ] 下一页　[ b ] 上一页"
  draw_text "[ q ] 退出　　[ 0-9 ] 选择"
  draw_bot
}

# 执行选项
run_slot() {
  local page="$1" slot="$2"
  local start=$(( (page - 1) * PER_PAGE ))
  local idx=$(( start + slot ))
  (( idx < 0 || idx >= TOTAL )) && return

  local line="${ALL_LINES[idx]}"
  local name="${line%%|*}"
  local rest="${line#*|}"
  local cmd="${rest%%|*}"
  local args="${rest#*|}"
  [[ "$rest" == "$cmd" ]] && args=""

  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${name}${C_RESET}"
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"

  if [[ "$cmd" =~ ^CMD: ]]; then
    eval "${cmd#CMD:} ${args}"
  elif [[ "$cmd" =~ ^https?:// ]]; then
    bash <(c
