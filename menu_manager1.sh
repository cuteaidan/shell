#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权 ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m[警告]\033[0m 检测到当前用户不是 root。"
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[1;31m[错误]\033[0m 系统未安装 sudo，请使用 root 用户运行本脚本。"
    exit 1
  fi
  echo -e "\033[1;32m[提示]\033[0m 请输入当前用户的密码以获取管理员权限..."

  if [ -f "$0" ] && [ -r "$0" ]; then
    exec sudo -E bash "$0" "$@"
    exit $?
  fi

  TMP_SCRIPT="$(mktemp /tmp/menu_manager.XXXXXX.sh)"
  if [ -e "$0" ]; then
    if ! cat "$0" > "$TMP_SCRIPT" 2>/dev/null; then
      cat > "$TMP_SCRIPT"
    fi
  else
    cat > "$TMP_SCRIPT"
  fi
  chmod +x "$TMP_SCRIPT"

  echo -e "\033[1;34m[信息]\033[0m 已将脚本内容写入临时文件：$TMP_SCRIPT"
  echo -e "\033[1;34m[信息]\033[0m 正在以 root 权限重新运行..."
  exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
  exit $?
fi
# ====== 提权结束 ======

CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts1.conf"
PER_PAGE=10
BOX_WIDTH=50
LEFT_INDENT="        "

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
  echo -e "\033[1;31m[错误]\033[0m 无法下载配置文件: $CONFIG_URL"
  exit 1
fi

mapfile -t RAW_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")

# ====== 色彩定义 ======
C_RESET="\033[0m"
C_BOX="\033[1;38;5;202m"
C_TITLE="\033[1;38;5;220m"
C_KEY="\033[1;32m"
C_DIR="\033[1;38;5;39m"
C_ITEM="\033[1;32m"
C_HINT="\033[1;32m"
C_DIV="\033[38;5;240m"

# ====== 宽度计算（支持全角） ======
str_width() {
  local text="$1" len=0 i ch code
  text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
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

draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }

draw_text() {
  local text="$1" width padding
  width=$(str_width "$text")
  padding=$((BOX_WIDTH - width - ${#LEFT_INDENT} - 2))
  ((padding<0)) && padding=0
  printf "%b║%s%b%*s%b║%b\n" "$C_BOX" "$LEFT_INDENT" "$text" "$padding" "" "$C_BOX" "$C_RESET"
}

draw_title() {
  local title="$1" width left_pad right_pad
  width=$(str_width "$title")
  left_pad=$(( (BOX_WIDTH - width - 2)/2 ))
  right_pad=$((BOX_WIDTH - width - left_pad - 2))
  printf "%b║%*s%b%s%b%*s%b║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX" "$C_RESET"
}

# ====== 构建层级结构 ======
declare -A MENU_MAP
declare -a path_stack
for line in "${RAW_LINES[@]}"; do
  indent=$(expr match "$line" ' *')
  content=$(echo "$line" | sed 's/^ *//')
  while ((${#path_stack[@]} > indent)); do
    unset "path_stack[$(( ${#path_stack[@]} - 1 ))]"
  done
  current_path="${path_stack[*]}"
  MENU_MAP["$current_path"]+=$'\n'"$content"
  if [[ "$content" =~ ^\[.*\]$ ]]; then
    path_stack+=("$content")
  fi
done

# ====== 显示菜单页 ======
print_menu() {
  local context="$1" lines=() line idx=0
  mapfile -t lines <<< "${MENU_MAP[$context]}"
  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp)"
  draw_mid

  for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^\[.*\]$ ]]; then
      draw_text "${C_KEY}[$idx]${C_RESET} ${C_DIR}${line//[\[\]]/}${C_RESET}"
    else
      name="${line%%|*}"
      draw_text "${C_KEY}[$idx]${C_RESET} ${C_ITEM}${name}${C_RESET}"
    fi
    ((idx++))
  done

  draw_mid
  draw_text "[ n ] 下一页   [ b ] 上一页"
  draw_text "[ q ] 返回上级 / 退出"
  draw_bot
}

# ====== 执行功能 ======
run_item() {
  local line="$1"
  local name="${line%%|*}"
  local rest="${line#*|}"
  local cmd="${rest%%|*}"
  local args=""
  [[ "$rest" == *"|"* ]] && args="${rest#*|}"

  clear
  echo -e "${C_KEY}[执行]${C_RESET} 正在运行：${C_ITEM}${name}${C_RESET}"
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
declare -a stack
current_path=""

while true; do
  print_menu "$current_path"
  printf "%b选项 (数字或关键字): %b" "$C_HINT" "$C_RESET"
  read -r key || true
  mapfile -t current_lines <<< "${MENU_MAP[$current_path]}"
  case "$key" in
    q|Q)
      if ((${#stack[@]} > 0)); then
        current_path="${stack[-1]}"
        unset "stack[$(( ${#stack[@]} - 1 ))]"
      else
        clear; echo -e "\033[1;34m[退出]\033[0m 感谢使用，再见。"; exit 0
      fi
      ;;
    [0-9])
      ((key<${#current_lines[@]})) || continue
      sel="${current_lines[$key]}"
      if [[ "$sel" =~ ^\[.*\]$ ]]; then
        stack+=("$current_path")
        current_path="$current_path
$sel"
      else
        run_item "$sel"
      fi
      ;;
    *)
      # 模糊搜索
      matches=()
      for full in "${!MENU_MAP[@]}"; do
        mapfile -t sub <<< "${MENU_MAP[$full]}"
        for l in "${sub[@]}"; do
          [[ -n "$l" && "$l" != "["*"]" ]] && [[ "${l,,}" == *"${key,,}"* ]] && matches+=("$l")
        done
      done
      if ((${#matches[@]}==0)); then
        echo -e "\033[1;33m[提示]\033[0m 未找到匹配项: $key"; read -rp "按回车返回..." _
      else
        clear; draw_line; draw_title "搜索结果"; draw_mid
        idx=0; for l in "${matches[@]}"; do
          name="${l%%|*}"
          draw_text "${C_KEY}[$idx]${C_RESET} ${C_ITEM}${name}${C_RESET}"; ((idx++))
        done
        draw_bot
        printf "%b选择执行项编号 (或 q 返回): %b" "$C_HINT" "$C_RESET"
        read -r n || true
        [[ "$n" =~ ^[0-9]+$ ]] && ((n<${#matches[@]})) && run_item "${matches[$n]}"
      fi
      ;;
  esac
done
