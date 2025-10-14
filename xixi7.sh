#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权（兼容 bash <(curl …) / curl | bash / 本地文件） ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m⚠️  检测到当前用户不是 root。\033[0m"
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[1;31m❌ 系统未安装 sudo，请使用 root 用户运行本脚本。\033[0m"
    exit 1
  fi
  echo -e "\033[1;32m🔑  请输入当前用户的密码以获取管理员权限（sudo）...\033[0m"

  TMP_SCRIPT="$(mktemp /tmp/menu_manager.XXXXXX.sh)"
  if [ -e "$0" ]; then
    if ! cat "$0" > "$TMP_SCRIPT" 2>/dev/null; then
      cat > "$TMP_SCRIPT"
    fi
  else
    cat > "$TMP_SCRIPT"
  fi
  chmod +x "$TMP_SCRIPT"

  exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
fi
# ====== 提权检测结束 ======

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

# ====== 菜单数据解析 ======
declare -A CMD_MAP       # parent::leaf -> command
declare -A CHILDREN      # parent -> leaf1\x1fleaf2...
SEP=$'\x1f'

_join_path() {
  local -n arr=$1
  local res=""
  for p in "${arr[@]}"; do
    res=${res:+$res::}$p
  done
  echo "$res"
}

# 构建树
for line in "${ALL_LINES[@]}"; do
  IFS='|' read -r -a parts <<< "$line"
  [ ${#parts[@]} -lt 2 ] && continue
  cmd="${parts[-1]}"
  # 获取路径层级
  path=()
  for ((i=0;i<${#parts[@]}-1;i++)); do
    part="${parts[i]}"
    part="$(echo -n "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$part" ] && path+=("$part")
  done
  [ ${#path[@]} -eq 0 ] && continue
  leaf="${path[-1]}"
  parent="ROOT"
  [ ${#path[@]} -gt 1 ] && parent="$(_join_path "${path[@]:0:${#path[@]}-1}")"
  # 添加到 CHILDREN
  existing="${CHILDREN[$parent]:-}"
  [[ ":$existing:" != *":$leaf:"* ]] && CHILDREN[$parent]="${existing}${leaf}${SEP}"
  # 添加命令
  CMD_MAP["$parent::$leaf"]="$cmd"
done

# ====== 辅助函数 ======
_get_children_array() {
  local key="$1" arr=() raw="${CHILDREN[$key]:-}"
  [ -z "$raw" ] && echo && return
  IFS=$'\x1f' read -r -a arr <<< "$raw"
  for v in "${arr[@]}"; do [ -n "$v" ] && echo "$v"; done
}

print_page_view() {
  local page="$1"; shift
  local -a items=("$@")
  local total=${#items[@]}
  local pages=$(( (total+PER_PAGE-1)/PER_PAGE )); [ $pages -lt 1 ] && pages=1
  local start=$(( (page-1)*PER_PAGE )); local end=$(( start+PER_PAGE-1 )); ((end>=total)) && end=$((total-1))

  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp)"
  draw_mid
  for slot in $(seq 0 $((PER_PAGE-1))); do
    idx=$((start+slot))
    if (( idx<=end )); then
      draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${items[idx]}${C_RESET}"
    else
      draw_text ""
    fi
  done
  draw_mid
  draw_text "第 $page/$pages 页   共 $total 项"
  draw_text "[ n ] 下一页   [ b ] 上一页"
  draw_text "[ p ] 返回上级   [ q ] 退出"
  draw_bot
}

run_selected() {
  local parent="$1" leaf="$2" cmd="${CMD_MAP[$parent::$leaf]:-}"
  [ -z "$cmd" ] && return 2 # 没有命令 -> 进入子菜单
  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${leaf}${C_RESET}"
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  if [[ "$cmd" =~ ^CMD: ]]; then eval "${cmd#CMD:}"
  elif [[ "$cmd" =~ ^https?:// ]]; then bash <(curl -fsSL "$cmd")
  else eval "$cmd"
  fi
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  read -rp $'按回车返回菜单...' _
  return 0
}

# ====== 全局搜索 ======
search_and_show() {
  local keyword="$1"; [ -z "$keyword" ] && return
  local -a matches=() name cmd key
  keyword_lc="$(echo "$keyword" | tr '[:upper:]' '[:lower:]')"
  for k in "${!CMD_MAP[@]}"; do
    name="${k##*::}"; key="$k"; cmd="${CMD_MAP[$k]}"
    [[ "$(echo "$name" | tr '[:upper:]' '[:lower:]')" == *"$keyword_lc"* ]] && matches+=("$key::$name::$cmd")
  done
  [ ${#matches[@]} -eq 0 ] && { echo "❌ 未找到匹配项，输入 p 返回菜单。"; read -rp "输入: " ans; [[ "$ans" == "p" ]] && return 2; return; }

  local page=1
  while true; do
    local -a disp=()
    for m in "${matches[@]}"; do disp+=("${m#*::}"); done
    print_page_view "$page" "${disp[@]}"
    printf "%b请输入编号(0-9)执行，p返回菜单，q退出: %b" "$C_HINT" "$C_RESET"
    read -r in || true
    case "$in" in
      p|P) return 2 ;;
      q|Q) clear; echo "👋 再见！"; exit 0 ;;
      [0-9])
        idx=$(( (page-1)*PER_PAGE + in ))
        (( idx<0 || idx>=${#matches[@]} )) && { echo "❌ 无效编号"; read -rp "按回车继续..." _; continue; }
        sel="${matches[$idx]}"; sel_key="${sel%%::*}"; sel_name="${sel#*::}"; sel_cmd="${sel##*::}"
        clear
        echo -e "${C_KEY}👉 正在执行：${C_NAME}${sel_name}${C_RESET}"
        echo -e "${C_DIV}-----------------------------------------${C_RESET}"
        [[ "$sel_cmd" =~ ^CMD: ]] && eval "${sel_cmd#CMD:}" || [[ "$sel_cmd" =~ ^https?:// ]] && bash <(curl -fsSL "$sel_cmd") || eval "$sel_cmd"
        echo -e "${C_DIV}-----------------------------------------${C_RESET}"
        read -rp $'按回车返回搜索结果...' _
        ;;
      n|N) ((page++)); maxp=$(( (${#matches[@]}+PER_PAGE-1)/PER_PAGE )); ((page>maxp)) && page=$maxp ;;
      b|B) ((page--)); ((page<1)) && page=1 ;;
      *) echo "⚠️ 无效输入"; sleep 0.5 ;;
    esac
  done
}

# ====== 主循环 ======
current_parent="ROOT"; page=1
while true; do
  # 首页或子菜单：显示子菜单名称+叶子节点
  IFS=$'\n' read -r -d '' -a view_items < <(
    _get_children_array "$current_parent"
    printf '\0'
  )
  VIEW_TOTAL=${#view_items[@]}; VIEW_PAGES=$(( (VIEW_TOTAL+PER_PAGE-1)/PER_PAGE )); [ $VIEW_PAGES -lt 1 ] && VIEW_PAGES=1
  print_page_view "$page" "${view_items[@]}"

  printf "%b请输入选项 (0-9/n/b/p/q/搜索): %b" "$C_HINT" "$C_RESET"
  read -r key || true
  key="$(echo -n "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  case "$key" in
    [0-9])
      idx=$(( (page-1)*PER_PAGE + key )); (( idx<0 || idx>=VIEW_TOTAL )) && { echo "❌ 无效选项"; read -rp "按回车返回..." _; continue; }
      sel="${view_items[$idx]}"
      run_selected "$current_parent" "$sel"
      rc=$?
      if [ "$rc" -eq 2 ]; then
        new_parent="$current_parent::$sel"; [ "$current_parent" == "ROOT" ] && new_parent="$sel"
        if [ -n "${CHILDREN[$new_parent]:-}" ]; then current_parent="$new_parent"; page=1
        else echo "⚠️ 当前项无下级且不可执行"; read -rp "按回车返回..." _; fi
      fi
      ;;
    n|N) ((page<VIEW_PAGES)) && ((page++)) || { echo "已是最后一页"; read -rp "按回车返回..." _; } ;;
    b|B)
      if [ "$current_parent" == "ROOT" ]; then echo "已是主菜单"; read -rp "按回车返回..." _; else current_parent="${current_parent%::*}"; page=1; fi
      ;;
    p|P) current_parent="ROOT"; page=1 ;;
    q|Q) clear; echo "👋 再见！"; exit 0 ;;
    "") continue ;;
    *) search_and_show "$key" ;;
  esac
done
