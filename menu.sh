#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权 ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m! Current user is not root.\033[0m"
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[1;31mX sudo not installed. Please run as root.\033[0m"
    exit 1
  fi
  echo -e "\033[1;32m🔑 Please enter password to gain admin privileges...\033[0m"
  exec sudo -E bash "$0" "$@"
fi

# ====== 配置部分 ======
CONFIG_URL="${CONFIG_URL:-https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf}"
BACKUP_URL="https://raw.eaidan.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10
BOX_WIDTH=41
LEFT_INDENT="        "

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

# ====== 下载配置 ======
download_conf() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$TMP_CONF"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_CONF" "$url"
  else
    echo "X curl or wget not installed"
    exit 1
  fi
}

echo -e "\033[1;34m⏳ Loading remote configuration...\033[0m"
if ! download_conf "$CONFIG_URL"; then
  echo -e "\033[1;33m! Main source failed, trying backup...\033[0m"
  if ! download_conf "$BACKUP_URL"; then
    echo -e "\033[1;31mX Cannot download configuration. Check network.\033[0m"
    exit 1
  fi
fi

# ====== 色彩定义 ======
C_RESET="\033[0m"
C_BOX="\033[1;38;5;51m"
C_TITLE="\033[1;38;5;220m"
C_KEY="\033[1;32m"
C_HINT="\033[1;32m"
C_DIV="\033[38;5;240m"
C_EXEC="\033[1;32m"
C_RUN="\033[38;5;201m"
C_WARN="\033[1;33m"

# ====== 宽度计算 ======
str_width() {
  local text="$1"
  text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
  local len=0 i ch code
  for ((i=0;i<${#text};i++)); do
    ch="${text:i:1}"
    code=$(printf '%d' "'$ch" 2>/dev/null || true)
    (( (code>=19968 && code<=40959) || (code>=65281 && code<=65519) || (code>=12288 && code<=12543) )) && len=$((len+2)) || len=$((len+1))
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
  ((left_pad<0)) && left_pad=0
  ((right_pad<0)) && right_pad=0
  printf "%b║%*s%b%s%b%*s%b║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX" "$C_RESET"
}

# ====== 解析配置 ======
declare -A CHILDREN
declare -A ITEMS
path_stack=()
while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  [[ -z "$raw_line" || "$raw_line" =~ ^[[:space:]]*$ ]] && continue
  raw_line="${raw_line%$'\r'}"
  stripped="${raw_line#"${raw_line%%[![:space:]]*}"}"
  [[ "$stripped" =~ ^# ]] && continue
  lead_len=$(( ${#raw_line} - ${#stripped} ))
  indent=$(( lead_len / 2 ))
  if [[ "$stripped" =~ ^\[.*\]$ ]]; then
    dir="${stripped#[}"; dir="${dir%]}"
    while ((${#path_stack[@]} > indent)); do unset 'path_stack[-1]'; done
    path_stack+=("$dir")
    current_path="ROOT"; for d in "${path_stack[@]}"; do current_path+="/$d"; done
    CHILDREN["$current_path"]="${CHILDREN[$current_path]:-}"
    continue
  fi
  line="$stripped"
  current_path="ROOT"; [[ ${#path_stack[@]} -gt 0 ]] && for d in "${path_stack[@]}"; do current_path+="/$d"; done
  CHILDREN["$current_path"]+=$'\n'"$line"
  name="${line%%|*}"; ITEMS["$current_path/$name"]="$line"
done < "$TMP_CONF"

# ====== 状态变量 ======
CURRENT_PATH="ROOT"
MENU_STACK=()
page=1
DISPLAY_LINES=()
SEARCH_MODE=0

# ====== 栈操作 ======
push_menu_stack() { MENU_STACK+=("$CURRENT_PATH"); }
pop_menu_stack() {
    if ((${#MENU_STACK[@]}==0)); then CURRENT_PATH="ROOT"; page=1; return 1; fi
    last_idx=$((${#MENU_STACK[@]}-1))
    CURRENT_PATH="${MENU_STACK[$last_idx]}"
    unset "MENU_STACK[$last_idx]"
    page=1
}

# ====== 打印页面 ======
print_page() {
  local path="$1" pagev="$2"
  DISPLAY_LINES=()
  mapfile -t sorted_keys < <(printf '%s\n' "${!CHILDREN[@]}" | sort)
  for key in "${sorted_keys[@]}"; do
    [[ "$key" == "$path"/* ]] && sub="${key#$path/}" && [[ "$sub" != */* ]] && DISPLAY_LINES+=("DIR:$sub")
  done
  [[ -n "${CHILDREN[$path]:-}" ]] && while IFS= read -r line || [ -n "$line" ]; do [[ -n "$line" ]] && DISPLAY_LINES+=("$line"); done <<< "${CHILDREN[$path]}"
  local TOTAL=${#DISPLAY_LINES[@]}
  local PAGES=$((TOTAL ? (TOTAL+PER_PAGE-1)/PER_PAGE : 1))
  ((pagev>PAGES)) && pagev=1

  clear; draw_line; draw_title "Script Manager (by Moreanp)"; draw_mid
  local start=$(( (pagev-1)*PER_PAGE )); local end=$(( start+PER_PAGE-1 )); (( end>=TOTAL )) && end=$(( TOTAL-1 ))

  if (( TOTAL == 0 )); then
    draw_text "（该目录为空）"
  else
    for i in $(seq $start $end); do
      entry="${DISPLAY_LINES[i]}"
      local shown=$(( ( (i-start+1) % 10 ) ))
      [[ "$entry" == DIR:* ]] && draw_text "${C_KEY}[$shown]${C_RESET} ${C_RUN}${entry#DIR:}${C_RESET}" \
        || draw_text "${C_KEY}[$shown]${C_RESET} ${C_EXEC}${entry%%|*}${C_RESET}"
    done
  fi
  draw_mid
  draw_text "Path: ${path#ROOT}"
  draw_text "[ n ] Next Page   [ b ] Previous Page"
  draw_text "[ q ] Back / Quit   [0-9] Select"
  draw_bot
  page=$pagev
}

# ====== 执行槽 ======
run_slot() {
  local page="$1" key_input="$2"
  local offset=$(( key_input == 0 ? 9 : key_input - 1 ))
  local idx=$(( (page-1)*PER_PAGE + offset ))
  (( idx<0 || idx>=${#DISPLAY_LINES[@]} )) && { read -rp $'X Invalid option, press Enter to return...' _; return; }

  local entry="${DISPLAY_LINES[$idx]}"
  if [[ "$entry" == DIR:* ]]; then
    push_menu_stack
    CURRENT_PATH="$CURRENT_PATH/${entry#DIR:}"
    page=1
    return
  fi

  local name="${entry%%|*}"
  local rest="${entry#*|}"
  local cmd="${rest%%|*}"
  local args=""; [[ "$rest" == *"|"* ]] && args="${rest#*|}"

  clear; echo -e "${C_KEY}→ Running: ${C_EXEC}${name}${C_RESET}"
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"

  # 执行前确认，默认 Y
  read -rp "Confirm execution [$name]? [Y/n] " confirm
  confirm=${confirm:-Y}
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
      echo "Execution cancelled [$name]"
      read -rp $'Press Enter to return...' _
      return
  fi

  # 执行命令
  if [[ "$cmd" =~ ^CMD: ]]; then
    eval "${cmd#CMD:} ${args}"
  elif [[ "$cmd" =~ ^https?:// ]]; then
    if command -v curl >/dev/null 2>&1; then bash <(curl -fsSL "$cmd") ${args:+$args}
    elif command -v wget >/dev/null 2>&1; then bash <(wget -qO- "$cmd") ${args:+$args}
    else echo "X curl or wget not installed"; fi
  else
    eval "$cmd ${args}"
  fi

  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  read -rp $'Press Enter to return...' _
}

# ====== 搜索 ======
do_search() {
  [[ -z "$1" ]] && return
  local keyword="$1"
  local lc_kw=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
  SEARCH_RESULTS=()
  for key in "${!ITEMS[@]}"; do
    local name="${key##*/}"
    local lc_key=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    [[ "$lc_key" == *"$lc_kw"* ]] && SEARCH_RESULTS+=("${ITEMS[$key]}")
  done

  if (( ${#SEARCH_RESULTS[@]} == 0 )); then
    echo -e "${C_WARN}! No match found: '$keyword'${C_RESET}"
    read -rp $'Press Enter to return...' _
    return
  fi

  SEARCH_MODE=1
  CURRENT_PATH="__SEARCH__/$keyword"
  DISPLAY_LINES=("${SEARCH_RESULTS[@]}")
  local TOTAL=${#DISPLAY_LINES[@]}
  local PAGES=$(( (TOTAL+PER_PAGE-1)/PER_PAGE ))
  page=1

  clear; draw_line; draw_title "Script Manager (Search: $keyword)"; draw_mid
  local start=$(( (page-1)*PER_PAGE )); local end=$((start+PER_PAGE-1)); ((end>=TOTAL)) && end=$((TOTAL-1))
  for i in $(seq $start $end); do
    local entry="${DISPLAY_LINES[i]}"
    local shown=$(( ( (i-start+1) % 10 ) ))
    draw_text "${C_KEY}[$shown]${C_RESET} ${C_EXEC}${entry%%|*}${C_RESET}"
  done
  draw_mid
  draw_text "Search results ${page}/${PAGES}, total ${#DISPLAY_LINES[@]}"
  draw_text "[ q ] Back   [0-9] Select"
  draw_bot
}

# ====== 主循环 ======
while true; do
  [[ "$SEARCH_MODE" -eq 0 ]] && print_page "$CURRENT_PATH" "$page"
  read -e -p "$(printf "%bOption (0-9 or keyword search): %b" "$C_HINT" "$C_RESET")" key || true
  [[ -z "$key" ]] && continue
  case "$key" in
    [0-9]) run_slot "$page" "$key" ;;
    n|N) ((page<PAGES)) && ((page++)) || { echo "Already last page"; read -rp $'Press Enter to return...' _; } ;;
    b|B) ((page>1)) && ((page--)) || { echo "Already first page"; read -rp $'Press Enter to return...' _; } ;;
    q|Q)
      if [[ "$SEARCH_MODE" -eq 1 ]]; then
        SEARCH_MODE=0
        CURRENT_PATH="ROOT"
        MENU_STACK=()
        page=1
      else
        read -rp "Confirm exit Script Manager? [Y/n] " exit_confirm
        exit_confirm=${exit_confirm:-Y}
        if [[ "$exit_confirm" =~ ^[Yy]$ ]]; then
            echo "Exiting Script Manager..."
            exit 0
        else
            continue
        fi
      fi
      DISPLAY_LINES=()
      ;;
    *) do_search "$key" ;;
  esac
done
