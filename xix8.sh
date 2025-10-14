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
curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"

mapfile -t ALL_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")

# ====== 色彩 ======
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

# ====== 内部安全 key 转换 ======
safe_key() {
  local s="$1"
  echo "$s" | tr ' ' '_' | tr -cd '[:alnum:]_-'
}

# ====== 解析配置 ======
declare -A CMD_MAP
declare -A CHILDREN
declare -A DISPLAY_NAME

SEP=$'\x1f'

_join_path() {
  local -n _arr=$1
  local res=""
  for part in "${_arr[@]}"; do
    [ -z "$res" ] && res="$part" || res="$res::$part"
  done
  echo "$res"
}

for line in "${ALL_LINES[@]}"; do
  IFS='|' read -r -a parts <<< "$line"
  (( ${#parts[@]} < 2 )) && continue
  cmd_field="${parts[-1]}"
  path_components=()
  for ((i=0;i<${#parts[@]}-1;i++)); do
    part="$(echo -n "${parts[i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$part" ] && path_components+=("$part")
  done
  (( ${#path_components[@]} < 1 )) && continue

  leaf="${path_components[-1]}"
  leaf_key=$(safe_key "$leaf")
  DISPLAY_NAME["$leaf_key"]="$leaf"

  parent_key="ROOT"
  if (( ${#path_components[@]} > 1 )); then
    parent_arr=("${path_components[@]:0:${#path_components[@]}-1}")
    parent_key=$(_join_path parent_arr)
    parent_key=$(safe_key "$parent_key")
  fi

  CHILDREN["$parent_key"]+="${leaf_key}${SEP}"
  CMD_MAP["$parent_key::$leaf_key"]="$cmd_field"
done

# ====== 获取 children 数组 ======
_get_children_array() {
  local key="$1"
  local -a out=()
  local raw="${CHILDREN[$key]:-}"
  [ -z "$raw" ] && echo && return
  IFS=$'\x1f' read -r -a temp <<< "$raw"
  for v in "${temp[@]}"; do
    [ -n "$v" ] && out+=("$v")
  done
  for e in "${out[@]}"; do printf '%s\n' "$e"; done
}

# ====== 打印页面 ======
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
    if (( idx<=end )); then
      key="${items[idx]}"
      draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${DISPLAY_NAME[$key]}${C_RESET}"
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

# ====== 执行选项 ======
run_selected() {
  local parent="$1"
  local sel_key="$2"
  local cmd="${CMD_MAP[$parent::$sel_key]:-}"
  if [ -z "$cmd" ]; then
    return 2
  fi
  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${DISPLAY_NAME[$sel_key]}${C_RESET}"
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"

  if [[ "$cmd" =~ ^https?:// ]]; then
    bash <(curl -fsSL "$cmd")
  else
    eval "$cmd"
  fi

  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  read -rp $'按回车返回菜单...' _
  return 0
}

# ====== 搜索 ======
search_and_show() {
  local keyword="$1"
  [ -z "$keyword" ] && return 1
  kw_lc=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
  local -a matches=()
  for key in "${!CMD_MAP[@]}"; do
    name="${key##*::}"
    name_lc=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    [[ "$name_lc" == *"$kw_lc"* ]] && matches+=("$key")
  done
  (( ${#matches[@]} == 0 )) && { echo "❌ 未找到匹配项"; read -rp "按回车返回..." _; return 1; }

  local page=1
  while true; do
    local -a disp=()
    for k in "${matches[@]}"; do
      leaf="${k##*::}"
      disp+=("$leaf")
    done
    print_page_view "$page" "${disp[@]}"
    printf "%b请输入编号 (0-9) 执行, p 返回菜单, q 退出: %b" "$C_HINT" "$C_RESET"
    read -r in || true
    case "$in" in
      p|P) return 0 ;;
      q|Q) clear; echo "👋 再见！"; exit 0 ;;
      [0-9])
        idx=$(( (page-1)*PER_PAGE + in ))
        (( idx < 0 || idx >= ${#matches[@} )) && { echo "❌ 无效编号"; read -rp "按回车继续..." _; continue; }
        sel="${matches[$idx]}"
        sel_leaf="${sel##*::}"
        run_selected "${sel%%::*}" "$sel_leaf"
        ;;
      n|N) ((page++)); maxp=$(( (${#matches[@]}+PER_PAGE-1)/PER_PAGE )); ((page>maxp)) && page=$maxp ;;
      b|B) ((page--)); ((page<1)) && page=1 ;;
      *) echo "⚠️ 无效输入"; sleep 0.5 ;;
    esac
  done
}

# ====== 主循环 ======
current_parent="ROOT"
page=1

while true; do
  IFS=$'\n' read -r -d '' -a view_items < <(_get_children_array "$current_parent" && printf '\0')
  VIEW_TOTAL=${#view_items[@]}
  VIEW_PAGES=$(( (VIEW_TOTAL + PER_PAGE -1)/PER_PAGE ))
  ((VIEW_PAGES<1)) && VIEW_PAGES=1

  print_page_view "$page" "${view_items[@]}"
  printf "%b请输入选项 (0-9/n/b/p/q/搜索): %b" "$C_HINT" "$C_RESET"
  read -r key || true
  key=$(echo -n "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  case "$key" in
    [0-9])
      idx=$(( (page-1)*PER_PAGE + key ))
      (( idx<0 || idx>=VIEW_TOTAL )) && { echo "❌ 无效编号"; sleep 0.5; continue; }
      sel_key="${view_items[idx]}"
      run_selected "$current_parent" "$sel_key"
      ;;
    n|N) ((page++)); ((page>VIEW_PAGES)) && page=VIEW_PAGES ;;
    b|B) ((page--)); ((page<1)) && page=1 ;;
    p|P) current_parent="ROOT"; page=1 ;;
    q|Q) clear; echo "👋 再见！"; exit 0 ;;
    搜索*)
      keyword="${key#搜索}"
      keyword="${keyword#"${keyword%%[![:space:]]*}"}"
      search_and_show "$keyword"
      ;;
    *)
      echo "⚠️ 无效输入"; sleep 0.5 ;;
  esac
done
