#!/usr/bin/env bash
# main.sh - 彩色分页脚本管理器（远程配置）
# 用法：
#   bash <(curl -fsSL https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/menu.sh)

set -o errexit
set -o pipefail
set -o nounset

# ============== 配置 ==============
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10         # 每页显示条目数，固定为 10（通过 0-9 选择）
# ===================================

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"

cleanup() {
  rm -f "$TMP_CONF"
}
trap cleanup EXIT

# 下载并解析配置（过滤注释与空行）
if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
  echo "❌ 无法下载配置文件: $CONFIG_URL"
  exit 1
fi
mapfile -t ALL_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")

TOTAL=${#ALL_LINES[@]}
PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))

# ========== 颜色与样式 ==========
C_RESET="\033[0m"
C_TITLE_BG="\033[48;5;17;1m"   # 深蓝背景 + 粗体白
C_TITLE_FG="\033[1;37m"
C_KEY="\033[1;32m"            # 绿色
C_NAME="\033[1;36m"           # 青色
C_INDEX="\033[1;33m"          # 黄色
C_HINT="\033[0;37m"
C_DIV="\033[38;5;241m"
C_BOLD="\033[1m"
# =================================

# 打印一页菜单
print_page() {
  local page="$1"
  local start=$(( (page - 1) * PER_PAGE ))
  local end=$(( start + PER_PAGE - 1 ))
  (( end >= TOTAL )) && end=$(( TOTAL - 1 ))

  # 标题（居中）
  clear
  printf "%b" "${C_TITLE_BG}${C_TITLE_FG}"
  printf "  %-60s  " " 脚本管理器 (by Moreanp) "
  printf "%b\n\n" "${C_RESET}"

  # 说明行
  printf "%b" "${C_DIV}"
  printf " 配置: %s" "$CONFIG_URL"
  printf "%b\n\n" "${C_RESET}"

  # 列出项（以 0..9 键 标识当前页项）
  for slot in $(seq 0 $((PER_PAGE-1))); do
    idx=$(( start + slot ))
    if (( idx <= end )); then
      line="${ALL_LINES[idx]}"
      name="${line%%|*}"
      # 显示格式： [键] 名称（在行首，名称宽度适配）
      printf "  %b[%s]%b  %b%s%b\n" \
        "${C_KEY}" "${slot}" "${C_RESET}" "${C_NAME}" "$name" "${C_RESET}"
    else
      # 空位显示占位（保持整齐）
      printf "  %b[%s]%b  %b%s%b\n" "${C_KEY}" "${slot}" "${C_RESET}" "${C_NAME}" "-" "${C_RESET}"
    fi
  done

  # 分页与操作提示
  printf "\n%b第 %s/%s 页   共 %s 项%b\n" "${C_DIV}" "${page}" "${PAGES}" "${TOTAL}" "${C_RESET}"
  printf "%b[ n ] 下一页   [ b ] 上一页   [ q ] 退出   [ 0-9 ] 选择当前页对应项%b\n\n" "${C_HINT}" "${C_RESET}"
}

# 执行选中项
run_slot() {
  local page="$1"
  local slot="$2"   # 0..9
  local start=$(( (page - 1) * PER_PAGE ))
  local idx=$(( start + slot ))
  if (( idx < 0 || idx >= TOTAL )); then
    echo "❌ 该键没有对应条目。"
    return 0
  fi

  selected="${ALL_LINES[idx]}"
  name="${selected%%|*}"
  rest="${selected#*|}"
  # rest 可能就是命令（包含 | 号的会被当作命令的一部分）
  cmd="${rest%%|*}"
  args=""
  if [[ "$rest" == *"|"* ]]; then
    args="${rest#*|}"
  fi

  echo
  printf "%b👉 正在执行：%b%s%b\n" "${C_INDEX}" "${C_BOLD}" "$name" "${C_RESET}"
  printf "%b-----------------------------------------%b\n" "${C_DIV}" "${C_RESET}"

  # CMD: 前缀 → 直接 eval 后面的内容（适合多命令、复杂脚本）
  if [[ "$cmd" =~ ^CMD: ]]; then
    eval "${cmd#CMD:} ${args}"
  elif [[ "$cmd" =~ ^https?:// ]]; then
    # 远程脚本（支持附带参数）
    bash <(curl -fsSL "${cmd}") ${args:+$args}
  else
    # 普通命令行（支持自然写法）
    eval "$cmd ${args}"
  fi

  printf "%b-----------------------------------------%b\n" "${C_DIV}" "${C_RESET}"
  read -rp $'按回车返回菜单...' _dummy
}

# ========== 主循环 ==========
page=1
while true; do
  print_page "$page"

  # 读取单个字符（不需要回车）
  # 也允许用户敲回车再输入（兼容性）
  read -rn1 -p "请选择 (0-9 / n / b / q): " key
  echo

  case "$key" in
    [0-9])
      run_slot "$page" "$key"
      ;;
    n)
      (( page < PAGES )) && ((page++)) || echo "已是最后一页"
      ;;
    b)
      (( page > 1 )) && ((page--)) || echo "已是第一页"
      ;;
    q)
      echo "再见 👋"
      exit 0
      ;;
    "")
      # 允许回车等（忽略）
      ;;
    *)
      echo "无效输入：$key"
      ;;
  esac
done
