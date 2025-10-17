#!/usr/bin/env bash
# menu_manager_v2_fixed.sh
# 支持：无限层级目录 + 多次搜索可返回主菜单 + 输入可退格删除
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权 ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m! 检测到当前用户不是 root。\033[0m"
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[1;31mX 系统未安装 sudo，请使用 root 用户运行本脚本。\033[0m"
    exit 1
  fi
  echo -e "\033[1;32m请输入密码以获取管理员权限（sudo）...\033[0m"
  exec sudo -E bash "$0" "$@"
  exit $?
fi

# ====== 配置 ======
CONFIG_URL="${CONFIG_URL:-https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts1.conf}"
PER_PAGE=10
BOX_WIDTH=41
LEFT_INDENT="        "

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

# ====== 下载配置 ======
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$CONFIG_URL" -o "$TMP_CONF" || {
    echo -e "\033[1;31mX curl 下载失败，尝试 wget...\033[0m"
    wget -qO "$TMP_CONF" "$CONFIG_URL" || { echo "X 下载失败"; exit 1; }
  }
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP_CONF" "$CONFIG_URL" || { echo "X wget 下载失败"; exit 1; }
else
  echo "X 未安装 curl/wget"; exit 1
fi

# ====== 色彩 ======
C_RESET="\033[0m"; C_BOX="\033[1;38;5;202m"
C_TITLE="\033[1;38;5;220m"; C_KEY="\033[1;32m"
C_NAME="\033[1;38;5;39m"; C_HINT="\033[1;32m"
C_DIV="\033[38;5;240m"; C_EXEC="\033[1;32m"
C_WARN="\033[1;33m"; C_ERROR="\033[1;31m"
C_RUN="\033[1;34m"

# ====== 计算宽度（全角兼容） ======
str_width() {
  local text="$1"
  text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
  local len=0 i ch code
  for ((i=0;i<${#text};i++)); do
    ch="${text:i:1}"; code=$(printf '%d' "'$ch" 2>/dev/null || true)
    if [[ -n "$code" ]] && (( (code>=19968 && code<=40959) || (code>=65281 && code<=65519) || (code>=12288 && code<=12543) )); then
      len=$((len+2))
    else len=$((len+1)); fi
  done
  echo "$len"
}

# ====== 绘制边框 ======
draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }

draw_text() {
  local text="$1"; local width; width=$(str_width "$text")
  local padding=$((BOX_WIDTH - width - ${#LEFT_INDENT} - 2))
  ((padding<0)) && padding=0
  printf "%b║%s%b%*s%b║%b\n" "$C_BOX" "$LEFT_INDENT" "$text" "$padding" "" "$C_BOX" "$C_RESET"
}

draw_title() {
  local title="$1"; local width; width=$(str_width "$title")
  local left_pad=$(( (BOX_WIDTH - width - 2)/2 ))
  local right_pad=$((BOX_WIDTH - width - left_pad - 2))
  ((left_pad<0)) && left_pad=0; ((right_pad<0)) && right_pad=0
  printf "%b║%*s%b%s%b%*s%b║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX" "$C_RESET"
}

# ====== 解析配置 ======
declare -A CHILDREN; declare -A ITEMS; declare -a ROOT_ITEMS
path_stack=(); current_path="ROOT"

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  [[ -z "$raw_line" || "$raw_line" =~ ^[[:space:]]*$ || "$raw_line" =~ ^# ]] && continue
  raw_line="${raw_line%$'\r'}"
  stripped="${raw_line#"${raw_line%%[![:space:]]*}"}"
  lead_len=$(( ${#raw_line} - ${#stripped} )); indent=$(( lead_len / 2 ))

  if [[ "${stripped}" =~ ^\[.*\]$ ]]; then
    dir="${stripped#[}"; dir="${dir%]}"
    while ((${#path_stack[@]} > indent)); do unset "path_stack[-1]"; done
    path_stack+=("$dir"); current_path="ROOT"
    for d in "${path_stack[@]}"; do current_path+="/$d"; done
    CHILDREN["$current_path"]="${CHILDREN[$current_path]:-}"
    continue
  fi

  line="${stripped}"; current_path="ROOT"
  for d in "${path_stack[@]}"; do current_path+="/$d"; done
  CHILDREN["$current_path"]+="${CHILDREN[$current_path]:+$'\n'}$line"
  name="${line%%|*}"; ITEMS["$current_path/$name"]="$line"
  ((${#path_stack[@]}==0)) && ROOT_ITEMS+=("$line")
done < "$TMP_CONF"

# ====== 状态 ======
CURRENT_PATH="ROOT"; declare -a MENU_STACK; page=1; DISPLAY_LINES=()

push_menu_stack() { MENU_STACK+=("$1" "$2"); }
pop_menu_stack() {
  ((${#MENU_STACK[@]}<2)) && return 1
  local p2="${MENU_STACK[-1]}" p1="${MENU_STACK[-2]}"
  unset "MENU_STACK[-1]" "MENU_STACK[-1]"
  echo "$p1 $p2"
}

print_page() {
  local path="$1" pagev="$2"; DISPLAY_LINES=()
  for key in "${!CHILDREN[@]}"; do
    if [[ "$key" == "$path"/* ]]; then
      sub="${key#$path/}"; [[ "$sub" != */* ]] && DISPLAY_LINES+=("DIR:$sub")
    fi
  done
  [[ -n "${CHILDREN[$path]:-}" ]] && while IFS= read -r line; do
    [[ -n "$line" ]] && DISPLAY_LINES+=("$line")
  done <<< "${CHILDREN[$path]}"

  TOTAL=${#DISPLAY_LINES[@]}; ((TOTAL==0)) && TOTAL=0
  PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE )); ((PAGES==0)) && PAGES=1
  ((pagev>PAGES)) && pagev=1

  clear; draw_line; draw_title "脚本管理器 (by Moreanp)"; draw_mid
  local start=$(( (pagev-1)*PER_PAGE )) end=$(( start+PER_PAGE-1 ))
  ((end>=TOTAL)) && end=$((TOTAL-1))
  ((TOTAL==0)) && draw_text "（该目录为空）"
  for i in $(seq $start $end); do
    entry="${DISPLAY_LINES[i]}"
    [[ "$entry" == DIR:* ]] && draw_text "${C_KEY}[$((i-start))]${C_RESET} ${C_RUN}${entry#DIR:}${C_RESET}" ||
      draw_text "${C_KEY}[$((i-start))]${C_RESET} ${C_EXEC}${entry%%|*}${C_RESET}"
  done
  draw_mid
  pshow="${path#ROOT}"; [[ -z "$pshow" ]] && pshow="/"
  draw_text "路径：${pshow}"
  draw_text "[ n ] 下页   [ b ] 上页"
  draw_text "[ q ] 上级   [0-9] 选择"
  draw_bot
  page=$pagev
}

run_slot() {
  local pagev="$1" slot="$2"; local start=$(( (pagev-1)*PER_PAGE ))
  local idx=$(( start + slot )); (( idx<0 || idx>=${#DISPLAY_LINES[@]} )) && return
  entry="${DISPLAY_LINES[$idx]}"
  if [[ "$entry" == DIR:* ]]; then
    push_menu_stack "$CURRENT_PATH" "$pagev"
    CURRENT_PATH="$CURRENT_PATH/${entry#DIR:}"; page=1; return
  fi
  local name="${entry%%|*}" rest="${entry#*|}" cmd="${rest%%|*}" args="${rest#*|}"
  clear; echo -e "${C_KEY}→ 执行：${C_EXEC}${name}${C_RESET}"
  if [[ "$cmd" =~ ^CMD: ]]; then eval "${cmd#CMD:} ${args:-}"
  elif [[ "$cmd" =~ ^https?:// ]]; then
    command -v curl >/dev/null && bash <(curl -fsSL "$cmd") ${args:-} ||
    command -v wget >/dev/null && bash <(wget -qO- "$cmd") ${args:-} ||
    echo "X 未安装 curl 或 wget"
  else eval "$cmd ${args:-}"; fi
  read -rp $'按回车返回菜单...' _
}

do_search() {
  local keyword="$1"; [[ -z "$keyword" ]] && return
  local lc_kw="$(echo "$keyword" | tr '[:upper:]' '[:lower:]')"
  local -a SEARCH_RESULTS=()
  for key in "${!ITEMS[@]}"; do
    local name="${key##*/}" lc_key="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    [[ "$lc_key" == *"$lc_kw"* ]] && SEARCH_RESULTS+=("${ITEMS[$key]}")
  done
  ((${#SEARCH_RESULTS[@]}==0)) && { echo -e "${C_WARN}! 未找到匹配: '$keyword'${C_RESET}"; read -rp "回车返回..."; return; }
  push_menu_stack "$CURRENT_PATH" "$page"
  CURRENT_PATH="__SEARCH__"; DISPLAY_LINES=("${SEARCH_RESULTS[@]}")
  TOTAL=${#DISPLAY_LINES[@]}; PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE )); page=1

  while true; do
    clear; draw_line; draw_title "脚本管理器 (搜索：${keyword})"; draw_mid
    local start=$(( (page-1)*PER_PAGE )) end=$(( start+PER_PAGE-1 ))
    ((end>=TOTAL)) && end=$((TOTAL-1))
    for i in $(seq $start $end); do
      entry="${DISPLAY_LINES[i]}"; name="${entry%%|*}"
      draw_text "${C_KEY}[$((i-start))]${C_RESET} ${C_EXEC}${name}${C_RESET}"
    done
    draw_mid; draw_text "搜索结果 ${page}/${PAGES} 共 ${#DISPLAY_LINES[@]} 项"
    draw_text "[ q ] 返回上一级     [ 0-9 ] 选择"; draw_bot
    read -e -p "$(printf "%b选项: %b" "$C_HINT" "$C_RESET")" key || true
    case "$key" in
      [0-9]) run_slot "$page" "$key" ;;
      n|N) ((page<PAGES)) && ((page++)) ;;
      b|B) ((page>1)) && ((page--)) ;;
      q|Q)
        read -r prev_path prev_page < <(pop_menu_stack || printf "\n\n")
        if [[ -z "$prev_path" ]]; then CURRENT_PATH="ROOT"; page=1; return; fi
        CURRENT_PATH="$prev_path"; page="$prev_page"; return ;;
      *) do_search "$key"; return ;;
    esac
  done
}

# ====== 主循环 ======
while true; do
  print_page "$CURRENT_PATH" "$page"
  read -e -p "$(printf "%b选项 (0-9 or 输入关键字搜索): %b" "$C_HINT" "$C_RESET")" key || true
  case "$key" in
    [0-9]) run_slot "$page" "$key" ;;
    n|N) ((page<PAGES)) && ((page++)) ;;
    b|B) ((page>1)) && ((page--)) ;;
    q|Q)
      read -r prev_path prev_page < <(pop_menu_stack || printf "\n\n")
      if [[ -z "$prev_path" ]]; then clear; echo "→ 再见！"; exit 0; fi
      CURRENT_PATH="$prev_path"; page="$prev_page" ;;
    *) do_search "$key" ;;
  esac
done
