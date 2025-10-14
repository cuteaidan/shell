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
  cat > "$TMP_SCRIPT"
  chmod +x "$TMP_SCRIPT"

  echo -e "\033[1;34mℹ️  已将脚本内容写入临时文件：$TMP_SCRIPT\033[0m"
  echo -e "\033[1;34m➡️  正在以 root 权限重新运行...\033[0m"

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

# ====== 字符宽度计算（支持全角字符） ======
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

# ====== 构建菜单树 ======
declare -A CMD_MAP        # key="完整路径" -> 命令
declare -A CHILDREN       # key="父路径" -> 子菜单/叶子，用 \x1f 分隔
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
  # 去掉空格
  for i in "${!parts[@]}"; do
    parts[$i]="$(echo -n "${parts[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  done
  # 过滤空行
  [[ "${#parts[@]}" -lt 2 ]] && continue
  # 找到最后一个非空字段作为命令
  cmd=""
  for ((i=${#parts[@]}-1;i>=0;i--)); do
    [[ -n "${parts[i]}" ]] && { cmd="${parts[i]}"; parts=("${parts[@]:0:i}"); break; }
  done
  # 父路径
  path=()
  for p in "${parts[@]}"; do
    [[ -n "$p" ]] && path+=("$p")
  done
  if [ ${#path[@]} -eq 0 ]; then
    path=("ROOT")
  fi
  leaf="${path[-1]}"
  parent=()
  if [ ${#path[@]} -gt 1 ]; then
    parent=("${path[@]:0:${#path[@]}-1}")
    parent_key="$(_join_path parent)"
  else
    parent_key="ROOT"
  fi
  full_key="$(_join_path path)"
  CMD_MAP["$full_key"]="$cmd"

  # 添加到父子列表
  current="${CHILDREN[$parent_key]:-}"
  if [[ -z "$current" ]]; then
    CHILDREN[$parent_key]="${leaf}${SEP}"
  elif [[ "$current" != *"${leaf}${SEP}"* ]]; then
    CHILDREN[$parent_key]="${current}${leaf}${SEP}"
  fi
done

# ====== 获取子项数组 ======
_get_children_array() {
  local key="$1"
  local -a arr=()
  local raw="${CHILDREN[$key]:-}"
  [[ -z "$raw" ]] && echo && return
  IFS=$'\x1f' read -r -a temp <<< "$raw"
  for v in "${temp[@]}"; do [[ -n "$v" ]] && arr+=("$v"); done
  printf '%s\n' "${arr[@]}"
}

# ====== 打印页面 ======
print_page_view() {
  local page="$1"
  shift
  local -a items=("$@")
  local total=${#items[@]}
  local pages=$(( (total + PER_PAGE -1)/PER_PAGE ))
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
      name="${items[idx]}"
      draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${name}${C_RESET}"
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
  local parent_key="$1"
  local sel="$2"
  local full_key="$parent_key"
  [[ "$parent_key" == "ROOT" ]] && full_key="$sel" || full_key="$parent_key::$sel"
  local cmd="${CMD_MAP[$full_key]:-}"
  if [[ -z "$cmd" ]]; then
    # 进入子菜单
    current_parent="$full_key"
    page=1
    return 2
  fi
  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${sel}${C_RESET}"
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

# ====== 搜索功能 ======
search_and_show() {
  local keyword="$1"
  [[ -z "$keyword" ]] && return 1
  kw_lc="$(echo "$keyword" | tr '[:upper:]' '[:lower:]')"
  local -a matches=()
  for key in "${!CMD_MAP[@]}"; do
    name="${key##*::}"
    name_lc="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$name_lc" == *"$kw_lc"* ]]; then
      matches+=("$key")
    fi
  done
  if [ ${#matches[@]} -eq 0 ]; then
    echo "❌ 未找到匹配项，输入 p 返回全部菜单"
    read -rp "输入: " ans
    [[ "$ans" == "p" ]] && return 2
    return 1
  fi

  local page=1
  while true; do
    local -a disp=()
    for m in "${matches[@]}"; do
      disp+=("${m##*::}")
    done
    print_page_view "$page" "${disp[@]}"
    printf "%b请输入编号 (0-9) 执行, p 返回菜单, q 退出: %b" "$C_HINT" "$C_RESET"
    read -r in
    case "$in" in
      [0-9])
        idx=$(( (page-1)*PER_PAGE + in ))
        [[ $idx -ge ${#matches[@]} ]] && { echo "❌ 无效编号"; read -rp "按回车继续..." _; continue; }
        sel="${matches[$idx]}"
        cmd="${CMD_MAP[$sel]}"
        clear
        echo -e "${C_KEY}👉 正在执行：${C_NAME}${sel##*::}${C_RESET}"
        echo -e "${C_DIV}-----------------------------------------${C_RESET}"
        if [[ "$cmd" =~ ^https?:// ]]; then
          bash <(curl -fsSL "$cmd")
        else
          eval "$cmd"
        fi
        echo -e "${C_DIV}-----------------------------------------${C_RESET}"
        read -rp $'按回车返回搜索结果...' _
        ;;
      p|P) return 2 ;;
      q|Q) clear; echo "👋 再见！"; exit 0 ;;
      n|N) ((page++)); maxp=$(( (${#matches[@]} + PER_PAGE -1)/PER_PAGE )); ((page>maxp)) && page=$maxp ;;
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
  [ $VIEW_PAGES -lt 1 ] && VIEW_PAGES=1

  print_page_view "$page" "${view_items[@]}"

  printf "%b请输入选项 (0-9/n/b/p/q/搜索): %b" "$C_HINT" "$C_RESET"
  read -r key
  key="$(echo -n "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  case "$key" in
    [0-9])
      idx=$(( (page-1)*PER_PAGE + key ))
      if (( idx<0 || idx>=VIEW_TOTAL )); then
        echo "❌ 无效选项"; read -rp "按回车返回..." _
        continue
      fi
      sel="${view_items[$idx]}"
      run_selected "$current_parent" "$sel"
      rc=$?
      if [ $rc -eq 2 ]; then
        continue
      fi
      ;;
    n|N)
      ((page++)); ((page>VIEW_PAGES)) && page=$VIEW_PAGES ;;
    b|B)
      if [[ "$current_parent" == "ROOT" ]]; then
        echo "已是主菜单"; read -rp "按回车返回..." _
      else
        parent="${current_parent%::*}"
        [[ "$parent" == "$current_parent" ]] && parent="ROOT"
        current_parent="$parent"
        page=1
      fi
      ;;
    p|P)
      current_parent="ROOT"
      page=1
      ;;
    q|Q)
      clear; echo "👋 再见！"; exit 0 ;;
    "")
      ;;
    *)
      search_and_show "$key"
      rc=$?
      [[ $rc -eq 2 ]] && { current_parent="ROOT"; page=1; }
      ;;
  esac
done
