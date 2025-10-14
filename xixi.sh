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
  TMP_SCRIPT="$(mktemp /tmp/menu_manager.XXXXXX.sh)"
  cat > "$TMP_SCRIPT"
  chmod +x "$TMP_SCRIPT"
  exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
fi

# ====== 配置 ======
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

mapfile -t RAW_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")

# ====== 色彩 ======
C_RESET="\033[0m"
C_BOX="\033[1;38;5;202m"
C_TITLE="\033[1;38;5;220m"
C_KEY="\033[1;32m"
C_NAME="\033[1;38;5;39m"
C_HINT="\033[1;32m"
C_DIV="\033[38;5;240m"

# ====== 计算宽度 ======
str_width() {
  local text="$1"
  text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
  local len=0 i ch code
  for ((i=0;i<${#text};i++)); do
    ch="${text:i:1}"
    code=$(printf '%d' "'$ch" 2>/dev/null || true)
    if (( (code>=19968 && code<=40959) || (code>=65281 && code<=65519) || (code>=12288 && code<=12351) || (code>=12352 && code<=12543) )); then
      len=$((len+2))
    else
      len=$((len+1))
    fi
  done
  echo "$len"
}

# ====== 绘制函数 ======
draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }

draw_text() {
  local text="$1"
  local width padding
  width=$(str_width "$text")
  padding=$((BOX_WIDTH - width - ${#LEFT_INDENT} - 2))
  ((padding<0)) && padding=0
  printf "%b║%s%b%*s%b║%b\n" "$C_BOX" "$LEFT_INDENT" "$text" "$padding" "" "$C_BOX" "$C_RESET"
}

draw_title() {
  local title="$1"
  local width left_pad right_pad
  width=$(str_width "$title")
  left_pad=$(( (BOX_WIDTH - width - 2)/2 ))
  right_pad=$((BOX_WIDTH - width - left_pad - 2))
  printf "%b║%*s%b%s%b%*s%b║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX" "$C_RESET"
}

# ====== 配置解析（支持多级菜单） ======
declare -A MENU_TREE
declare -a ALL_ITEMS

for line in "${RAW_LINES[@]}"; do
  IFS='|' read -r -a parts <<< "$line"
  depth=$(grep -o '||' <<< "$line" | wc -l)
  clean_parts=()
  for p in "${parts[@]}"; do
    [[ -n "$p" ]] && clean_parts+=("$p")
  done
  name="${clean_parts[$depth]}"
  keypath=$(IFS='>'; echo "${clean_parts[*]:0:$depth}")
  cmd="${clean_parts[$((depth+1))]:-}"
  args="${clean_parts[$((depth+2))]:-}"
  ALL_ITEMS+=("$keypath|$name|$cmd|$args")
done

# ====== 打印菜单页 ======
print_menu() {
  local title="$1"; shift
  local -n items=$1
  clear
  draw_line
  draw_title "$title"
  draw_mid
  local i=0
  for item in "${items[@]}"; do
    name="${item%%|*}"
    draw_text "${C_KEY}[$i]${C_RESET} ${C_NAME}${name}${C_RESET}"
    ((i++))
  done
  draw_mid
  draw_text "[ s ] 搜索   [ b ] 返回上级   [ q ] 退出"
  draw_bot
}

# ====== 执行命令 ======
run_cmd() {
  local name="$1" cmd="$2" args="$3"
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

# ====== 生成子菜单 ======
get_children() {
  local prefix="$1"
  local results=()
  for entry in "${ALL_ITEMS[@]}"; do
    IFS='|' read -r path name cmd args <<< "$entry"
    if [[ "$path" == "$prefix" ]]; then
      results+=("$name|$cmd|$args")
    fi
  done
  printf '%s\n' "${results[@]}"
}

# ====== 搜索功能 ======
search_items() {
  local keyword="$1"
  local -a results=()
  keyword=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
  for entry in "${ALL_ITEMS[@]}"; do
    IFS='|' read -r _ name cmd args <<< "$entry"
    lower_name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower_name" == *"$keyword"* ]]; then
      results+=("$name|$cmd|$args")
    fi
  done
  if ((${#results[@]}==0)); then
    echo "❌ 未找到匹配项，输入 p 返回主菜单。"
    read -rp "请输入: " back
    [[ "$back" == "p" ]] && return 1
    return 0
  fi
  local choice
  while true; do
    print_menu "搜索结果：$keyword" results
    read -rp "请输入编号或 p 返回主菜单: " choice
    if [[ "$choice" =~ ^[0-9]+$ && "$choice" -lt "${#results[@]}" ]]; then
      IFS='|' read -r name cmd args <<< "${results[$choice]}"
      run_cmd "$name" "$cmd" "$args"
    elif [[ "$choice" == "p" ]]; then
      return 1
    fi
  done
}

# ====== 主逻辑 ======
stack=("ROOT")
while true; do
  prefix=$(IFS='>'; echo "${stack[*]}")
  IFS=$'\n' read -r -d '' -a current_items < <(get_children "$prefix" && printf '\0')

  if ((${#current_items[@]}==0)); then
    clear
    echo "❌ 当前菜单为空，返回上级。"
    read -rp "按回车继续..." _
    unset 'stack[-1]'
    continue
  fi

  print_menu "脚本管理器 - ${stack[-1]}" current_items
  read -rp "请输入编号/指令: " choice

  case "$choice" in
    [0-9]*)
      if [[ "$choice" -ge 0 && "$choice" -lt "${#current_items[@]}" ]]; then
        IFS='|' read -r name cmd args <<< "${current_items[$choice]}"
        if [[ -z "$cmd" ]]; then
          stack+=("$name")
        else
          run_cmd "$name" "$cmd" "$args"
        fi
      fi
      ;;
    s|S)
      read -rp "请输入搜索关键字: " kw
      search_items "$kw" || continue
      ;;
    b|B)
      ((${#stack[@]}>1)) && unset 'stack[-1]' || echo "已在主菜单"
      ;;
    q|Q)
      clear; echo "👋 再见！"; exit 0 ;;
    *)
      echo "⚠️ 无效输入"; sleep 0.5 ;;
  esac
done
