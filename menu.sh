
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

  echo -e "\033[1;34mℹ️  已将脚本内容写入临时文件：$TMP_SCRIPT\033[0m"
  echo -e "\033[1;34m➡️  正在以 root 权限重新运行...\033[0m"

  exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
  exit $?
fi
# ====== 提权结束 ======

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

mapfile -t ALL_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")
TOTAL=${#ALL_LINES[@]}
PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))

# ====== 色彩定义 ======
C_RESET="\033[0m"
C_BOX="\033[1;38;5;202m"
C_TITLE="\033[1;38;5;220m"
C_KEY="\033[1;32m"
C_NAME="\033[1;38;5;39m"
C_HINT="\033[1;32m"
C_DIV="\033[38;5;240m"

# ====== 宽度计算（支持全角字符） ======
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
  [ $left_pad -lt 0 ] && left_pad=0
  [ $right_pad -lt 0 ] && right_pad=0
  printf "%b║%*s%b%s%b%*s%b║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX" "$C_RESET"
}

# ====== 菜单页 ======
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
      name="${DISPLAY_LINES[idx]%%|*}"
      draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${name}${C_RESET}"
    else
      draw_text ""
    fi
  done

  draw_mid
  draw_text "第 $page/$PAGES 页   共 ${#DISPLAY_LINES[@]} 项"
  draw_text "[ n ] 下一页   [ b ] 上一页"
  draw_text "[ q ] 上一级     [ 0-9 ] 选择"
  draw_bot
}

# ====== 执行选项 ======
run_slot() {
  local page="$1" slot="$2"
  local start=$(( (page-1)*PER_PAGE ))
  local idx=$((start+slot))
  if (( idx<0 || idx>=${#DISPLAY_LINES[@]} )); then
    echo "❌ 无效选项"
    read -rp "按回车返回..." _
    return
  fi

  selected="${DISPLAY_LINES[idx]}"
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

# ====== 全局搜索（仅标题匹配） ======
search_lines() {
  local keyword="$1"
  MENU_STACK+=("DISPLAY_LINES:$DISPLAY_LINES" "PAGE:$page")  # 保存当前状态
  DISPLAY_LINES=()
  for line in "${ALL_LINES[@]}"; do
    name="${line%%|*}"
    if [[ "${name,,}" == *"${keyword,,}"* ]]; then
      DISPLAY_LINES+=("$line")
    fi
  done
  TOTAL=${#DISPLAY_LINES[@]}
  PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))
  page=1
}

# ====== 主循环 ======
DISPLAY_LINES=("${ALL_LINES[@]}")
MENU_STACK=()  # 状态堆栈
page=1

while true; do
  print_page "$page"
  printf "%b选项 (0-9 or 关键字): %b" "$C_HINT" "$C_RESET"
  read -r key || true

  case "$key" in
    [0-9]) run_slot "$page" "$key" ;;
    n|N) ((page<PAGES)) && ((page++)) || { echo "已是最后一页"; read -rp "按回车返回..." _; } ;;
    b|B) ((page>1)) && ((page--)) || { echo "已是第一页"; read -rp "按回车返回..." _; } ;;
    q|Q)
      if (( ${#MENU_STACK[@]} > 0 )); then
        # 弹出上一级菜单
        DISPLAY_LINES_STATE="${MENU_STACK[-2]}"
        page_STATE="${MENU_STACK[-1]}"
        unset MENU_STACK[-1] MENU_STACK[-1]
        DISPLAY_LINES="${DISPLAY_LINES_STATE#DISPLAY_LINES:}"
        page="${page_STATE#PAGE:}"
        TOTAL=${#DISPLAY_LINES[@]}
        PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))
      else
        clear; echo "👋 再见！"; exit 0
      fi
      ;;
    "") continue ;;
    *) 
      if [[ ! "$key" =~ ^[0-9]$ ]]; then
        search_lines "$key"
        if ((TOTAL==0)); then
          echo "⚠️ 未找到匹配项: $key"
          read -rp "按回车返回..." _
          # 回到上一级菜单，如果堆栈为空，则显示主菜单
          if (( ${#MENU_STACK[@]} > 0 )); then
            DISPLAY_LINES_STATE="${MENU_STACK[-2]}"
            page_STATE="${MENU_STACK[-1]}"
            unset MENU_STACK[-1] MENU_STACK[-1]
            DISPLAY_LINES="${DISPLAY_LINES_STATE#DISPLAY_LINES:}"
            page="${page_STATE#PAGE:}"
          else
            DISPLAY_LINES=("${ALL_LINES[@]}")
            page=1
          fi
          TOTAL=${#DISPLAY_LINES[@]}
          PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))
        else
          page=1
        fi
      fi
      ;;
  esac
done
