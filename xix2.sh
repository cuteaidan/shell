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

mapfile -t ALL_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")

# ====== 色彩定义 ======
C_RESET="\033[0m"
C_BOX="\033[1;38;5;202m"
C_TITLE="\033[1;38;5;220m"
C_KEY="\033[1;32m"
C_NAME="\033[1;38;5;39m"
C_HINT="\033[1;32m"
C_DIV="\033[38;5;240m"

# ====== 字符宽度计算（全角支持） ======
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

# ====== 解析配置构建菜单树 ======
declare -A CMD_MAP      # parent::name -> command
declare -A CHILDREN     # parent -> 子项，用 \x1f 分隔
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
  [ $parts_len -lt 2 ] && continue
  cmd_field="${parts[parts_len-1]}"
  path_components=()
  for ((i=0;i<parts_len-1;i++)); do
    part="$(echo -n "${parts[i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$part" ] && path_components+=("$part")
  done
  [ ${#path_components[@]} -eq 0 ] && continue
  leaf="${path_components[-1]}"
  parent_arr=("${path_components[@]:0:${#path_components[@]}-1}")
  parent_key="${#parent_arr[@]}" && [ "${#parent_arr[@]}" -gt 0 ] && parent_key="$(_join_path parent_arr)" || parent_key="ROOT"

  # 注册子项
  CHILDREN[$parent_key]="${CHILDREN[$parent_key]:-}${leaf}${SEP}"
  CMD_MAP["$parent_key::$leaf"]="$cmd_field"
done

# ====== 获取菜单子项数组 ======
_get_children_array() {
  local key="$1"
  local -a out=()
  local raw="${CHILDREN[$key]:-}"
  [ -z "$raw" ] && return
  IFS=$'\x1f' read -r -a temp <<< "$raw"
  for v in "${temp[@]}"; do [ -n "$v" ] && out+=("$v"); done
  echo "${out[@]}"
}

# ====== 打印菜单 ======
print_page_view() {
  local page="$1"
  shift
  local -a items=("$@")
  local total=${#items[@]}
  local pages=$(( (total + PER_PAGE - 1)/PER_PAGE ))
  [ $pages -lt 1 ] && pages=1
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

# ====== 执行命令 ======
run_selected() {
  local parent="$1" name="$2"
  local cmd="${CMD_MAP[$parent::$name]:-}"
  [ -z "$cmd" ] && return 2
  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${name}${C_RESET}"
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
  return 0
}

# ====== 搜索功能 ======
search_and_show() {
  local keyword="$1"
  [ -z "$keyword" ] && return 1
  kw_lc="$(echo "$keyword" | tr '[:upper:]' '[:lower:]')"
  local -a matches=()
  for k in "${!CMD_MAP[@]}"; do
    name="${k##*::}"
    lc_name="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lc_name" == *"$kw_lc"* ]]; then
      matches+=("$name|$k|${CMD_MAP[$k]}")
    fi
  done
  if [ ${#matches[@]} -eq 0 ]; then
    echo "❌ 未找到匹配项，输入 p 返回全部列表。"
    read -rp "输入: " ans || true
    [[ "$ans" == "p" ]] && return 2
    return 1
  fi

  local page=1
  while true; do
    local -a disp=()
    for m in "${matches[@]}"; do
      disp+=("${m%%|*}")
    done
    print_page_view "$page" "${disp[@]}"
    printf "%b请输入编号 (0-9) 执行， p 返回全部列表, q 退出: %b" "$C_HINT" "$C_RESET"
    read -r in || true
    case "$in" in
      p|P) return 2 ;;
      q|Q) clear; echo "👋 再见！"; exit 0 ;;
      [0-9]*)
        idx=$(( (page-1)*PER_PAGE + in ))
        if (( idx >= 0 && idx < ${#matches[@]} )); then
          sel="${matches[$idx]}"
          sel_name="${sel%%|*}"
          sel_cmd="${sel##*|}"
          clear
          echo -e "${C_KEY}👉 正在执行：${C_NAME}${sel_name}${C_RESET}"
          echo -e "${C_DIV}-----------------------------------------${C_RESET}"
          if [[ "$sel_cmd" =~ ^CMD: ]]; then eval "${sel_cmd#CMD:}"; 
          elif [[ "$sel_cmd" =~ ^https?:// ]]; then bash <(curl -fsSL "$sel_cmd"); 
          else eval "$sel_cmd"; fi
          echo -e "${C_DIV}-----------------------------------------${C_RESET}"
          read -rp $'按回车返回搜索结果...' _
        else
          echo "❌ 无效编号"; sleep 0.5
        fi
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
  # 展开叶子节点及一级菜单
  view_items=()
  for item in $(_get_children_array "$current_parent"); do
    key="$current_parent::$item"
    if [ -n "${CHILDREN[$key]:-}" ]; then
      # 有子菜单，只显示父菜单名称
      view_items+=("$item")
    else
      # 叶子节点
      view_items+=("$item")
    fi
  done

  VIEW_TOTAL=${#view_items[@]}
  VIEW_PAGES=$(( (VIEW_TOTAL+PER_PAGE-1)/PER_PAGE ))
  [ $VIEW_PAGES -lt 1 ] && VIEW_PAGES=1
  print_page_view "$page" "${view_items[@]}"

  printf "%b请输入选项 (0-9/n/b/p/q/搜索): %b" "$C_HINT" "$C_RESET"
  read -r key || true
  key="$(echo -n "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  case "$key" in
    [0-9])
      idx=$(( (page-1)*PER_PAGE + key ))
      if (( idx>=0 && idx<VIEW_TOTAL )); then
        sel="${view_items[$idx]}"
        run_selected "$current_parent" "$sel"
        rc=$?
        if [ "$rc" -eq 2 ]; then
          # 进入子菜单
          current_parent="$current_parent::$sel"
          page=1
        fi
      else
        echo "❌ 无效选项"; read -rp "按回车返回..." _
      fi
      ;;
    n|N) ((page++)); ((page>VIEW_PAGES)) && page=$VIEW_PAGES ;;
    b|B) 
      if [[ "$current_parent" == "ROOT" ]]; then
        echo "已是主菜单"; read -rp "按回车返回..." _
      else
        current_parent="${current_parent%::*}"; [ -z "$current_parent" ] && current_parent="ROOT"
        page=1
      fi
      ;;
    p|P)
      current_parent="ROOT"
      page=1
      ;;
    q|Q) clear; echo "👋 再见！"; exit 0 ;;
    "") ;;
    *) search_and_show "$key" ;;
  esac
done
