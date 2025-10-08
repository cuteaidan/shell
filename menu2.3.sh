#!/usr/bin/env bash
# 彩色带边框分页脚本管理器
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/menu.sh)

set -o errexit
set -o pipefail
set -o nounset

# ============== 配置 ==============
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10
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
C_TITLE_BG="\033[48;5;17;1m"
C_TITLE_FG="\033[1;37m"
C_KEY="\033[1;32m"        # 明亮绿色
C_NAME="\033[1;38;5;45m"  # 明亮蓝色（高对比）
C_DIV="\033[38;5;241m"
C_HINT="\033[0;37m"
C_BOX="\033[38;5;240m"
# =====================

# 打印水平线（根据终端宽度自动）
term_width=$(tput cols 2>/dev/null || echo 70)
if (( term_width < 70 )); then term_width=70; fi
line=$(printf '═%.0s' $(seq 1 $((term_width-2))))

draw_top()  { printf "%b╔%s╗%b\n" "$C_BOX" "$line" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$line" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$line" "$C_RESET"; }
draw_blank(){ printf "%b║%-*s║%b\n" "$C_BOX" $((term_width-2)) " " "$C_RESET"; }
draw_text() { local text="$1"; printf "%b║ %-*s║%b\n" "$C_BOX" $((term_width-3)) "$text" "$C_RESET"; }

# 绘制一页菜单
print_page() {
  local page="$1"
  local start=$(( (page - 1) * PER_PAGE ))
  local end=$(( start + PER_PAGE - 1 ))
  (( end >= TOTAL )) && end=$(( TOTAL - 1 ))

  clear
  draw_top
  title="脚本管理器 (by Moreanp)"
  center=$(( (term_width - ${#title}) / 2 ))
  printf "%b║%*s%s%*s║%b\n" "$C_BOX" "$center" "" "$title" "$((term_width - center - ${#title} - 2))" "" "$C_RESET"
  draw_mid

  for slot in $(seq 0 $((PER_PAGE-1))); do
    idx=$(( start + slot ))
    if (( idx <= end )); then
      name="${ALL_LINES[idx]%%|*}"
      printf "%b║%b[%s]%b  %-*s║%b\n" \
        "$C_BOX" "$C_KEY" "$slot" "$C_BOX" $((term_width-9)) "$(echo -e "$C_NAME$name$C_RESET")" "$C_RESET"
    else
      draw_blank
    fi
  done

  draw_mid
  page_info="第 $page/$PAGES 页   共 $TOTAL 项"
  draw_text "$page_info"
  draw_text "[ n ] 下一页   [ b ] 上一页"
  draw_text "[ q ] 退出     [ 0-9 ] 选择当前页对应项"
  draw_bot
}

# 执行选中项
run_slot() {
  local page="$1" slot="$2"
  local start=$(( (page - 1) * PER_PAGE ))
  local idx=$(( start + slot ))
  (( idx < 0 || idx >= TOTAL )) && { echo "❌ 无效选项"; return; }

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

# 主循环
page=1
while true; do
  print_page "$page"
  read -rn1 -p "请选择 (0-9 / n / b / q): " key || true
  echo
  case "$key" in
    [0-9]) run_slot "$page" "$key" ;;
    n) ((page < PAGES)) && ((page++)) || echo "已是最后一页" ;;
    b) ((page > 1)) && ((page--)) || echo "已是第一页" ;;
    q) clear; echo "👋 再见！"; exit 0 ;;
    *) ;;
  esac
done
