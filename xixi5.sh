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

  TMP_SCRIPT="$(mktemp /tmp/menu.XXXXXX.sh)"
  if [ -f "$0" ] && [ -r "$0" ]; then
    cat "$0" >"$TMP_SCRIPT"
  else
    cat >"$TMP_SCRIPT"
  fi
  chmod +x "$TMP_SCRIPT"
  exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
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

mapfile -t ALL_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")

# ====== 颜色 ======
C_RESET="\033[0m"
C_BOX="\033[1;38;5;202m"
C_TITLE="\033[1;38;5;220m"
C_KEY="\033[1;32m"
C_NAME="\033[1;38;5;39m"
C_HINT="\033[1;32m"

# ====== 工具函数 ======
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

# ====== 构建菜单树 ======
declare -A CMD_MAP
declare -A CHILDREN
SEP=$'\x1f'

_join_path() {
  local -n arr=$1
  local res=""
  for part in "${arr[@]}"; do
    if [ -z "$res" ]; then res="$part"; else res="$res::$part"; fi
  done
  echo "$res"
}

for line in "${ALL_LINES[@]}"; do
  IFS='|' read -r -a parts <<< "$line"
  parts_len=${#parts[@]}
  (( parts_len < 2 )) && continue

  cmd="${parts[-1]}"
  path=()
  for ((i=0;i<parts_len-1;i++)); do
    p="$(echo -n "${parts[i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$p" ] && path+=("$p")
  done
  (( ${#path[@]} == 0 )) && continue

  leaf="${path[-1]}"
  parent_key="ROOT"
  if (( ${#path[@]} > 1 )); then
    parent_arr=("${path[@]:0:${#path[@]}-1}")
    parent_key="$(_join_path parent_arr)"
  fi

  CMD_MAP["${parent_key}::${leaf}"]="$cmd"
  existing="${CHILDREN[$parent_key]:-}"
  CHILDREN[$parent_key]="${existing}${leaf}${SEP}"
done

# 补充：确保ROOT含有所有“孤立叶子节点”
for key in "${!CMD_MAP[@]}"; do
  parent="${key%::*}"
  leaf="${key##*::}"
  if [ "$parent" != "ROOT" ] && [ -z "${CHILDREN[$parent]:-}" ]; then
    CHILDREN["ROOT"]+="${leaf}${SEP}"
  fi
done

# ====== 获取子项 ======
_get_children_array() {
  local key="$1"
  local -a result=()
  local raw="${CHILDREN[$key]:-}"
  [ -z "$raw" ] && echo "" && return
  IFS=$'\x1f' read -r -a temp <<< "$raw"
  for t in "${temp[@]}"; do [ -n "$t" ] && result+=("$t"); done
  echo "${result[@]}"
}

# ====== 分页展示 ======
print_page_view() {
  local page="$1"
  shift
  local -a items=("$@")
  local total=${#items[@]}
  local pages=$(( (total + PER_PAGE - 1) / PER_PAGE ))
  ((pages<1)) && pages=1
  local start=$(( (page-1)*PER_PAGE ))
  local end=$(( start+PER_PAGE-1 ))
  ((end>=total)) && end=$((total-1))

  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp)"
  draw_mid
  for slot in $(seq 0 $((PER_PAGE-1))); do
    idx=$((start+slot))
    if ((idx<=end)); then
      draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${items[idx]}${C_RESET}"
    else
      draw_text ""
    fi
  done
  draw_mid
  draw_text "第 $page/$pages 页   共 $total 项"
  draw_text "[ n ] 下一页   [ b ] 上一页"
  draw_text "[ p ] 返回主菜单   [ q ] 退出"
  draw_bot
}

# ====== 执行 ======
run_selected() {
  local parent_key="$1"
  local name="$2"
  local cmd="${CMD_MAP[$parent_key::$name]:-}"
  if [ -z "$cmd" ]; then return 2; fi

  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${name}${C_RESET}"
  echo -e "-----------------------------------------"

  if [[ "$cmd" =~ ^https?:// ]]; then
    bash <(curl -fsSL "$cmd")
  else
    eval "$cmd"
  fi
  echo -e "-----------------------------------------"
  read -rp "按回车返回菜单..." _
}

# ====== 全局搜索 ======
search_and_show() {
  local keyword="$1"
  [ -z "$keyword" ] && return 1
  local -a matches=()
  kw_lc="$(echo "$keyword" | tr '[:upper:]' '[:lower:]')"
  for key in "${!CMD_MAP[@]}"; do
    name="${key##*::}"
    name_lc="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    [[ "$name_lc" == *"$kw_lc"* ]] && matches+=("$name|$key")
  done
  (( ${#matches[@]} == 0 )) && { echo "❌ 未找到匹配项"; read -rp "按回车返回..." _; return 1; }

  local page=1
  while true; do
    local -a disp=()
    for m in "${matches[@]}"; do disp+=("${m%%|*}"); done
    print_page_view "$page" "${disp[@]}"
    printf "%b输入编号(0-9)/p返回主菜单/q退出/关键词继续搜索:%b" "$C_HINT" "$C_RESET"
    read -r in || true
    case "$in" in
      p|P) return 3 ;;  # ✅ 返回主菜单信号
      q|Q) clear; echo "👋 再见！"; exit 0 ;;
      [0-9])
        idx=$(( (page-1)*PER_PAGE + in ))
        (( idx>=0 && idx<${#matches[@]} )) || continue
        sel="${matches[$idx]}"
        sel_name="${sel%%|*}"
        sel_key="${sel#*|}"
        parent="${sel_key%::*}"
        run_selected "$parent" "$sel_name"
        ;;
      n|N) ((page++)); max=$(( (${#matches[@]} + PER_PAGE -1)/PER_PAGE )); ((page>max)) && page=$max ;;
      b|B) ((page--)); ((page<1)) && page=1 ;;
      *) search_and_show "$in"; return $? ;;
    esac
  done
}

# ====== 主循环 ======
current_parent="ROOT"
page=1
while true; do
  IFS=' ' read -r -a view_items <<< "$(_get_children_array "$current_parent")"
  total=${#view_items[@]}
  ((total==0)) && view_items=("（无可显示项）")
  print_page_view "$page" "${view_items[@]}"

  printf "%b请输入选项 (0-9/n/b/p/q/搜索):%b" "$C_HINT" "$C_RESET"
  read -r key || true
  key="$(echo "$key" | xargs)"
  case "$key" in
    [0-9])
      idx=$(( (page-1)*PER_PAGE + key ))
      (( idx<0 || idx>=total )) && continue
      sel="${view_items[$idx]}"
      run_selected "$current_parent" "$sel" || rc=$?
      if [ "$rc" -eq 2 ]; then
        [ "$current_parent" == "ROOT" ] && new="$sel" || new="${current_parent}::${sel}"
        if [ -n "${CHILDREN[$new]:-}" ]; then current_parent="$new"; page=1; fi
      fi
      ;;
    n|N) ((page++)); max=$(( (total+PER_PAGE-1)/PER_PAGE )); ((page>max)) && page=$max ;;
    b|B)
      if [ "$current_parent" == "ROOT" ]; then
        echo "已在主菜单"; read -rp "按回车返回..." _
      else
        [[ "$current_parent" == *"::"* ]] && current_parent="${current_parent%::*}" || current_parent="ROOT"
        page=1
      fi
      ;;
    p|P) current_parent="ROOT"; page=1 ;;
    q|Q) clear; echo "👋 再见！"; exit 0 ;;
    "") ;;
    *) search_and_show "$key"; [ $? -eq 3 ] && { current_parent="ROOT"; page=1; } ;;
  esac
done
