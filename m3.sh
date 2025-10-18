#!/usr/bin/env bash
# menu_manager_v3.sh
# 支持：层级菜单 + 顺序保留 + 动态加载配置 + 可执行命令

set -euo pipefail

CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/menu_config.txt"
CONFIG_FILE="/tmp/menu_config.txt"

# 颜色定义
RED="\033[1;31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; BLUE="\033[1;34m"; CYAN="\033[1;36m"; RESET="\033[0m"

# 下载配置文件
download_config() {
  echo -e "${CYAN}正在加载远程配置...${RESET}"
  curl -fsSL "$CONFIG_URL" -o "$CONFIG_FILE" || { echo -e "${RED}配置文件下载失败！${RESET}"; exit 1; }
}

# 解析配置文件，构建菜单树（保持原顺序）
declare -A MENU_CMDS MENU_PARENTS
declare -a MENU_ORDER MENU_LEVELS MENU_NAMES

parse_config() {
  local order=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue

    # 获取缩进层级（每两个空格为一级）
    local indent="${line%%[^ ]*}"
    local level=$(( ${#indent} / 2 ))

    # 去掉缩进
    line="${line#"${indent}"}"

    if [[ "$line" =~ ^\[.*\]$ ]]; then
      # 目录
      local name="${line#[}"
      name="${name%]}"
      MENU_NAMES[$order]="$name"
      MENU_LEVELS[$order]=$level
      MENU_ORDER[$order]="$name"
      MENU_CMDS["$name"]=""
      MENU_PARENTS["$name"]=""
    else
      # 命令项
      local name cmd arg
      IFS="|" read -r name cmd arg <<<"$line"
      MENU_NAMES[$order]="$name"
      MENU_LEVELS[$order]=$level
      MENU_ORDER[$order]="$name"
      MENU_CMDS["$name"]="$cmd ${arg:-}"
    fi
    ((order++))
  done < "$CONFIG_FILE"
}

# 根据层级构建父子关系
build_parents() {
  local -a stack=()
  for i in "${!MENU_ORDER[@]}"; do
    local level=${MENU_LEVELS[$i]}
    local name=${MENU_ORDER[$i]}
    if (( level == 0 )); then
      stack=("$name")
      MENU_PARENTS["$name"]=""
    else
      while (( ${#stack[@]} > level )); do
        unset 'stack[-1]'
      done
      local parent="${stack[-1]}"
      MENU_PARENTS["$name"]="$parent"
      stack+=("$name")
    fi
  done
}

# 显示菜单
show_menu() {
  local current="$1"
  clear
  echo -e "${BLUE}╔══════════════════════════════════════════════╗"
  echo -e "║          脚本管理器 (by Moreanp)             ║"
  echo -e "╠══════════════════════════════════════════════╣${RESET}"

  local idx=0
  declare -A map
  for i in "${!MENU_ORDER[@]}"; do
    local name=${MENU_ORDER[$i]}
    local parent=${MENU_PARENTS[$name]}
    local cmd=${MENU_CMDS[$name]}
    if [[ "$parent" == "$current" ]]; then
      printf "║  [${YELLOW}%d${RESET}] %s\n" "$idx" "$name"
      map[$idx]="$name"
      ((idx++))
    fi
  done
  echo -e "╠══════════════════════════════════════════════╣"
  echo -e "║  [${YELLOW}q${RESET}] 返回上一级 / 退出             ║"
  echo -e "╚══════════════════════════════════════════════╝${RESET}"

  echo -ne "${CYAN}请选择操作：${RESET}"
  read -r choice

  if [[ "$choice" == "q" ]]; then
    if [[ -z "$current" ]]; then exit 0; fi
    show_menu "${MENU_PARENTS[$current]}"
    return
  fi

  local name="${map[$choice]}"
  if [[ -z "$name" ]]; then
    show_menu "$current"
    return
  fi

  if [[ -n "${MENU_CMDS[$name]}" ]]; then
    clear
    echo -e "${GREEN}正在执行：${name}${RESET}"
    eval "${MENU_CMDS[$name]}"
    echo -e "\n${YELLOW}按回车键返回菜单...${RESET}"
    read -r
  fi

  # 若是目录，则进入下一层
  local has_child=false
  for v in "${MENU_PARENTS[@]}"; do
    [[ "$v" == "$name" ]] && has_child=true
  done
  if $has_child; then
    show_menu "$name"
  else
    show_menu "$current"
  fi
}

# 主程序
download_config
parse_config
build_parents
show_menu ""
