#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权 ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m⚠️  检测到当前用户不是 root。\033[0m"
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[1;31m❌ 系统未安装 sudo，请使用 root 用户运行本脚本。\033[0m"
    exit 1
  fi
  echo -e "\033[1;32m🔑  请输入当前用户的密码以获取管理员权限（sudo）...\033[0m"
  exec sudo -E bash "$0" "$@"
  exit $?
fi

# ====== 配置部分 ======
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10
BOX_WIDTH=50
LEFT_INDENT="        "

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
  echo "❌ 无法下载配置文件: $CONFIG_URL"
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

# ====== 宽度计算 ======
str_width() {
  local text="$1"
  text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
  local len=0 i ch code
  for ((i=0;i<${#text};i++)); do
    ch="${text:i:1}"
    code=$(printf '%d' "'$ch" 2>/dev/null || true)
    if (( (code>=19968 && code<=40959) || (code>=65281 && code<=65519) || (code>=12288 && code<=12543) )); then
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
  local width
  width=$(str_width "$text")
  local padding=$((BOX_WIDTH - width - ${#LEFT_INDENT} - 2))
  ((padding<0)) && padding=0
  printf "%b║%s%b%*s%b║%b\n" "$C_BOX" "$LEFT_INDENT" "$text" "$padding" "" "$C_BOX" "$C_RESET"
}

draw_title() {
  local title="$1"
  local width
  width=$(str_width "$title")
  local left_pad=$(( (BOX_WIDTH - width - 2)/2 ))
  local right_pad=$((BOX_WIDTH - width - left_pad - 2))
  printf "%b║%*s%b%s%b%*s%b║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX" "$C_RESET"
}

# ====== 层级化配置解析 ======
declare -A CHILDREN
declare -A ITEMS
declare -a ROOT_ITEMS

path_stack=()
current_path="ROOT"

while IFS= read -r raw_line; do
  line="${raw_line#"${raw_line%%[![:space:]]*}"}"   # 去前导空格
  indent=$(( (${#raw_line} - ${#line}) / 2 ))
  [[ "$line" =~ ^# ]] && continue
  [[ -z "$line" ]] && continue

  if [[ "$line" =~ ^\[.*\]$ ]]; then
    dir="${line#[}"
    dir="${dir%]}"
    while ((${#path_stack[@]} > indent)); do unset 'path_stack[-1]'; done
    path_stack+=("$dir")
    current_path="ROOT"
    for d in "${path_stack[@]}"; do current_path+="/$d"; done
    continue
  fi

  # 普通脚本项
  name="${line%%|*}"
  CHILDREN["$current_path"]+="$line"$'\n'
  ITEMS["$current_path/$name"]="$line"
  if (( ${#path_stack[@]} == 0 )); then
    ROOT_ITEMS+=("$line")
  fi
done < "$TMP_CONF"

CURRENT_PATH="ROOT"
MENU_STACK=()
page=1

# ====== 打印页面 ======
print_page() {
  local path="$1" page="$2"
  DISPLAY_LINES=()

  # 获取子目录
  for k in "${!CHILDREN[@]}"; do
    if [[ "$k" == "$path"/* ]]; then
      sub="${k#$path/}"
      [[ "$sub" != */* ]] && DISPLAY_LINES+=("DIR:$sub")
    fi
  done

  # 加入脚本项
  if [[ -n "${CHILDREN[$path]:-}" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && DISPLAY_LINES+=("$line")
    done <<< "${CHILDREN[$path]}"
  fi

  TOTAL=${#DISPLAY_LINES[@]}
  PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))
  ((page>PAGES)) && page=1

  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp)"
  draw_mid

  local start=$(( (page-1)*PER_PAGE ))
  local end=$(( start+PER_PAGE-1 ))
  ((end>=TOTAL)) && end=$((TOTAL-1))

  for i in $(seq $start $end); do
    local entry="${DISPLAY_LINES[i]}"
    if [[ "$entry" == DIR:* ]]; then
      dir="${entry#DIR:}"
      draw_text "${C_KEY}[$((i-start))]${C_RESET} 📁 ${C_NAME}${dir}${C_RESET}"
    elif [[ -n "$entry" ]]; then
      name="${entry%%|*}"
      draw_text "${C_KEY}[$((i-start))]${C_RESET} ${C_NAME}${name}${C_RESET}"
    else
      draw_text ""
    fi
  done

  draw_mid
  draw_text "路径：${path#ROOT}"
  draw_text "[ n ] 下一页   [ b ] 上一页"
  draw_text "[ q ] 上一级     [ 0-9 ] 选择"
  draw_bot
}

# ====== 执行/进入逻辑 ======
run_slot() {
  local page="$1" slot="$2"
  local start=$(( (page-1)*PER_PAGE ))
  local idx=$((start+slot))
  if (( idx<0 || idx>=${#DISPLAY_LINES[@]} )); then
    read -rp "❌ 无效选项，按回车返回..." _
    return
  fi

  entry="${DISPLAY_LINES[$idx]}"
  if [[ "$entry" == DIR:* ]]; then
    dir="${entry#DIR:}"
    MENU_STACK+=("$CURRENT_PATH" "$page")
    CURRENT_PATH="$CURRENT_PATH/$dir"
    page=1
    return
  fi

  name="${entry%%|*}"
  rest="${entry#*|}"
  cmd="${rest%%|*}"
  args=""
  [[ "$rest" == *"|"* ]] && args="${rest#*|}"

  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${name}${C_RESET}"
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"

  if [[ "$cmd" =~ ^CMD: ]]; then
    eval "${cmd#CMD:} ${args}"
  elif [[ "$cmd" =~ ^https?:// ]]; then
    bash <(curl -fsSL "$cmd") ${args:+$args}
  else
    eval "$cmd ${args}"
  fi

  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  read -rp "按回车返回菜单..." _
}

# ====== 主循环 ======
while true; do
  print_page "$CURRENT_PATH" "$page"
  printf "%b选项 (0-9): %b" "$C_HINT" "$C_RESET"
  read -r key || true

  case "$key" in
    [0-9]) run_slot "$page" "$key" ;;
    n|N) ((page<PAGES)) && ((page++)) ;;
    b|B) ((page>1)) && ((page--)) ;;
    q|Q)
      if (( ${#MENU_STACK[@]} > 0 )); then
        page="${MENU_STACK[-1]}"
        CURRENT_PATH="${MENU_STACK[-2]}"
        unset 'MENU_STACK[-1]' 'MENU_STACK[-1]'
      else
        clear; echo "👋 再见！"; exit 0
      fi
      ;;
    *) continue ;;
  esac
done
