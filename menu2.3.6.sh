#!/bin/bash
# ============================================
#  彩色多页菜单管理器 (Final v2 Pro)
#  作者: Moreanp
# ============================================

CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
ITEMS_PER_PAGE=10

# ========== 颜色定义 ==========
C_RESET="\033[0m"
C_BOX="\033[38;5;208m"   # 橘色边框
C_TITLE="\033[1;36m"     # 青蓝标题
C_NUM="\033[1;32m"       # 绿色编号
C_TEXT="\033[1;37m"      # 白色文字

# ========== 计算宽度 ==========
term_width=$(tput cols 2>/dev/null || echo 80)
BOX_WIDTH=$((term_width / 2))
[[ $BOX_WIDTH -lt 50 ]] && BOX_WIDTH=50
[[ $BOX_WIDTH -gt 80 ]] && BOX_WIDTH=80

# ========== 加载远程配置 ==========
load_config() {
  mapfile -t SCRIPTS < <(curl -fsSL "$CONFIG_URL" | sed '/^\s*#/d;/^\s*$/d')
  if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
    echo "❌ 无法加载配置或配置为空"
    exit 1
  fi
}

# ========== 绘制框线 ==========
draw_line() {
  printf "%b╔%*s╗%b\n" "$C_BOX" $((BOX_WIDTH - 2)) "" "$C_RESET" | sed "s/ /═/g"
}
draw_mid() {
  printf "%b╠%*s╣%b\n" "$C_BOX" $((BOX_WIDTH - 2)) "" "$C_RESET" | sed "s/ /═/g"
}
draw_bot() {
  printf "%b╚%*s╝%b\n" "$C_BOX" $((BOX_WIDTH - 2)) "" "$C_RESET" | sed "s/ /═/g"
}

# ========== 去除颜色码并计算宽度 ==========
stripped_length() {
  local input="$1"
  echo -n "$input" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' | wc -m
}

# ========== 居中显示 ==========
center_text() {
  local text="$1"
  local clean_len
  clean_len=$(stripped_length "$text")
  local padding=$(( (BOX_WIDTH - 2 - clean_len) / 2 ))
  ((padding < 0)) && padding=0
  printf "%b║%*s%s%*s║%b\n" "$C_BOX" "$padding" "" "$text" $((BOX_WIDTH - 2 - clean_len - padding)) "" "$C_RESET"
}

# ========== 绘制菜单 ==========
draw_menu() {
  clear
  draw_line
  center_text "${C_TITLE}脚本管理器 (by Moreanp)${C_RESET}"
  draw_mid

  local start=$((PAGE * ITEMS_PER_PAGE))
  local end=$((start + ITEMS_PER_PAGE))
  [[ $end -gt ${#SCRIPTS[@]} ]] && end=${#SCRIPTS[@]}

  for ((i = start; i < end; i++)); do
    name="${SCRIPTS[i]%%|*}"
    num=$((i - start))
    display="${C_NUM}[$num]${C_RESET} ${C_TEXT}${name}${C_RESET}"

    clean_len=$(stripped_length "[$num] $name")
    padding=$((BOX_WIDTH - 4 - clean_len))
    ((padding < 0)) && padding=0

    printf "%b║  %s%*s║%b\n" "$C_BOX" "$display" "$padding" "" "$C_RESET"
  done

  # 空行补齐
  for ((i = end; i < start + ITEMS_PER_PAGE; i++)); do
    printf "%b║%*s║%b\n" "$C_BOX" $((BOX_WIDTH - 2)) "" "$C_RESET"
  done

  draw_mid
  center_text "${C_TEXT}[ n ] 下一页   [ b ] 上一页${C_RESET}"
  center_text "${C_TEXT}[ q ] 退出     [ 0-9 ] 选择${C_RESET}"
  draw_bot
}

# ========== 执行选项 ==========
run_selected() {
  selected="${SCRIPTS[$((PAGE * ITEMS_PER_PAGE + choice))]}"
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

# ========== 主逻辑 ==========
load_config
PAGE=0

while true; do
  draw_menu
  read -rp "请选择操作: " choice
  case "$choice" in
    n|N)
      ((PAGE++))
      ((PAGE * ITEMS_PER_PAGE >= ${#SCRIPTS[@]})) && PAGE=0
      ;;
    b|B)
      ((PAGE--))
      ((PAGE < 0)) && PAGE=$(((${#SCRIPTS[@]} - 1) / ITEMS_PER_PAGE))
      ;;
    q|Q)
      echo "👋 再见！"
      exit 0
      ;;
    [0-9])
      total=$((PAGE * ITEMS_PER_PAGE + choice))
      if (( total < ${#SCRIPTS[@]} )); then
        run_selected
      fi
      ;;
  esac
done
