#!/bin/bash
# 彩色分页脚本菜单管理器（支持远程配置）
# 用法: bash <(curl -Ls https://raw.githubusercontent.com/xxx/main/menu.sh)

REMOTE_CONF="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
TMP_CONF="/tmp/scripts.conf.$$"

# 下载配置文件
if ! curl -fsSL "$REMOTE_CONF" -o "$TMP_CONF"; then
  echo "❌ 无法下载配置文件: $REMOTE_CONF"
  exit 1
fi

# 读取配置文件到数组
mapfile -t SCRIPTS < "$TMP_CONF"
rm -f "$TMP_CONF"

# 颜色定义
C_RESET="\033[0m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_CYAN="\033[1;36m"
C_MAGENTA="\033[1;35m"
C_YELLOW="\033[1;33m"
C_BOLD="\033[1m"
C_BG_BLUE="\033[44;1;37m"

# 每页显示数量（可自动根据终端高度调整）
LINES=$(tput lines 2>/dev/null || echo 24)
PER_PAGE=$((LINES - 10))
(( PER_PAGE < 5 )) && PER_PAGE=5

page=1
total=${#SCRIPTS[@]}
pages=$(( (total + PER_PAGE - 1) / PER_PAGE ))

print_menu() {
  clear
  echo -e "${C_BG_BLUE}        脚本管理器 (by Moreanp)        ${C_RESET}"
  echo
  start=$(( (page - 1) * PER_PAGE ))
  end=$(( start + PER_PAGE - 1 ))
  (( end >= total )) && end=$(( total - 1 ))

  for i in $(seq $start $end); do
    num=$(( i + 1 ))
    item="${SCRIPTS[i]}"
    name="${item%%|*}"
    printf "  ${C_GREEN}%-3s${C_RESET} ${C_CYAN}%-40s${C_RESET}\n" "$num)" "$name"
  done

  echo
  echo -e "${C_YELLOW}第 $page/$pages 页${C_RESET}"
  echo "-----------------------------------------"
  echo "  n) 下一页    p) 上一页"
  echo "  0) 退出"
  echo
}

while true; do
  print_menu
  read -rp "请输入选项编号: " choice

  case "$choice" in
    0)
      echo "再见 👋"
      exit 0
      ;;
    n)
      (( page < pages )) && ((page++)) || echo "已是最后一页"
      ;;
    p)
      (( page > 1 )) && ((page--)) || echo "已是第一页"
      ;;
    *)
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then
        selected="${SCRIPTS[choice-1]}"
        name="${selected%%|*}"
        cmd="${selected#*|}"

        echo
        echo -e "👉 ${C_BOLD}正在执行 [${C_MAGENTA}$name${C_RESET}${C_BOLD}] ...${C_RESET}"
        echo "-----------------------------------------"

        # 判断是否是CMD命令或URL
        if [[ "$cmd" =~ ^CMD: ]]; then
          eval "${cmd#CMD:}"
        else
          bash <(curl -Ls "$cmd")
        fi

        echo "-----------------------------------------"
        echo -e "✅ [${C_MAGENTA}$name${C_RESET}] 执行完毕，按回车键返回菜单..."
        read -r
      else
        echo "❌ 输入无效"
        sleep 1
      fi
      ;;
  esac
done
