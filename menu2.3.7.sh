#!/bin/bash

CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
ITEMS_PER_PAGE=10

# 颜色定义
C_RESET="\033[0m"
C_BOX="\033[38;5;208m"   # 橘色边框
C_TITLE="\033[1;36m"     # 青蓝标题
C_NUM="\033[1;32m"       # 绿色编号
C_TEXT="\033[1;37m"      # 白色文字

# 框宽控制
term_width=$(tput cols 2>/dev/null || echo 80)
BOX_WIDTH=$((term_width / 2))
[[ $BOX_WIDTH -lt 50 ]] && BOX_WIDTH=50
[[ $BOX_WIDTH -gt 80 ]] && BOX_WIDTH=80

# 加载远程配置
mapfile -t SCRIPTS < <(curl -fsSL "$CONFIG_URL" | sed '/^\s*#/d;/^\s*$/d')
[[ ${#SCRIPTS[@]} -eq 0 ]] && echo "❌ 配置为空" && exit 1

# 去除颜色码计算长度
stripped_length() {
  echo -n "$1" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' | wc -m
}

# 绘制框线
draw_line(){ printf "%b╔%*s╗%b\n" "$C_BOX" $((BOX_WIDTH-2)) "" "$C_RESET" | sed 's/ /═/g'; }
draw_mid(){ printf "%b╠%*s╣%b\n" "$C_BOX" $((BOX_WIDTH-2)) "" "$C_RESET" | sed 's/ /═/g'; }
draw_bot(){ printf "%b╚%*s╝%b\n" "$C_BOX" $((BOX_WIDTH-2)) "" "$C_RESET" | sed 's/ /═/g'; }

# 居中显示
center_text() {
  local text="$1"
  local len=$(stripped_length "$text")
  local pad=$(( (BOX_WIDTH-2 - len)/2 ))
  ((pad<0)) && pad=0
  printf "%b║%*s%s%*s║%b\n" "$C_BOX" "$pad" "" "$text" $((BOX_WIDTH-2-len-pad)) "" "$C_RESET"
}

# 显示菜单
draw_menu() {
  clear
  draw_line
  center_text "${C_TITLE}脚本管理器 (by Moreanp)${C_RESET}"
  draw_mid

  local start=$((PAGE*ITEMS_PER_PAGE))
  local end=$((start+ITEMS_PER_PAGE))
  [[ $end -gt ${#SCRIPTS[@]} ]] && end=${#SCRIPTS[@]}

  for ((i=start;i<end;i++)); do
    name="${SCRIPTS[i]%%|*}"
    num=$((i-start))
    display="${C_NUM}[$num]${C_RESET} ${C_TEXT}${name}${C_RESET}"
    clean_len=$(stripped_length "[$num] $name")
    pad=$((BOX_WIDTH-4-clean_len))
    ((pad<0)) && pad=0
    printf "%b║  %b%*s║%b\n" "$C_BOX" "$display" "$pad" "" "$C_RESET"
  done

  # 空行补齐
  for ((i=end;i<start+ITEMS_PER_PAGE;i++)); do
    printf "%b║%*s║%b\n" "$C_BOX" $((BOX_WIDTH-2)) "" "$C_RESET"
  done

  draw_mid
  center_text "${C_TEXT}[ n ] 下一页   [ b ] 上一页${C_RESET}"
  center_text "${C_TEXT}[ q ] 退出     [ 0-9 ] 选择${C_RESET}"
  draw_bot
}

# 执行选项
run_selected() {
  selected="${SCRIPTS[$((PAGE*ITEMS_PER_PAGE+choice))]}"
  name="${selected%%|*}"
  cmd="${selected#*|}"
  clear
  echo "👉 正在执行 [$name] ..."
  echo "-----------------------------------------"
  bash <(curl -Ls "$cmd")
  echo "-----------------------------------------"
  echo "✅ [$name] 执行完毕，按回车返回菜单..."
  read -r
}

# 主循环
PAGE=0
while true; do
  draw_menu
  read -rp "请选择操作: " choice
  case "$choice" in
    n|N) ((PAGE++)); ((PAGE*ITEMS_PER_PAGE>=${#SCRIPTS[@]})) && PAGE=0 ;;
    b|B) ((PAGE--)); ((PAGE<0)) && PAGE=$(((${#SCRIPTS[@]}-1)/ITEMS_PER_PAGE)) ;;
    q|Q) echo "👋 再见！"; exit 0 ;;
    [0-9])
      total=$((PAGE*ITEMS_PER_PAGE+choice))
      ((total<${#SCRIPTS[@]})) && run_selected
      ;;
  esac
done
