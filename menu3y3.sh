#!/usr/bin/env bash
# 精修稳定版：防卡死输入 + 紧凑窗口 + 高饱和橘色边框
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/menu.sh)

set -o errexit
set -o pipefail
set -o nounset

# ============== 配置 ==============
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10
BOX_WIDTH=50   # 固定宽度
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

# ====== 色彩定义（用 $'...' 解析 ANSI 转义） ======
C_RESET=$'\033[0m'
C_BOX=$'\033[38;5;208m'
C_TITLE=$'\033[1;38;5;202m'
C_KEY=$'\033[1;32m'
C_NAME=$'\033[1;38;5;39m'
C_DIV=$'\033[38;5;240m'
C_HINT=$'\033[0;37m'
# =====================

# 绘制框架
draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }

# 绘制文本行，自动计算全半角宽度，ANSI 颜色不影响对齐
draw_text() {
  local text="$1"
  local clean_text len=0 i char code

  # 去掉 ANSI 颜色码计算长度
  clean_text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')

  len=0
  for ((i=0; i<${#clean_text}; i++)); do
    char="${clean_text:i:1}"
    code=$(printf '%d' "'$char")
    # 中文/全角判断：CJK 常用中文 19968-40959 (十进制)
    if (( code >= 19968 && code <= 40959 )); then
      len=$((len + 2))
    else
      len=$((len + 1))
    fi
  done

  local padding=$((BOX_WIDTH - len - 2))  # 2 = 左右边框
  ((padding < 0)) && padding=0

  # printf 输出 ANSI 颜色原样显示
  printf "%b║%s%*s║%b\n" "$C_BOX" "$text" "$padding" "" "$C_BOX"
}

# 绘制菜单页
print_page() {
  local page="$1"
  local start=$(( (page - 1) * PER_PAGE ))
  local end=$(( start + PER_PAGE - 1 ))
  (( end >= TOTAL )) && end=$(( TOTAL - 1 ))

  clear
  draw_line
  local title="脚本管理器 (by Moreanp)"
  draw_text "$(printf '%*s%s%*s' $(((BOX_WIDTH - ${#title})/2)) '' "$C_TITLE$title$C_RESET" $(((BOX_WIDTH - ${#title})/2 - 2)) '')"
  draw_mid

  # 序号行
  for slot in $(seq 0 $((PER_PAGE-1))); do
    idx=$(( start + slot ))
    if (( idx <= end )); then
      name="${ALL_LINES[idx]%%|*}"
      line="$C_KEY[$slot] $C_NAME$name$C_RESET"
      draw_text " $line"
    else
      draw_text ""
    fi
  done

  draw_mid
  draw_text " 第 $page/$PAGES 页   共 $TOTAL 项"
  draw_text " [ n ] 下一页   [ b ] 上一页"
  draw_text " [ q ] 退出     [ 0-9 ] 选择"
  draw_bot
}

# 执行选项
run_slot() {
  local page="$1" slot="$2"
  local start=$(( (page - 1) * PER_PAGE ))
  local idx=$(( start + slot ))
  (( idx < 0 || idx >= TOTAL )) && { echo "❌ 无效选项"; read -rp "按回车返回..." _; return; }

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
  read -rp "请输入选项 (0-9 / n / b / q): " key || true
  case "$key" in
    [0-9]) run_slot "$page" "$key" ;;
    n|N) ((page < PAGES)) && ((page++)) || { echo "已是最后一页"; read -rp "按回车返回..." _; } ;;
    b|B) ((page > 1)) && ((page--)) || { echo "已是第一页"; read -rp "按回车返回..." _; } ;;
    q|Q) clear; echo "👋 再见！"; exit 0 ;;
    *) echo "⚠️ 无效输入，请重试"; sleep 0.8 ;;
  esac
done
