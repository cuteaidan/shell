#!/usr/bin/env bash
# 完整最终版菜单脚本（修复ANSI颜色显示、边框、对齐、美化）

set -o errexit
set -o pipefail
set -o nounset

# ============== 配置 ==============
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10
BOX_WIDTH=50
LEFT_INDENT="        "  # 左侧缩进
# =================================

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

# 下载配置文件
if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
  echo "❌ 无法下载配置文件: $CONFIG_URL"
  exit 1
fi

mapfile -t ALL_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")
TOTAL=${#ALL_LINES[@]}
PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))

# ====== 色彩定义 ======
C_RESET="\033[0m"
C_BOX="\033[38;5;124m"      # 深红色边框
C_TITLE="\033[1;38;5;202m"
C_KEY="\033[1;32m"          # 亮绿色序号
C_NAME="\033[1;38;5;39m"    # 亮蓝色脚本名
C_DIV="\033[38;5;240m"
C_HINT="\033[1;32m"          # 输入提示绿色
# =====================

# ====== 宽度计算函数（支持中文/全角） ======
str_width() {
  local text="$1"
  # 去掉 ANSI 颜色码
  text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
  local len=0 char code
  for ((i=0;i<${#text};i++)); do
    char="${text:i:1}"
    code=$(printf '%d' "'$char")
    # 中文/全角/日文假名/全角标点
    if (( (code>=19968 && code<=40959) || (code>=65281 && code<=65519) || (code>=12288 && code<=12351) || (code>=12352 && code<=12543) )); then
      len=$((len+2))
    else
      len=$((len+1))
    fi
  done
  echo "$len"
}

# ====== 绘制框架 ======
draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }

# ====== 绘制文本行 ======
draw_text() {
  local text="$1"
  text="${text//$'\n'/}"
  local width=$(str_width "$text")
  local padding=$((BOX_WIDTH - width - ${#LEFT_INDENT} - 2))
  ((padding<0)) && padding=0
  printf "%b║%s%s%*s║%b\n" "$C_BOX" "$LEFT_INDENT" "$text" "$padding" "" "$C_BOX"
}

# ====== 绘制标题 ======
draw_title() {
  local title="$1"
  local width=$(str_width "$title")
  local left_pad=$(( (BOX_WIDTH - width - 2)/2 ))
  local right_pad=$((BOX_WIDTH - width - left_pad - 2))
  printf "%b║%*s%b%s%b%*s║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX"
}

# ====== 绘制菜单页 ======
print_page() {
  local page="$1"
  local start=$(( (page-1)*PER_PAGE ))
  local end=$(( start+PER_PAGE-1 ))
  ((end>=TOTAL)) && end=$((TOTAL-1))

  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp)"
  draw_mid

  for slot in $(seq 0 $((PER_PAGE-1))); do
    idx=$((start+slot))
    if ((idx<=end)); then
      name="${ALL_LINES[idx]%%|*}"
      local item_text="${C_KEY}[$slot]${C_RESET} ${C_NAME}${name}${C_RESET}"
      draw_text "$item_text"
    else
      draw_text ""
    fi
  done

  draw_mid
  draw_text "第 $page/$PAGES 页   共 $TOTAL 项"
  draw_text "[ n ] 下一页   [ b ] 上一页"
  draw_text "[ q ] 退出     [ 0-9 ] 选择"
  draw_bot
}

# ====== 执行选项 ======
run_slot() {
  local page="$1" slot="$2"
  local start=$(( (page-1)*PER_PAGE ))
  local idx=$((start+slot))
  ((idx<0||idx>=TOTAL)) && { echo "❌ 无效选项"; read -rp "按回车返回..." _; return; }

  selected="${ALL_LINES[idx]}"
  name="${selected%%|*}"
  rest="${selected#*|}"
  cmd="${rest%%|*}"
  args=""
  [[ "$rest" == *"|"* ]] && args="${rest#*|}"

  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${name}${C_RESET}"
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"

  if [[ "$cmd" =~ ^CMD: ]]; then
    eval "${cmd#CMD:} ${args}"
  elif [[ "$cmd" =~ ^https?:// ]]; then
    bash <(curl -fsSL "${cmd}") ${args:+$args}
  else
    eval "$cmd ${args}"
  fi

  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  read -rp $'按回车返回菜单...' _
}

# ====== 主循环 ======
page=1
while true; do
  print_page "$page"
  echo -ne "${C_HINT}请输入选项 (0-9 / n / b / q): ${C_RESET}"
  read -r key || true
  case "$key" in
    [0-9]) run_slot "$page" "$key" ;;
    n|N) ((page<PAGES)) && ((page++)) || { echo "已是最后一页"; read -rp "按回车返回..." _; } ;;
    b|B) ((page>1)) && ((page--)) || { echo "已是第一页"; read -rp "按回车返回..." _; } ;;
    q|Q) clear; echo "👋 再见！"; exit 0 ;;
    *) echo "⚠️ 无效输入，请重试"; sleep 0.8 ;;
  esac
done
