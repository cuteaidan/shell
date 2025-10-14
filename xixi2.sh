#!/usr/bin/env bash
# ========================================================
# xixi.sh — 菜单管理脚本（增强稳定版 by GPT-5）
# ========================================================

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
  TMP_SCRIPT="$(mktemp /tmp/menu_manager.XXXXXX.sh)"
  cat > "$TMP_SCRIPT"
  chmod +x "$TMP_SCRIPT"
  exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
fi

# ====== 基本配置 ======
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10
BOX_WIDTH=50
LEFT_INDENT="        "

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

# ====== 下载配置文件 ======
echo -e "\033[1;34m🔄 正在加载菜单配置...\033[0m"
if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
  echo -e "\033[1;31m❌ 无法下载配置文件，请检查网络或配置地址。\033[0m"
  exit 1
fi

mapfile -t RAW_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")
if [ ${#RAW_LINES[@]} -eq 0 ]; then
  echo -e "\033[1;31m⚠️  配置文件为空或格式不正确。\033[0m"
  exit 1
fi

# ====== 颜色定义 ======
C_RESET='\033[0m'
C_BOX='\033[1;38;5;202m'
C_TITLE='\033[1;38;5;220m'
C_KEY='\033[1;32m'
C_NAME='\033[1;38;5;39m'
C_HINT='\033[1;32m'
C_DIV='\033[38;5;240m'

# ====== 数据结构 ======
declare -A MENU_TREE
declare -a ALL_ITEMS

# ====== 解析配置文件 ======
for line in "${RAW_LINES[@]}"; do
  IFS='|' read -r -a parts <<< "$line"
  depth=$(grep -o '||' <<< "$line" | wc -l || true)   # ✅ 容错修复
  title="${parts[-2]}"
  cmd="${parts[-1]}"
  indent=""
  for ((i=0; i<depth; i++)); do indent+="  "; done
  ALL_ITEMS+=("$indent$title|$cmd")
done

# ====== 打印菜单函数 ======
draw_box() {
  local title="$1"
  local padding=$(( (BOX_WIDTH - ${#title} - 2) / 2 ))
  printf "${C_BOX}╔%*s${C_TITLE}%s${C_BOX}%*s╗${C_RESET}\n" "$padding" "" "$title" "$padding" ""
}

# ====== 主逻辑 ======
clear
draw_box "脚本管理器 (by Moreanp)"
echo -e "${C_DIV}╠════════════════════════════════════════════════╣${C_RESET}"

i=0
for item in "${ALL_ITEMS[@]}"; do
  ((i++))
  name="${item%|*}"
  cmd="${item#*|}"
  printf "${C_KEY}[%02d]${C_RESET} ${C_NAME}%s${C_RESET}\n" "$i" "$name"
done

echo -e "${C_DIV}╚════════════════════════════════════════════════╝${C_RESET}"
echo
read -rp "请输入编号以执行命令 (q 退出): " choice

if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice <= ${#ALL_ITEMS[@]} )); then
  cmd="${ALL_ITEMS[$((choice-1))]#*|}"
  echo -e "\033[1;34m▶ 正在执行: ${cmd}\033[0m"
  bash -c "$cmd"
else
  echo -e "\033[1;31m❌ 无效的输入。\033[0m"
fi
