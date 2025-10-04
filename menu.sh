#!/bin/bash
# 一个整合脚本管理器，可以从远程加载并运行子脚本
# 用法：
#   bash <(curl -Ls https://raw.githubusercontent.com/eaidan/lib/refs/heads/main/main.sh)

# ================== 配置 ==================
# 远程配置文件 URL
CONFIG_URL="https://raw.githubusercontent.com/dcj1104/lib/refs/heads/main/scripts.conf"
# ================== 配置结束 ==============

# 下载配置文件
load_config() {
  mapfile -t SCRIPTS < <(curl -Ls "$CONFIG_URL" | grep -vE '^\s*#|^\s*$')
  if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
    echo "❌ 无法从 $CONFIG_URL 加载配置，请检查网络或配置文件格式"
    exit 1
  fi
}

# 打印菜单
print_menu() {
  clear
  echo "========================================="
  echo "   脚本管理器 (by Moreanp) "
  echo "   配置来源: $CONFIG_URL"
  echo "========================================="
  echo
  local i=1
  for item in "${SCRIPTS[@]}"; do
    name="${item%%|*}"
    echo "  $i) $name"
    ((i++))
  done
  echo "  r) 重新加载配置"
  echo "  0) 退出"
  echo
}

# 主循环
while true; do
  load_config
  print_menu
  read -rp "请输入要执行的选项编号: " choice

  if [[ "$choice" == "0" ]]; then
    echo "退出脚本管理器"
    exit 0
  elif [[ "$choice" == "r" ]]; then
    echo "🔄 重新加载配置..."
    sleep 1
    continue
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#SCRIPTS[@]} )); then
    selected="${SCRIPTS[choice-1]}"

    # 分割字段
    name="${selected%%|*}"
    rest="${selected#*|}"
    cmd="${rest%%|*}"
    args=""
    [[ "$rest" == *"|"* ]] && args="${rest#*|}"

    echo
    echo "👉 正在执行 [$name] ..."
    echo "-----------------------------------------"

    # 判断是不是URL
    if [[ "$cmd" =~ ^https?:// ]]; then
      bash <(curl -Ls "$cmd") $args
    else
      eval "$cmd $args"
    fi

    echo "-----------------------------------------"
    echo "✅ [$name] 执行完毕，按回车键返回菜单..."
    read -r
  else
    echo "❌ 输入无效，请重新选择"
    sleep 1
  fi
done
