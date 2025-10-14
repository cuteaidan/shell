#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权 ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m⚠️ 检测到当前用户不是 root。\033[0m"
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[1;31m❌ 系统未安装 sudo，请使用 root 用户运行本脚本。\033[0m"
    exit 1
  fi
  echo -e "\033[1;32m🔑 请输入当前用户的密码以获取管理员权限（sudo）...\033[0m"
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
  echo -e "\033[1;34mℹ️ 已将脚本内容写入临时文件：$TMP_SCRIPT\033[0m"
  echo -e "\033[1;34m➡️ 正在以 root 权限重新运行...\033[0m"
  exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
  exit $?
fi

# ====== 配置部分 ======
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/script1.conf"
PER_PAGE=10
BOX_WIDTH=60
LEFT_INDENT="  "
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
    if (( (code>=19968 && code<=40959) || (code>=65281 && code<=65519) || (code>=12288 && code<=12351) || (code>=12352 && code<=12543) )); then
      len=$((len+2))
    else
      len=$((len+1))
    fi
  done
  echo "$len"
}

# ====== 边框绘制 ======
draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_text() {
  local text="$1"
  local width=$(str_width "$text")
  local padding=$((BOX_WIDTH - width - ${#LEFT_INDENT} - 2))
  ((padding<0)) && padding=0
  printf "%b║%s%b%*s%b║%b\n" "$C_BOX" "$LEFT_INDENT" "$text" "$padding" "" "$C_BOX" "$C_RESET"
}
draw_title() {
  local title="$1"
  local width=$(str_width "$title")
  local left_pad=$(( (BOX_WIDTH - width - 2)/2 ))
  local right_pad=$((BOX_WIDTH - width - left_pad - 2))
  [ $left_pad -lt 0 ] && left_pad=0
  [ $right_pad -lt 0 ] && right_pad=0
  printf "%b║%*s%b%s%b%*s%b║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX" "$C_RESET"
}

# ====== 数据结构 ======
declare -A CHILDREN
declare -A LABEL
declare -A CMD
ORDERED_KEYS=()

ROOT_KEY="__ROOT__"
CURRENT_PATH="$ROOT_KEY"

add_child() {
  local parent="$1"
  local child="$2"
  local child_label="$3"

  local parent_key="$parent"
  [ -z "$parent_key" ] && parent_key="$ROOT_KEY"

  local existing="${CHILDREN["$parent_key"]:-}"
  if [ -z "$existing" ]; then
    CHILDREN["$parent_key"]="$child"
  else
    if ! printf '%s\n' "$existing" | grep -Fxq "$child"; then
      CHILDREN["$parent_key"]="${existing}"$'\n'"${child}"
    fi
  fi

  LABEL["$child"]="$child_label"
  if ! printf '%s\n' "${ORDERED_KEYS[@]-}" | grep -Fxq "$child"; then
    ORDERED_KEYS+=("$child")
  fi
}

join_slash() {
  local IFS='/'
  echo "$*"
}

# ====== 解析配置文件 ======
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^\s*# ]] && continue
  [[ -z "${line// }" ]] && continue

  IFS='|' read -r -a parts <<< "$line"
  len=${#parts[@]}
  if (( len < 2 )); then continue; fi

  name="${parts[len-2]}"
  cmd="${parts[len-1]}"

  path_segments=()
  if (( len > 2 )); then
    for ((i=0;i<len-2;i++)); do
      seg="${parts[i]}"
      seg="${seg#"${seg%%[![:space:]]*}"}"
      seg="${seg%"${seg##*[![:space:]]}"}"
      [ -n "$seg" ] && path_segments+=("$seg")
    done
  fi

  if [ ${#path_segments[@]} -eq 0 ]; then
    parent="$ROOT_KEY"
  else
    parent="$(join_slash "${path_segments[@]}")"
  fi

  if [ -n "$parent" ] && [ "$parent" != "$ROOT_KEY" ]; then
    if [ -z "${LABEL["$parent"]:-}" ]; then
      parent_label="${parent##*/}"
      LABEL["$parent"]="$parent_label"
      if ! printf '%s\n' "${ORDERED_KEYS[@]-}" | grep -Fxq "$parent"; then
        ORDERED_KEYS+=("$parent")
      fi
    fi
  fi

  if [ "$parent" = "$ROOT_KEY" ]; then
    child="$name"
  else
    child="$parent/$name"
  fi

  add_child "$parent" "$child" "$name"
  if [ -n "$cmd" ]; then
    CMD["$child"]="$cmd"
  fi
done < "$TMP_CONF"

has_children() { local k="$1"; local key="${k:-$ROOT_KEY}"; [ -n "${CHILDREN["$key"]:-}" ]; }
is_leaf() { local k="$1"; [ -n "${CMD["$k"]:-}" ]; }
breadcrumb() { [ "$1" = "$ROOT_KEY" ] && echo "Home" || echo "$1"; }

# ====== 打印菜单 ======
print_page() {
  local current="$1" page="$2"
  local key="${current:-$ROOT_KEY}"
  local -a list
  if [ -n "${CHILDREN["$key"]:-}" ]; then
    IFS=$'\n' read -r -d '' -a list < <(printf '%s\0' "${CHILDREN["$key"]}")
  else
    list=()
  fi
  local total=${#list[@]}
  local pages=$(( (total + PER_PAGE - 1)/PER_PAGE ))
  ((pages==0)) && pages=1
  local start=$(( (page-1)*PER_PAGE ))

  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp) — $(breadcrumb "$key")"
  draw_mid
  for ((slot=0; slot<PER_PAGE; slot++)); do
    idx=$((start + slot))
    if (( idx < total )); then
      k="${list[idx]}"
      label="${LABEL["$k"]}"
      if has_children "$k"; then
        draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${label}${C_RESET}${C_DIV} /目录${C_RESET}"
      else
        draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${label}${C_RESET}"
      fi
    else
      draw_text ""
    fi
  done
  draw_mid
  draw_text "第 ${page}/${pages} 页 共 ${total} 项"
  draw_text "[ n ] 下一页 [ b ] 上一页  [ p ] 返回上一级  [ s ] 全局搜索  [ q ] 退出"
  draw_bot
}

run_key() {
  local key="$1"
  if has_children "$key"; then
    CURRENT_PATH="$key"
    PAGE=1
    return 0
  fi
  if is_leaf "$key"; then
    cmd="${CMD["$key"]}"
    clear
    echo -e "${C_KEY}👉 正在执行：${C_NAME}${LABEL["$key"]}${C_RESET}"
    echo -e "${C_DIV}-----------------------------------------${C_RESET}"
    if [[ "$cmd" =~ ^CMD: ]]; then
      eval "${cmd#CMD:}"
    elif [[ "$cmd" =~ ^https?:// ]]; then
      bash <(curl -fsSL "${cmd}")
    else
      eval "$cmd"
    fi
    echo -e "${C_DIV}-----------------------------------------${C_RESET}"
    read -rp $'按回车返回菜单...' _
    return 0
  fi
  echo "❌ 无法执行该项"
  read -rp "按回车返回..." _
}

# ====== 全局搜索 ======
search_mode() {
  local -a leaf_keys=()
  local -a leaf_disp=()
  for k in "${!CMD[@]}"; do
    leaf_keys+=("$k")
    leaf_disp+=("${LABEL["$k"]} (${k})")
  done
  [ ${#leaf_keys[@]} -eq 0 ] && { echo "⚠️ 没有可搜索的项。按回车返回..."; read -r _; return; }

  while true; do
    clear
    draw_line
    draw_title "全局模糊搜索（只匹配可执行项）"
    draw_mid
    draw_text "请输入搜索关键词（不区分大小写），或直接按回车返回："
    draw_mid
    draw_text "[ p ] 返回主目录"
    draw_bot
    printf "%b搜索: %b" "$C_HINT" "$C_RESET"
    read -r pattern || true
    [[ "$pattern" = "p" || "$pattern" = "P" ]] && { CURRENT_PATH="$ROOT_KEY"; PAGE=1; return; }
    [ -z "$pattern" ] && return

    local -a results_keys=()
    local -a results_disp=()
    local LCASE_PATTERN="$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')"
    for i in "${!leaf_keys[@]}"; do
      k="${leaf_keys[i]}"
      disp="${LABEL["$k"]}"
      low_disp="$(printf '%s' "$disp" | tr '[:upper:]' '[:lower:]')"
      if [[ "$low_disp" == *"$LCASE_PATTERN"* ]]; then
        results_keys+=("$k")
        results_disp+=("$disp")
      fi
    done

    if [ ${#results_keys[@]} -eq 0 ]; then
      echo "⚠️ 没有匹配结果"
      read -rp "按回车继续..." _
      continue
    fi

    local r_page=1
    while true; do
      local total=${#results_keys[@]}
      local pages=$(( (total+PER_PAGE-1)/PER_PAGE ))
      local start=$(( (r_page-1)*PER_PAGE ))
      clear
      draw_line
      draw_title "搜索结果: \"$pattern\""
      draw_mid
      for ((slot=0; slot<PER_PAGE; slot++)); do
        idx=$((start+slot))
        if (( idx<total )); then
          draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${results_disp[idx]}${C_RESET}"
        else
          draw_text ""
        fi
      done
      draw_mid
      draw_text "第 ${r_page}/${pages} 页 共 ${total} 项"
      draw_text "[ n ] 下一页 [ b ] 上一页 [ p ] 返回主目录 [ 0-9 ] 执行"
      draw_bot
      printf "%b请输入选项: %b" "$C_HINT" "$C_RESET"
      read -r skey || true
      case "$skey" in
        [0-9]) idx=$((start + skey)); (( idx<total )) && run_key "${results_keys[idx]}" ;;
        n|N) ((r_page<pages)) && ((r_page++)) ;;
        b|B) ((r_page>1)) && ((r_page--)) ;;
        p|P|"") CURRENT_PATH="$ROOT_KEY"; PAGE=1; return ;;
        *) echo "⚠️ 无效输入"; sleep 0.6 ;;
      esac
    done
  done
}

# ====== 主循环 ======
PAGE=1
while true; do
  print_page "$CURRENT_PATH" "$PAGE"
  printf "%b请输入选项 (0-9 / n / b / p / s / q): %b" "$C_HINT" "$C_RESET"
  read -r key || true
  case "$key" in
    [0-9])
      list=()
      key_for_children="${CURRENT_PATH:-$ROOT_KEY}"
      [ -n "${CHILDREN["$key_for_children"]:-}" ] && IFS=$'\n' read -r -d '' -a list < <(printf '%s\0' "${CHILDREN["$key_for_children"]}")
      idx=$key
      (( idx<${#list[@]} )) && run_key "${list[idx]}"
      ;;
    n|N) ((PAGE++)) ;;
    b|B) ((PAGE>1)) && ((PAGE--)) ;;
    p|P) CURRENT_PATH="$ROOT_KEY"; PAGE=1 ;;
    s|S) search_mode ;;
    q|Q) clear; echo "👋 再见！"; exit 0 ;;
    *) echo "⚠️ 无效输入"; sleep 0.6 ;;
  esac
done
