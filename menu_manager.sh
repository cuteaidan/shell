#!/usr/bin/env bash
# menu_manager_v2.sh
# 支持：无限层级目录（两个空格为一级） + 兼容旧 bash + 跨目录模糊搜索
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
  exec sudo -E bash "$0" "$@"
  exit $?
fi

# ====== 配置部分 ======
CONFIG_URL="${CONFIG_URL:-https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf}"
PER_PAGE=10
BOX_WIDTH=50
LEFT_INDENT="        "

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

# 下载配置：curl 优先，失败再尝试 wget
if command -v curl >/dev/null 2>&1; then
  if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
    echo -e "\033[1;31m❌ 使用 curl 下载配置失败：$CONFIG_URL\033[0m"
    if command -v wget >/dev/null 2>&1; then
      echo "尝试使用 wget..."
      if ! wget -qO "$TMP_CONF" "$CONFIG_URL"; then
        echo "❌ wget 也失败，退出。"
        exit 1
      fi
    else
      exit 1
    fi
  fi
elif command -v wget >/dev/null 2>&1; then
  if ! wget -qO "$TMP_CONF" "$CONFIG_URL"; then
    echo "❌ wget 下载配置失败：$CONFIG_URL"
    exit 1
  fi
else
  echo "❌ 系统未安装 curl 或 wget，无法下载配置文件。"
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

# ====== 宽度计算（支持全角字符，去除 ANSI 控制序列） ======
str_width() {
  local text="$1"
  # 删除 ANSI 序列
  text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
  local len=0 i ch code
  for ((i=0;i<${#text};i++)); do
    ch="${text:i:1}"
    # 获取字节值（对非 ASCII 可能失败，但尽量兼容）
    code=$(printf '%d' "'$ch" 2>/dev/null || true)
    if [[ -n "$code" ]] && (( (code>=19968 && code<=40959) || (code>=65281 && code<=65519) || (code>=12288 && code<=12543) )); then
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

# ====== 解析层级化配置（两个空格为一个层级） ======
# 存储结构：
#   CHILDREN["FULL_PATH"] -> 多行“名称|命令|args”文本（每项以换行分隔）
#   ITEMS["FULL_PATH/NAME"] -> 原始行（便于搜索）
declare -A CHILDREN
declare -A ITEMS
declare -a ROOT_ITEMS
path_stack=()
current_path="ROOT"

# 读取配置并解析
while IFS= read -r raw_line || [ -n "$raw_line" ]; do
  # 计算前导空格数
  # 保留原行，用于计算 indent
  # 取出去掉前导空格的版本
  # 注意：如果行全是空格，视为空行
  if [[ -z "$raw_line" || "$raw_line" =~ ^[[:space:]]*$ ]]; then
    continue
  fi
  # 删除行尾的 CR（防 Windows 换行）
  raw_line="${raw_line%$'\r'}"
  # 去前导空格并得到 stripped
  stripped="${raw_line#"${raw_line%%[![:space:]]*}"}"
  # count leading spaces
  lead_len=$(( ${#raw_line} - ${#stripped} ))
  # indent 等于每 2 个空格视为一级
  indent=$(( lead_len / 2 ))

  # 跳过注释行
  if [[ "${stripped}" =~ ^# ]]; then
    continue
  fi

  # 目录标记
  if [[ "${stripped}" =~ ^\[.*\]$ ]]; then
    dir="${stripped#[}"
    dir="${dir%]}"
    # pop 多余层级（兼容旧 bash：不使用负索引）
    while ((${#path_stack[@]} > indent)); do
      last_idx=$(( ${#path_stack[@]} - 1 ))
      unset "path_stack[$last_idx]"
    done
    # push
    path_stack+=("$dir")
    # recompute current_path
    current_path="ROOT"
    for d in "${path_stack[@]}"; do
      current_path+="/$d"
    done
    # ensure CHILDREN key exists (empty)
    CHILDREN["$current_path"]="${CHILDREN[$current_path]:-}"
    continue
  fi

  # 普通项：名称|命令|可选参数
  line="${stripped}"
  # ensure current_path exists; if no path_stack, current_path is ROOT
  current_path="ROOT"
  if ((${#path_stack[@]} > 0)); then
    current_path="ROOT"
    for d in "${path_stack[@]}"; do
      current_path+="/$d"
    done
  fi

  # append to CHILDREN[current_path]
  if [[ -n "${CHILDREN[$current_path]:-}" ]]; then
    CHILDREN["$current_path"]+=$'\n'"$line"
  else
    CHILDREN["$current_path"]="$line"
  fi

  # store for search
  name="${line%%|*}"
  ITEMS["$current_path/$name"]="$line"

  # if at root level, also record as root item (for listing if desired)
  if ((${#path_stack[@]} == 0)); then
    ROOT_ITEMS+=("$line")
  fi
done < "$TMP_CONF"

# ====== 状态变量 ======
CURRENT_PATH="ROOT"
MENU_STACK=()   # 用于保存返回：保存成对 (PATH, PAGE)
page=1
DISPLAY_LINES=()   # 当前页面显示项（目录标志使用 "DIR:子目录名"）

# ====== 帮助函数：stack 操作（push/pop pair） ======
push_menu_stack() {
  local path="$1" pagev="$2"
  MENU_STACK+=("$path" "$pagev")
}
pop_menu_stack() {
  # 返回两个值：PATH PAGE
  if ((${#MENU_STACK[@]} < 2)); then
    echo ""
    echo ""
    return 1
  fi
  last_idx=$(( ${#MENU_STACK[@]} - 1 ))
  pagev="${MENU_STACK[$last_idx]}"
  unset "MENU_STACK[$last_idx]"
  last_idx=$(( ${#MENU_STACK[@]} - 1 ))
  pathv="${MENU_STACK[$last_idx]}"
  unset "MENU_STACK[$last_idx]"
  # shrink array indexes to avoid holes (rebuild)
  # Shell will auto-compact on unset for indexed arrays, but keep safe
  echo "$pathv"
  echo "$pagev"
  return 0
}

# ====== 打印页面函数 ======
print_page() {
  local path="$1"
  local pagev="$2"
  DISPLAY_LINES=()

  # 先收集直接子目录（仅一层子目录）
  # 形式： CHILDREN keys like "ROOT/dir1/dir2" — 直接子目录要求去掉前缀 path/ 并且不包含进一步的 "/"
  for key in "${!CHILDREN[@]}"; do
    if [[ "$key" == "$path"/* ]]; then
      sub="${key#$path/}"
      # 跳过更深层（只允许直接子）
      if [[ "$sub" != */* ]]; then
        DISPLAY_LINES+=("DIR:$sub")
      fi
    fi
  done

  # 再把当前目录下的脚本项加入（按文件中顺序加入）
  if [[ -n "${CHILDREN[$path]:-}" ]]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ -n "$line" ]] && DISPLAY_LINES+=("$line")
    done <<< "${CHILDREN[$path]}"
  fi

  TOTAL=${#DISPLAY_LINES[@]}
  if (( TOTAL == 0 )); then
    PAGES=1
  else
    PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))
  fi
  ((pagev > PAGES)) && pagev=1

  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp)"
  draw_mid

  local start=$(( (pagev-1)*PER_PAGE ))
  local end=$(( start+PER_PAGE-1 ))
  ((end>=TOTAL)) && end=$((TOTAL-1))

  if (( TOTAL == 0 )); then
    draw_text "（该目录为空）"
  else
    for i in $(seq $start $end); do
      entry="${DISPLAY_LINES[i]}"
      if [[ "$entry" == DIR:* ]]; then
        dir="${entry#DIR:}"
        draw_text "${C_KEY}[$((i-start))]${C_RESET} 📁 ${C_NAME}${dir}${C_RESET}"
      else
        name="${entry%%|*}"
        draw_text "${C_KEY}[$((i-start))]${C_RESET} ${C_NAME}${name}${C_RESET}"
      fi
    done
  fi

  draw_mid
  # 显示当前路径（ROOT 展示为 / 为空）
  if [[ "$path" == "ROOT" ]]; then
    pshow="/"
  else
    pshow="${path#ROOT}"
  fi
  draw_text "路径：${pshow}"
  draw_text "[ n ] 下一页   [ b ] 上一页"
  draw_text "[ q ] 上一级     [ 0-9 ] 选择   [ 输入关键字进行模糊搜索 ]"
  draw_bot

  # 返回 page (可能被调整)
  page=$pagev
}

# ====== 运行条目或进入子目录 ======
run_slot() {
  local pagev="$1" slot="$2"
  local start=$(( (pagev-1)*PER_PAGE ))
  local idx=$(( start + slot ))
  if (( idx < 0 || idx >= ${#DISPLAY_LINES[@]} )); then
    read -rp $'❌ 无效选项，按回车返回...' _
    return
  fi

  entry="${DISPLAY_LINES[$idx]}"
  if [[ "$entry" == DIR:* ]]; then
    dir="${entry#DIR:}"
    # push current state
    push_menu_stack "$CURRENT_PATH" "$pagev"
    # enter
    if [[ "$CURRENT_PATH" == "ROOT" ]]; then
      CURRENT_PATH="ROOT/$dir"
    else
      CURRENT_PATH="$CURRENT_PATH/$dir"
    fi
    page=1
    return
  fi

  # 执行脚本项
  name="${entry%%|*}"
  rest="${entry#*|}"
  cmd="${rest%%|*}"
  args=""
  [[ "$rest" == *"|"* ]] && args="${rest#*|}"

  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${name}${C_RESET}"
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"

  if [[ "$cmd" =~ ^CMD: ]]; then
    eval "${cmd#CMD:} ${args}"
  elif [[ "$cmd" =~ ^https?:// ]]; then
    # 当远程脚本很大时，curl 可能输出中断；这里直接调用并保留退出状态
    if command -v curl >/dev/null 2>&1; then
      bash <(curl -fsSL "$cmd") ${args:+$args}
    elif command -v wget >/dev/null 2>&1; then
      bash <(wget -qO- "$cmd") ${args:+$args}
    else
      echo "❌ 系统未安装 curl 或 wget，无法下载并执行远程脚本。"
    fi
  else
    eval "$cmd ${args}"
  fi

  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  read -rp $'按回车返回菜单...' _
}

# ====== 跨目录模糊搜索（名字匹配，不区分大小写） ======
do_search() {
  local keyword="$1"
  if [[ -z "$keyword" ]]; then
    return
  fi
  local lc_kw lc_key name key full
  lc_kw="$(echo "$keyword" | tr '[:upper:]' '[:lower:]')"

  SEARCH_RESULTS=()
  # 遍历 ITEMS（key 格式： FULL_PATH/NAME）
  for key in "${!ITEMS[@]}"; do
    # 提取 NAME（最后一个 / 后面的）
    name="${key##*/}"
    lc_key="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lc_key" == *"$lc_kw"* ]]; then
      # push display line (原始行)
      SEARCH_RESULTS+=("${ITEMS[$key]}")
    fi
  done

  if ((${#SEARCH_RESULTS[@]} == 0)); then
    echo -e "\033[1;33m⚠️ 未找到匹配: '$keyword'\033[0m"
    read -rp $'按回车返回...' _
    return
  fi

  # 推入菜单栈（保存当前 PATH & page），并将 DISPLAY_LINES 替换为搜索结果
  push_menu_stack "$CURRENT_PATH" "$page"
  # 标记我们进入搜索模式 by setting CURRENT_PATH to special token
  CURRENT_PATH="__SEARCH__/$keyword"
  DISPLAY_LINES=()
  for e in "${SEARCH_RESULTS[@]}"; do
    DISPLAY_LINES+=("$e")
  done
  # 当处于搜索模式时，print_page 不能按原 path 读取 CHILDREN；我们直接绘制搜索结果页面：
  TOTAL=${#DISPLAY_LINES[@]}
  PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))
  page=1
  # 绘制一个带有提示的页面
  clear
  draw_line
  draw_title "脚本管理器 (搜索：${keyword})"
  draw_mid
  local start=$(( (page-1)*PER_PAGE ))
  local end=$(( start+PER_PAGE-1 ))
  ((end>=TOTAL)) && end=$((TOTAL-1))
  for i in $(seq $start $end); do
    entry="${DISPLAY_LINES[i]}"
    name="${entry%%|*}"
    draw_text "${C_KEY}[$((i-start))]${C_RESET} ${C_NAME}${name}${C_RESET}"
  done
  draw_mid
  draw_text "搜索结果 ${page}/${PAGES} 共 ${#DISPLAY_LINES[@]} 项"
  draw_text "[ q ] 返回上一级     [ 0-9 ] 选择"
  draw_bot
}

# ====== 主循环 ======
while true; do
  # 正常模式与搜索模式区分
  if [[ "$CURRENT_PATH" == __SEARCH__/* ]]; then
    # 已经在搜索模式（do_search 已经渲染页面并设置 DISPLAY_LINES, page）
    :
  else
    print_page "$CURRENT_PATH" "$page"
  fi

  printf "%b选项 (0-9 or 输入关键字搜索): %b" "$C_HINT" "$C_RESET"
  read -r key || true

  # 处理空输入（回车）
  if [[ -z "${key:-}" ]]; then
    continue
  fi

  case "$key" in
    [0-9])
      # 如果当前是搜索模式，DISPLAY_LINES 已经是搜索结果
      run_slot "$page" "$key"
      ;;
    n|N)
      ((page < PAGES)) && ((page++)) || { echo "已是最后一页"; read -rp $'按回车返回...' _; }
      ;;
    b|B)
      ((page > 1)) && ((page--)) || { echo "已是第一页"; read -rp $'按回车返回...' _; }
      ;;
    q|Q)
      # 如果在搜索模式或子目录，回退
      if [[ "$CURRENT_PATH" == __SEARCH__/* ]]; then
        # pop stack
        read -r prev_path prev_page < <(pop_menu_stack || printf "\n\n")
        if [[ -z "$prev_path" && -z "$prev_page" ]]; then
          # nothing to pop -> exit
          clear; echo "👋 再见！"; exit 0
        fi
        CURRENT_PATH="$prev_path"
        page="$prev_page"
        # clear search flag
        DISPLAY_LINES=()
      elif ((${#MENU_STACK[@]} > 0)); then
        read -r prev_path prev_page < <(pop_menu_stack || printf "\n\n")
        if [[ -z "$prev_path" && -z "$prev_page" ]]; then
          clear; echo "👋 再见！"; exit 0
        fi
        CURRENT_PATH="$prev_path"
        page="$prev_page"
      else
        clear; echo "👋 再见！"; exit 0
      fi
      ;;
    *)
      # 既非 0-9 也非控制键：当做搜索关键字
      do_search "$key"
      ;;
  esac
done
