#!/usr/bin/env bash
# menu_manager_v2_noemoji_fixed2.sh
# 支持：无限层级目录（两个空格为一级） + 兼容旧 bash + 跨目录模糊搜索 + 修复多层级返回
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权 ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m!  检测到当前用户不是 root。\033[0m"
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[1;31mX 系统未安装 sudo，请使用 root 用户运行本脚本。\033[0m"
    exit 1
  fi
  echo -e "\033[1;32m🔑  请输入当前用户的密码以获取管理员权限（sudo）...\033[0m"
  exec sudo -E bash "$0" "$@"
  exit $?
fi

# ====== 配置部分 ======
CONFIG_URL="${CONFIG_URL:-https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts1.conf}"
PER_PAGE=10
BOX_WIDTH=41
LEFT_INDENT="        "

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

# 下载配置
if command -v curl >/dev/null 2>&1; then
  if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
    echo -e "\033[1;31mX curl 下载配置失败\033[0m"
    if command -v wget >/dev/null 2>&1; then
      wget -qO "$TMP_CONF" "$CONFIG_URL" || { echo "X wget 也失败"; exit 1; }
    else
      exit 1
    fi
  fi
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP_CONF" "$CONFIG_URL" || { echo "X wget 下载失败"; exit 1; }
else
  echo "X 系统未安装 curl 或 wget"
  exit 1
fi

# ====== 色彩定义 ======
C_RESET="\033[0m"
C_BOX="\033[1;38;5;202m"
C_TITLE="\033[1;38;5;220m"
C_KEY="\033[1;32m"
C_NAME="\033[1;38;5;39m"
C_HINT="\033[1;32m"
C_DIV="\033[38;5;240m"
C_EXEC="\033[1;32m"
C_WARN="\033[1;33m"
C_ERROR="\033[1;31m"
C_RUN="\033[1;34m"

# ====== 宽度计算 ======
str_width() {
  local text="$1"
  text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
  local len=0 i ch code
  for ((i=0;i<${#text};i++)); do
    ch="${text:i:1}"
    code=$(printf '%d' "'$ch" 2>/dev/null || true)
    if [[ -n "$code" ]] && (( (code>=19968 && code<=40959) || (code>=65281 && code<=65519) || (code>=12288 && code<=12543) )); then
      len=$((len+2))
    else
      len=$((len+1))
    fi
  done
  echo "$len"
}

# ====== 绘制边框 ======
draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }

draw_text() {
  local text="$1"
  local width=$(str_width "$text")
  local padding=$((BOX_WIDTH - width - ${#LEFT_INDENT} - 2))
  ((padding<0)) && padding=0
  printf "%b║%s%b%*s%b║%b\n" "$C_BOX" "$LEFT_INDENT" "$text" "$padding" "" "$C_BOX" "$C_RESET"
}

draw_title() {
  local title="$1"
  local width=$(str_width "$title")
  local left_pad=$(( (BOX_WIDTH - width - 2)/2 ))
  local right_pad=$((BOX_WIDTH - width - left_pad - 2))
  [ $left_pad -lt 0 ] && left_pad=0
  [ $right_pad -lt 0 ] && right_pad=0
  printf "%b║%*s%b%s%b%*s%b║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX" "$C_RESET"
}

# ====== 解析配置 ======
declare -A CHILDREN
declare -A ITEMS
declare -a ROOT_ITEMS
path_stack=()

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  [[ -z "$raw_line" || "$raw_line" =~ ^[[:space:]]*$ ]] && continue
  raw_line="${raw_line%$'\r'}"
  stripped="${raw_line#"${raw_line%%[![:space:]]*}"}"
  [[ "$stripped" =~ ^# ]] && continue
  lead_len=$(( ${#raw_line} - ${#stripped} ))
  indent=$(( lead_len / 2 ))

  if [[ "$stripped" =~ ^\[.*\]$ ]]; then
    dir="${stripped#[}"
    dir="${dir%]}"
    while ((${#path_stack[@]} > indent)); do unset 'path_stack[-1]'; done
    path_stack+=("$dir")
    current_path="ROOT"
    for d in "${path_stack[@]}"; do current_path+="/$d"; done
    CHILDREN["$current_path"]="${CHILDREN[$current_path]:-}"
    continue
  fi

  line="$stripped"
  current_path="ROOT"
  [[ ${#path_stack[@]} -gt 0 ]] && for d in "${path_stack[@]}"; do current_path+="/$d"; done
  CHILDREN["$current_path"]+=$'\n'"$line"
  name="${line%%|*}"
  ITEMS["$current_path/$name"]="$line"
  [[ ${#path_stack[@]} -eq 0 ]] && ROOT_ITEMS+=("$line")
done < "$TMP_CONF"

# ====== 状态变量 ======
CURRENT_PATH="ROOT"
MENU_STACK=()
page=1
DISPLAY_LINES=()

push_menu_stack() { MENU_STACK+=("$CURRENT_PATH" "$page"); }

pop_menu_stack() {
  [[ ${#MENU_STACK[@]} -lt 2 ]] && { echo "ROOT" "1"; return 1; }
  page="${MENU_STACK[-1]}"; unset 'MENU_STACK[-1]'
  path="${MENU_STACK[-1]}"; unset 'MENU_STACK[-1]'
  echo "$path" "$page"
}

# ====== 打印页面 ======
print_page() {
  local path="$1" pagev="$2"
  DISPLAY_LINES=()
  for key in "${!CHILDREN[@]}"; do
    [[ "$key" == "$path"/* ]] && sub="${key#$path/}" && [[ "$sub" != */* ]] && DISPLAY_LINES+=("DIR:$sub")
  done
  [[ -n "${CHILDREN[$path]:-}" ]] && while IFS= read -r line || [ -n "$line" ]; do [[ -n "$line" ]] && DISPLAY_LINES+=("$line"); done <<< "${CHILDREN[$path]}"
  TOTAL=${#DISPLAY_LINES[@]}
  PAGES=$((TOTAL ? (TOTAL+PER_PAGE-1)/PER_PAGE : 1))
  ((pagev>PAGES)) && pagev=1

  clear; draw_line; draw_title "脚本管理器 (by Moreanp)"; draw_mid
  local start=$(( (pagev-1)*PER_PAGE )); local end=$(( start+PER_PAGE-1 )); ((end>=TOTAL)) && end=$((TOTAL-1))
  ((TOTAL==0)) && draw_text "（该目录为空）" || \
  for i in $(seq $start $end); do
    entry="${DISPLAY_LINES[i]}"
    [[ "$entry" == DIR:* ]] && draw_text "${C_KEY}[$((i-start))]${C_RESET} ${C_RUN}${entry#DIR:}${C_RESET}" || draw_text "${C_KEY}[$((i-start))]${C_RESET} ${C_EXEC}${entry%%|*}${C_RESET}"
  done
  draw_mid
  draw_text "路径：${path#ROOT}"
  draw_text "[ n ] 下页   [ b ] 上页"
  draw_text "[ q ] 上级   [0-9] 选择"
  draw_bot
  page=$pagev
}

# ====== 执行槽 ======
run_slot() {
  local idx=$(( (page-1)*PER_PAGE + $2 ))
  (( idx<0 || idx>=${#DISPLAY_LINES[@]} )) && { read -rp $'X 无效选项，按回车返回...' _; return; }
  entry="${DISPLAY_LINES[$idx]}"
  if [[ "$entry" == DIR:* ]]; then push_menu_stack; CURRENT_PATH="$CURRENT_PATH/${entry#DIR:}"; page=1; return; fi

  name="${entry%%|*}"; rest="${entry#*|}"; cmd="${rest%%|*}"; args=""; [[ "$rest" == *"|"* ]] && args="${rest#*|}"
  clear; echo -e "${C_KEY}→ 正在执行：${C_EXEC}${name}${C_RESET}"; echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  if [[ "$cmd" =~ ^CMD: ]]; then eval "${cmd#CMD:} ${args}"
  elif [[ "$cmd" =~ ^https?:// ]]; then
    if command -v curl >/dev/null 2>&1; then bash <(curl -fsSL "$cmd") ${args:+$args}
    elif command -v wget >/dev/null 2>&1; then bash <(wget -qO- "$cmd") ${args:+$args}
    else echo "X 系统未安装 curl 或 wget"; fi
  else eval "$cmd ${args}"; fi
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  read -rp $'按回车返回菜单...' _
}

# ====== 搜索 ======
do_search() {
  [[ -z "$1" ]] && return
  local keyword="$1"; local lc_kw=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
  SEARCH_RESULTS=()
  for key in "${!ITEMS[@]}"; do
    name="${key##*/}"; lc_key=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    [[ "$lc_key" == *"$lc_kw"* ]] && SEARCH_RESULTS+=("${ITEMS[$key]}")
  done
  (( ${#SEARCH_RESULTS[@]} == 0 )) && { echo -e "${C_WARN}! 未找到匹配: '$keyword'${C_RESET}"; read -rp $'按回车返回...' _; return; }

  push_menu_stack
  CURRENT_PATH="__SEARCH__/$keyword"
  DISPLAY_LINES=("${SEARCH_RESULTS[@]}")
  TOTAL=${#DISPLAY_LINES[@]}
  PAGES=$(( (TOTAL+PER_PAGE-1)/PER_PAGE ))
  page=1

  clear; draw_line; draw_title "脚本管理器 (搜索：$keyword)"; draw_mid
  local start=$(( (page-1)*PER_PAGE )); local end=$(( start+PER_PAGE-1 )); ((end>=TOTAL)) && end=$((TOTAL-1))
  for i in $(seq $start $end); do entry="${DISPLAY_LINES[i]}"; draw_text "${C_KEY}[$((i-start))]${C_RESET} ${C_EXEC}${entry%%|*}${C_RESET}"; done
  draw_mid
  draw_text "搜索结果 ${page}/${PAGES} 共 ${#DISPLAY_LINES[@]} 项"
  draw_text "[ q ] 返回上一级     [ 0-9 ] 选择"
  draw_bot
}

# ====== 主循环 ======
while true; do
  [[ "$CURRENT_PATH" != __SEARCH__/* ]] && print_page "$CURRENT_PATH" "$page"
  printf "%b选项 (0-9 or 输入关键字搜索): %b" "$C_HINT" "$C_RESET"
  read -r key || true
  [[ -z "$key" ]] && continue
  case "$key" in
    [0-9]) run_slot "$page" "$key" ;;
    n|N) ((page<PAGES)) && ((page++)) || { echo "已是最后一页"; read -rp $'按回车返回...' _; } ;;
    b|B) ((page>1)) && ((page--)) || { echo "已是第一页"; read -rp $'按回车返回...' _; } ;;
    q|Q) read -r prev_path prev_page < <(pop_menu_stack); CURRENT_PATH="$prev_path"; page="$prev_page"; DISPLAY_LINES=() ;;
    *) do_search "$key" ;;
  esac
done
