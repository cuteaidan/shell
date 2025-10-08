#!/bin/bash
# =============================
#  彩色多页菜单管理器 (Final Pro)
#  作者: Moreanp
# =============================

CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
ITEMS_PER_PAGE=10

# --- 加载远程配置 ---
load_config() {
  mapfile -t SCRIPTS < <(curl -fsSL "$CONFIG_URL" | sed '/^\s*#/d;/^\s*$/d')
  if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
    echo "❌ 无法加载配置或配置为空"
    exit 1
  fi
}

# --- 绘制边框 ---
C_RESET="\033[0m"
C_BOX="\033[38;5;208m"   # 高饱和橘色
C_TITLE="\033[1;36m"     # 明亮蓝
C_NUM="\033[1;32m"       # 绿色编号
C_TEXT="\033[1;37m"      # 白色文字

# 自动计算终端宽度 & 框宽
term_width=$(tput cols 2>/dev/null || echo 80)
BOX_WIDTH=$((term_width/2))
[[ $BOX_WIDTH -lt 50 ]] && BOX_WIDTH=50
[[ $BOX_WIDTH -gt 80 ]] && BOX_WIDTH=80

draw_line() {
  local line; line=$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))
  printf "%b╔%s╗%b\n" "$C_BOX" "$line" "$C_RESET"
}
draw_mid() {
  local line; line=$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))
  printf "%b╠%s╣%b\n" "$C_BOX" "$line" "$C_RESET"
}
draw_bot() {
  local line; line=$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))
  printf "%b╚%s╝%b\n" "$C_BOX" "$line" "$C_RESET"
}

# --- 输出居中内容 ---
center_text() {
  local text="$1"
  local padding=$(( (BOX_WIDTH - 2 - ${#text}) / 2 ))
  [[ $padding -lt 0 ]] && padding=0
  printf "%b║%*s%s%*s║%b\n" "$C_BOX" $padding "" "$text" $((BOX_WIDTH-2-padding-${#text})) "" "$C_RESET"
}

# --- 绘制菜单 ---
draw_menu() {
  clear
  draw_line
  center_text "脚本管理器 (by Moreanp)"
  draw_mid
  local start=$((PAGE*ITEMS_PER_PAGE))
  local end=$((start+ITEMS_PER_PAGE))
  [[ $end -gt ${#SCRIPTS[@]} ]] && end=${#SCRIPTS[@]}

  for ((i=start; i<end; i++)); do
    name="${SCRIPTS[i]%%|*}"
    num=$((i-start))
    # 使用全角空格填充对齐
    display="[$num] ${name}"
    local padding=$((BOX_WIDTH-4-${#display}))
    [[ $padding -lt 0 ]] && padding=0
    pad=$(printf '　%.0s' $(seq 1 $padding))
    printf "%b║  %b%s%b%s║%b\n" "$C_BOX" "$C_NUM" "[$num]" "$C_TEXT" " ${name}${pad}" "$C_RESET"
  done

  # 空行填充使边框对齐
  for ((i=end; i<start+ITEMS_PER_PAGE; i++)); do
    pad=$(printf '　%.0s' $(seq 1 $((BOX_WIDTH-4))))
    printf "%b║%s║%b\n" "$C_BOX" "$pad" "$C_RESET"
  done
  draw_mid
  center_text "[ n ] 下一页   [ b ] 上一页"
  center_text("[ q ] 退出     [ 0-9 ] 选择")
  draw_bot
}

# --- 主逻辑 ---
run_selected() {
  selected="${SCRIPTS[$((PAGE*ITEMS_PER_PAGE+choice))]}"
  name="${selected%%|*}"
  cmd="${selected#*|}"
  clear
  echo "👉 正在执行 [$name] ..."
  echo "-----------------------------------------"
  if [[ "$cmd" =~ ^CMD: ]]; then
    eval "${cmd:4}"
  else
    bash <(curl -Ls "$cmd")
  fi
  echo "-----------------------------------------"
  echo "✅ [$name] 执行完毕，按回车返回菜单..."
  read -r
}

load_config
PAGE=0

while true; do
  draw_menu
  read -rp "请选择操作: " choice

  case "$choice" in
    n|N)
      ((PAGE++))
      ((PAGE*ITEMS_PER_PAGE >= ${#SCRIPTS[@]})) && PAGE=0
      ;;
    b|B)
      ((PAGE--))
      ((PAGE < 0)) && PAGE=$(( (${#SCRIPTS[@]}-1)/ITEMS_PER_PAGE ))
      ;;
    q|Q)
      echo "👋 再见！"
      exit 0
      ;;
    [0-9])
      total_items=$((PAGE*ITEMS_PER_PAGE+choice))
      if (( total_items < ${#SCRIPTS[@]} )); then
        run_selected
      fi
      ;;
    *)
      ;;
  esac
done
