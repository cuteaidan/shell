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
  cat > "$TMP_SCRIPT"
  chmod +x "$TMP_SCRIPT"
  echo -e "\033[1;34mℹ️  已将脚本内容写入临时文件：$TMP_SCRIPT\033[0m"
  echo -e "\033[1;34m➡️  正在以 root 权限重新运行...\033[0m"
  exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
  exit $?
fi

# ====== 配置 ======
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/script2.conf"
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

# ====== 宽度计算 ======
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

# ====== 边框 ======
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

# ====== 分级菜单解析 ======
declare -A MENU_TREE
declare -A MENU_CMD
declare -A MENU_PARENT
declare -A LEAF_FLAG
ROOT_KEY="ROOT"
MENU_TREE["$ROOT_KEY"]=""

for line in "${RAW_LINES[@]}"; do
  IFS='|' read -ra parts <<< "$line"
  parts_len=${#parts[@]}
  [ $parts_len -lt 2 ] && continue

  name="${parts[0]}"
  cmd="${parts[-1]}"

  parent="$ROOT_KEY"
  full_name=""
  for ((i=1;i<parts_len-1;i++)); do
    fld="${parts[i]}"
    [ -z "$fld" ] && continue
    full_path="$parent/$fld"
    [ -z "${MENU_TREE[$parent]+x}" ] && MENU_TREE["$parent"]=""
    # 保留完整显示路径
    MENU_TREE["$parent"]="${MENU_TREE["$parent"]} $fld"
    MENU_PARENT["$full_path"]="$parent"
    parent="$full_path"
    full_name="$fld"
  done

  # 添加叶子节点
  leaf_path="$parent/$name"
  [ -z "${MENU_TREE[$parent]+x}" ] && MENU_TREE["$parent"]=""
  MENU_TREE["$parent"]="${MENU_TREE["$parent"]} $name"
  MENU_PARENT["$leaf_path"]="$parent"
  if [ -n "$cmd" ]; then
    MENU_CMD["$leaf_path"]="$cmd"
    LEAF_FLAG["$leaf_path"]=1
  fi
done

# ====== 菜单栈 ======
MENU_STACK=()
CURRENT_PATH="$ROOT_KEY"

# ====== 渲染菜单 ======
render_menu() {
  local path="$1"
  local children=(${MENU_TREE[$path]})
  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp)"
  draw_mid
  for i in $(seq 0 $((PER_PAGE-1))); do
    if (( i < ${#children[@]} )); then
      local display_name="$children[i]"
      # 显示完整路径给用户
      local full_path="$path/$display_name"
      if [ "$path" != "$ROOT_KEY" ]; then
        display_name=$(echo "$full_path" | sed "s|$ROOT_KEY/||g" | tr '/' ' > ')
      fi
      draw_text "${C_KEY}[$i]${C_RESET} ${C_NAME}${display_name}${C_RESET}"
    else
      draw_text ""
    fi
  done
  draw_mid
  draw_text "第 1/1 页   共 ${#children[@]} 项"
  draw_text "[ p ] 返回上一级   [ q ] 退出"
  draw_text "[ 输入关键字直接搜索叶子节点 ]"
  draw_bot
}

# ====== 执行叶子节点 ======
run_leaf() {
  local full_path="$1"
  local cmd="${MENU_CMD[$full_path]}"
  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${full_path##*/}${C_RESET}"
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  if [[ "$cmd" =~ ^CMD: ]]; then
    eval "${cmd#CMD:}"
  elif [[ "$cmd" =~ ^https?:// ]]; then
    bash <(curl -fsSL "$cmd")
  else
    eval "$cmd"
  fi
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  read -rp $'按回车返回菜单...' _
}

# ====== 全局模糊搜索 ======
search_leaf() {
  local keyword="$1"
  keyword=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
  local results=()
  for key in "${!LEAF_FLAG[@]}"; do
    local name="${key##*/}"
    name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    if [[ "$name_lower" == *"$keyword"* ]]; then
      results+=("$key")
    fi
  done

  if [ ${#results[@]} -eq 0 ]; then
    echo "⚠️ 未找到匹配项"
    read -rp "按回车返回菜单..." _
    return
  fi

  clear
  draw_line
  draw_title "搜索结果"
  draw_mid
  for i in "${!results[@]}"; do
    local display_name="${results[i]}"
    display_name=$(echo "$display_name" | sed "s|$ROOT_KEY/||g" | tr '/' ' > ')
    draw_text "${C_KEY}[$i]${C_RESET} ${C_NAME}${display_name}${C_RESET}"
  done
  draw_bot
  read -rp "选择执行: " idx
  [[ "$idx" =~ ^[0-9]+$ ]] && [[ "$idx" -lt ${#results[@]} ]] && run_leaf "${results[idx]}"
}

# ====== 主循环 ======
while true; do
  render_menu "$CURRENT_PATH"
  read -rp "请输入选项或关键字: " input
  case "$input" in
    q|Q) clear; echo "👋 再见！"; exit 0 ;;
    p|P)
      if [ "${#MENU_STACK[@]}" -gt 0 ]; then
        CURRENT_PATH="${MENU_STACK[-1]}"
        unset 'MENU_STACK[-1]'
      fi
      ;;
    [0-9]*)
      children=(${MENU_TREE[$CURRENT_PATH]})
      if (( input < ${#children[@]} )); then
        selected="${children[input]}"
        full_path="$CURRENT_PATH/$selected"
        if [ -n "${LEAF_FLAG[$full_path]+x}" ]; then
          run_leaf "$full_path"
        elif [ -n "${MENU_TREE[$full_path]+x}" ]; then
          MENU_STACK+=("$CURRENT_PATH")
          CURRENT_PATH="$full_path"
        else
          echo "⚠️ 无效选项"; sleep 0.6
        fi
      fi
      ;;
    *)
      search_leaf "$input"
      ;;
  esac
done
