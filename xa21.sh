#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权（兼容 bash <(curl …) / curl | bash / 本地文件） ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m⚠️ 检测到当前用户不是 root。\033[0m"
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[1;31m❌ 系统未安装 sudo，请使用 root 用户运行本脚本。\033[0m"
    exit 1
  fi
  echo -e "\033[1;32m🔑 请输入当前用户的密码以获取管理员权限（sudo）...\033[0m"
  # 判断当前脚本是否为普通文件
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
# ====== 提权检测结束 ======

# ====== 配置部分 ======
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
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

# ====== 宽度计算（支持全角字符 & 去除 ANSI 颜色码） ======
str_width() {
  local text="$1"
  text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
  local len=0 i ch code
  # iterate by byte-aware method: use awk to get length per grapheme would be complex;
  # keep original heuristic: treat CJK/fullwidth codepoint ranges as width 2
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

# ====== 数据结构（树） ======
# 存储节点的孩子： CHILDREN["nodekey"]="childKey1|childKey2|..."
# 存储节点显示名： LABEL["nodekey"]="Name"
# 存储命令（若为可执行项/叶子节点）： CMD["nodekey"]="command"
# 节点的 key 以 path 形式，例如： "UI/page/H-UI"。根节点使用空字符串 ""。
declare -A CHILDREN
declare -A LABEL
declare -A CMD
ORDERED_KEYS=()   # 用于保持文件顺序，作为注册过的节点记录

# 附加 child 到 parent（保持顺序且避免重复）
add_child() {
  local parent="$1"
  local child="$2"    # child key
  local child_label="$3"
  # append child to parent's children if not exists
  local existing="${CHILDREN[$parent]:-}"
  if [ -z "$existing" ]; then
    CHILDREN[$parent]="$child"
  else
    # check if already contained
    if ! printf '%s\n' "$existing" | grep -Fxq "$child"; then
      CHILDREN[$parent]="${existing}"$'\n'"${child}"
    fi
  fi
  LABEL[$child]="$child_label"
  # register key order if unseen
  if ! printf '%s\n' "${ORDERED_KEYS[@]-}" | grep -Fxq "$child"; then
    ORDERED_KEYS+=("$child")
  fi
}

# Helper: join array with /
join_slash() {
  local IFS='/'
  echo "$*"
}

# ====== 读取并解析配置，构建树结构 ======
while IFS= read -r line || [ -n "$line" ]; do
  # 跳过注释与空行
  [[ "$line" =~ ^\s*# ]] && continue
  [[ -z "${line// }" ]] && continue

  # 把行按 '|' 分割（保留空字段）
  IFS='|' read -r -a parts <<< "$line"
  local_len=${#parts[@]}
  if (( local_len < 2 )); then
    continue
  fi

  # 最后一个字段视为 command，倒数第二是 name，其前面的视为路径段（可能包含空字符串）
  name="${parts[local_len-2]}"
  cmd="${parts[local_len-1]}"

  # 收集路径段（parts[0..local_len-3]），只保留非空段作为实际路径
  path_segments=()
  if (( local_len > 2 )); then
    for ((i=0;i<local_len-2;i++)); do
      seg="${parts[i]}"
      # trim whitespace
      seg="${seg#"${seg%%[![:space:]]*}"}"
      seg="${seg%"${seg##*[![:space:]]}"}"
      [ -n "$seg" ] && path_segments+=("$seg")
    done
  fi

  # parent key
  if [ ${#path_segments[@]} -eq 0 ]; then
    parent=""
  else
    parent="$(join_slash "${path_segments[@]}")"
  fi

  # child key = parent/name（根时 child = name）
  if [ -z "$parent" ]; then
    child="$name"
  else
    child="$parent/$name"
  fi

  # 创建 parent 节点（如果尚不存在）
  if [ -z "${LABEL[$parent]:-}" ] && [ -n "$parent" ]; then
    # set label for parent as last segment of parent path
    parent_label="${parent##*/}"
    LABEL[$parent]="$parent_label"
    # ensure it's registered
    if ! printf '%s\n' "${ORDERED_KEYS[@]-}" | grep -Fxq "$parent"; then
      ORDERED_KEYS+=("$parent")
    fi
  fi

  # 将 child 添加到 parent，并记录 command（如果存在）
  add_child "$parent" "$child" "$name"
  if [ -n "$cmd" ]; then
    CMD[$child]="$cmd"
  fi
done < "$TMP_CONF"

# ====== 辅助：判断是否有子节点 / 是否叶子节点 ======
has_children() {
  local k="$1"
  [ -n "${CHILDREN[$k]:-}" ]
}
is_leaf() {
  local k="$1"
  [ -n "${CMD[$k]:-}" ]
}

# ====== 打印当前路径面包屑 ======
breadcrumb() {
  local key="$1"
  if [ -z "$key" ]; then
    echo "Home"
  else
    echo "$key"
  fi
}

# ====== 打印菜单页（current_key 表示当前节点） ======
print_page() {
  local current="$1"
  local page="$2"
  local start=$(( (page-1)*PER_PAGE ))
  local -a list
  if [ -n "${CHILDREN[$current]:-}" ]; then
    # convert newline-separated children into array preserving order
    IFS=$'\n' read -r -d '' -a list < <(printf '%s\0' "${CHILDREN[$current]}")
  else
    list=()
  fi
  local total=${#list[@]}
  local pages=$(( (total + PER_PAGE - 1) / PER_PAGE ))
  ((pages==0)) && pages=1

  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp) — $(breadcrumb "$current")"
  draw_mid

  for ((slot=0; slot<PER_PAGE; slot++)); do
    idx=$((start + slot))
    if (( idx < total )); then
      key="${list[idx]}"
      label="${LABEL[$key]}"
      if has_children "$key"; then
        # 补充目录提示
        draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${label}${C_RESET}${C_DIV} /目录${C_RESET}"
      elif is_leaf "$key"; then
        draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${label}${C_RESET}"
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

# ====== 执行/进入逻辑 ======
run_key() {
  local key="$1"
  # 如果有子节点 -> 进入子目录
  if has_children "$key"; then
    CURRENT_PATH="$key"
    PAGE=1
    return 0
  fi
  # 如果是叶子节点 -> 执行命令
  if is_leaf "$key"; then
    cmd="${CMD[$key]}"
    clear
    echo -e "${C_KEY}👉 正在执行：${C_NAME}${LABEL[$key]}${C_RESET}"
    echo -e "${C_DIV}-----------------------------------------${C_RESET}"
    # 与原脚本类似：支持 CMD: 前缀、本地命令、远程脚本（http）等
    if [[ "$cmd" =~ ^CMD: ]]; then
      eval "${cmd#CMD:}"
    elif [[ "$cmd" =~ ^https?:// ]]; then
      bash <(curl -fsSL "${cmd}")
    else
      # 如果包含管道/复杂命令直接 eval
      eval "$cmd"
    fi
    echo -e "${C_DIV}-----------------------------------------${C_RESET}"
    read -rp $'按回车返回菜单...' _
    return 0
  fi
  echo "❌ 无法执行该项"
  read -rp "按回车返回..." _
}

# ====== 全局模糊搜索（只返回叶子节点） ======
search_mode() {
  # collect leaf keys and display labels (label + path for context)
  local -a leaf_keys=()
  local -a leaf_disp=()
  for k in "${!CMD[@]}"; do
    leaf_keys+=("$k")
    # 显示为 "Label (full/path)"
    leaf_disp+=("${LABEL[$k]} (${k})")
  done

  if [ ${#leaf_keys[@]} -eq 0 ]; then
    echo "⚠️ 没有可搜索的项。按回车返回..."
    read -r _
    return
  fi

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
    # 如果输入 p 则返回 home
    if [ "$pattern" = "p" ] || [ "$pattern" = "P" ]; then
      CURRENT_PATH=""
      PAGE=1
      return
    fi
    if [ -z "$pattern" ]; then
      return
    fi

    # 生成匹配结果数组（case-insensitive）
    local -a results_keys=()
    local -a results_disp=()
    local LCASE_PATTERN="$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')"
    for i in "${!leaf_keys[@]}"; do
      k="${leaf_keys[i]}"
      disp="${leaf_disp[i]}"
      low_disp="$(printf '%s' "$disp" | tr '[:upper:]' '[:lower:]')"
      if [[ "$low_disp" == *"$LCASE_PATTERN"* ]]; then
        results_keys+=("$k")
        results_disp+=("${LABEL[$k]} (${k})")
      fi
    done

    if [ ${#results_keys[@]} -eq 0 ]; then
      echo "未找到匹配项: '$pattern'。按回车继续..."
      read -r _
      continue
    fi

    # 结果分页浏览与选择
    local rpage=1
    while true; do
      clear
      draw_line
      draw_title "搜索结果: '$pattern' （按 p 返回主目录 / q 退出搜索）"
      draw_mid
      local start=$(( (rpage-1)*PER_PAGE ))
      for ((i=0;i<PER_PAGE;i++)); do
        idx=$((start + i))
        if (( idx < ${#results_keys[@]} )); then
          draw_text "${C_KEY}[$i]${C_RESET} ${C_NAME}${results_disp[idx]}${C_RESET}"
        else
          draw_text ""
        fi
      done
      draw_mid
      local total=${#results_keys[@]}
      local pages=$(( (total + PER_PAGE - 1) / PER_PAGE ))
      ((pages==0)) && pages=1
      draw_text "第 ${rpage}/${pages} 页 共 ${total} 项"
      draw_text "[ n ] 下一页 [ b ] 上一页  [ p ] 返回主目录  [ q ] 退出脚本"
      draw_bot

      printf "%b选择(0-9/n/b/p/q): %b" "$C_HINT" "$C_RESET"
      read -r in || true
      case "$in" in
        [0-9])
          sel=$((start + in))
          if (( sel < ${#results_keys[@]} )); then
            run_key "${results_keys[sel]}"
          else
            echo "无效选择"
            sleep 0.6
          fi
        ;;
        n|N)
          ((rpage < pages)) && ((rpage++)) || { echo "已是最后一页"; read -rp "按回车..." _; }
        ;;
        b|B)
          ((rpage > 1)) && ((rpage--)) || { echo "已是第一页"; read -rp "按回车..." _; }
        ;;
        p|P)
          CURRENT_PATH=""
          PAGE=1
          return
        ;;
        q|Q)
          clear; echo "👋 再见！"; exit 0
        ;;
        *)
          echo "⚠️ 无效输入"
          sleep 0.5
        ;;
      esac
    done
  done
}

# ====== 主循环与输入处理 ======
CURRENT_PATH=""
PAGE=1

while true; do
  print_page "$CURRENT_PATH" "$PAGE"
  printf "%b请输入选项 (0-9 / n / b / p / s / q): %b" "$C_HINT" "$C_RESET"
  read -r key || true

  case "$key" in
    [0-9])
      # 解析当前 children 列表
      if [ -n "${CHILDREN[$CURRENT_PATH]:-}" ]; then
        IFS=$'\n' read -r -d '' -a curlist < <(printf '%s\0' "${CHILDREN[$CURRENT_PATH]}")
      else
        curlist=()
      fi
      idx=$(( (PAGE-1)*PER_PAGE + key ))
      if (( idx < 0 || idx >= ${#curlist[@]} )); then
        echo "❌ 无效选项"
        sleep 0.6
        continue
      fi
      chosen="${curlist[idx]}"
      run_key "$chosen"
      ;;
    n|N)
      # next page
      if [ -n "${CHILDREN[$CURRENT_PATH]:-}" ]; then
        IFS=$'\n' read -r -d '' -a tmp < <(printf '%s\0' "${CHILDREN[$CURRENT_PATH]}")
      else
        tmp=()
      fi
      total=${#tmp[@]}
      pages=$(( (total + PER_PAGE - 1) / PER_PAGE ))
      ((pages==0)) && pages=1
      (( PAGE < pages )) && (( PAGE++ )) || { echo "已是最后一页"; read -rp "按回车返回..." _; }
      ;;
    b|B)
      # previous page
      (( PAGE > 1 )) && (( PAGE-- )) || { echo "已是第一页"; read -rp "按回车返回..." _; }
      ;;
    p|P)
      # go up one level (parent)
      if [ -z "$CURRENT_PATH" ]; then
        echo "已在根目录"
        read -rp "按回车返回..." _
      else
        parent="${CURRENT_PATH%/*}"
        # if no slash existed, parent becomes "" (root)
        if [ "$parent" = "$CURRENT_PATH" ]; then
          parent=""
        fi
        CURRENT_PATH="$parent"
        PAGE=1
      fi
      ;;
    s|S)
      search_mode
      ;;
    q|Q)
      clear; echo "👋 再见！"; exit 0
      ;;
    *)
      echo "⚠️ 无效输入，请重试"
      sleep 0.6
      ;;
  esac
done
