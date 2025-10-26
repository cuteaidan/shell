#!/usr/bin/env bash
# reinstall-menu.sh — 美观 & 修复版（支持 fnos dd 等）
# by GPT-5 (改进：安全参数拼接 / 版本选择 / dd-fnos 修复)
set -euo pipefail

# 色彩
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
PLAIN="\033[0m"

title() {
  clear
  echo -e "${BLUE}╔════════════════════════════════════════════════╗${PLAIN}"
  echo -e "${BLUE}║${PLAIN}   ${GREEN}一键系统重装 启动器（美观 & 修复版）${PLAIN}   ${BLUE}║${PLAIN}"
  echo -e "${BLUE}╚════════════════════════════════════════════════╝${PLAIN}"
  echo
}

# 下载 reinstall.sh（如不存在）
ensure_reinstall() {
  if [ ! -f "./reinstall.sh" ]; then
    echo -e "${YELLOW}检测到本地无 reinstall.sh，尝试自动下载...${PLAIN}"
    if ! curl -fsS --connect-timeout 10 -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh; then
      echo -e "${RED}从 GitHub 下载失败，尝试备用国内镜像...${PLAIN}"
      if ! curl -fsS --connect-timeout 10 -O https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh; then
        echo -e "${RED}备用镜像也下载失败。请手动下载 reinstall.sh 到当前目录后再运行本脚本。${PLAIN}"
        return 1
      fi
    fi
    chmod +x ./reinstall.sh
    echo -e "${GREEN}reinstall.sh 已下载并赋予执行权限。${PLAIN}"
  fi
  return 0
}

# 安全执行命令（使用数组）
run_cmd() {
  local -a arr=("$@")
  echo -e "${GREEN}执行：${PLAIN} ${arr[*]}"
  # 最终再二次确认
  read -rp "$(echo -e "${BLUE}确认要现在执行该命令吗？(y/N): ${PLAIN}")" ok
  if [[ "${ok,,}" == "y" ]]; then
    "${arr[@]}"
  else
    echo -e "${YELLOW}已取消执行。返回菜单。${PLAIN}"
    sleep 1
  fi
}

read_choice() {
  read -rp "$(echo -e "${BLUE}请输入序号：${PLAIN}")" choice
  echo "$choice"
}

# 帮助函数：选择版本（数组参数）
select_version_menu() {
  local -n __versions=$1
  echo
  for i in "${!__versions[@]}"; do
    printf "%2d) %s\n" $((i+1)) "${__versions[$i]}"
  done
  echo " 0) 手动输入 / 选择最新版"
  read -rp "$(echo -e "${BLUE}请选择版本序号（0 为手动输入或默认）:${PLAIN} ")" vchoice
  if [[ -z "$vchoice" || "$vchoice" == "0" ]]; then
    read -rp "请输入自定义版本（留空表示使用最新版）: " custom_ver
    echo "$custom_ver"
  else
    if ! [[ "$vchoice" =~ ^[0-9]+$ ]] || (( vchoice < 1 || vchoice > ${#__versions[@]} )); then
      echo ""
    else
      echo "${__versions[$((vchoice-1))]}"
    fi
  fi
}

linux_install() {
  title
  echo -e "${YELLOW}请选择要安装的 Linux 发行版：${PLAIN}"
  echo " 1) Debian"
  echo " 2) Ubuntu"
  echo " 3) CentOS Stream"
  echo " 4) Rocky"
  echo " 5) Fedora"
  echo " 6) Arch"
  echo " 7) Alpine"
  echo " 8) openEuler"
  echo " 9) Gentoo"
  echo "10) 安同 OS (aosc)"
  echo "11) 飞牛 fnOS (fnos)"
  echo " 0) 返回上级"
  read -rp "$(echo -e "${BLUE}请输入序号：${PLAIN}")" os_choice

  case "$os_choice" in
    1) distro="debian"; versions=(9 10 11 12 13) ;;
    2) distro="ubuntu"; versions=("16.04" "18.04" "20.04" "22.04" "24.04" "25.10") ;;
    3) distro="centos"; versions=(9 10) ;;
    4) distro="rocky"; versions=(8 9 10) ;;
    5) distro="fedora"; versions=(41 42) ;;
    6) distro="arch"; versions=("rolling") ;;
    7) distro="alpine"; versions=("3.19" "3.20" "3.21" "3.22") ;;
    8) distro="openeuler"; versions=("20.03" "22.03" "24.03" "25.09") ;;
    9) distro="gentoo"; versions=("rolling") ;;
    10) distro="aosc"; versions=("rolling") ;;
    11) distro="fnos"; versions=("公测") ;;
    0) return ;;
    *) echo -e "${RED}无效输入，返回。${PLAIN}" && sleep 1 && return ;;
  esac

  version="$(select_version_menu versions)"
  read -rp "$(echo -e "${BLUE}是否最小化安装（--minimal）？(y/N): ${PLAIN}")" minimal
  read -rp "$(echo -e "${BLUE}是否设置 root 密码？(y/N): ${PLAIN}")" pw_yes
  if [[ "${pw_yes,,}" == "y" ]]; then
    read -s -rp "请输入密码：" password; echo
  fi
  read -rp "$(echo -e "${BLUE}是否设置 SSH 公钥？(y/N): ${PLAIN}")" key_yes
  if [[ "${key_yes,,}" == "y" ]]; then
    read -rp "请输入公钥或路径（支持 github:your_username）： " ssh_key
  fi
  read -rp "$(echo -e "${BLUE}是否修改 SSH 端口？(y/N): ${PLAIN}")" port_yes
  if [[ "${port_yes,,}" == "y" ]]; then
    read -rp "请输入端口号：" ssh_port
  fi

  # 构造参数数组（避免 eval）
  cmd=("bash" "./reinstall.sh" "$distro")
  if [[ -n "${version:-}" ]]; then cmd+=("$version"); fi
  if [[ "${minimal,,}" == "y" ]]; then cmd+=(--minimal); fi
  if [[ "${pw_yes,,}" == "y" ]]; then cmd+=(--password "$password"); fi
  if [[ "${key_yes,,}" == "y" ]]; then cmd+=(--ssh-key "$ssh_key"); fi
  if [[ "${port_yes,,}" == "y" ]]; then cmd+=(--ssh-port "$ssh_port"); fi

  title
  echo -e "${GREEN}将执行命令：${PLAIN} ${cmd[*]}"
  run_cmd "${cmd[@]}"
}

dd_install() {
  title
  echo -e "${YELLOW}DD Raw 镜像到硬盘（会清除目标硬盘数据）${PLAIN}"
  # 允许用户选择“目标系统类型”（可帮助用户确认镜像是否兼容，比如 fnos）
  echo "可选：选择该镜像所属的目标系统（仅作提示，不会修改行为）"
  echo " 1) fnOS"
  echo " 2) Windows (DD)"
  echo " 3) Linux (generic)"
  echo " 0) 跳过 / 未知"
  read -rp "$(echo -e "${BLUE}请选择序号（0 跳过）:${PLAIN} ")" dd_target_choice
  case "$dd_target_choice" in
    1) dd_target_hint="fnos" ;;
    2) dd_target_hint="windows" ;;
    3) dd_target_hint="linux" ;;
    *) dd_target_hint="" ;;
  esac

  read -rp "请输入镜像链接（支持 http(s) / magnet / 文件路径）: " img
  if [[ -z "$img" ]]; then
    echo -e "${RED}镜像链接不能为空，返回。${PLAIN}"; sleep 1; return
  fi

  read -rp "$(echo -e "${BLUE}是否允许 Ping (仅限 Windows DD)？(y/N): ${PLAIN}")" ping_yes
  read -rp "$(echo -e "${BLUE}是否修改 RDP 端口？(y/N): ${PLAIN}")" rdp_yes
  if [[ "${rdp_yes,,}" == "y" ]]; then read -rp "请输入 RDP 端口号: " rdp_port; fi
  read -rp "$(echo -e "${BLUE}是否修改 SSH 端口？(y/N): ${PLAIN}")" ssh_yes
  if [[ "${ssh_yes,,}" == "y" ]]; then read -rp "请输入 SSH 端口号: " ssh_port; fi
  read -rp "$(echo -e "${BLUE}安装结束后是否保持系统不自动重启（--hold 2）？(y/N): ${PLAIN}")" hold_yes
  if [[ "${hold_yes,,}" == "y" ]]; then hold_flag="--hold 2"; else hold_flag=""; fi

  # 构造安全参数数组
  cmd=("bash" "./reinstall.sh" "dd" "--img" "$img")
  if [[ "${ping_yes,,}" == "y" ]]; then cmd+=(--allow-ping); fi
  if [[ "${rdp_yes,,}" == "y" ]]; then cmd+=(--rdp-port "$rdp_port"); fi
  if [[ "${ssh_yes,,}" == "y" ]]; then cmd+=(--ssh-port "$ssh_port"); fi
  if [[ -n "$hold_flag" ]]; then cmd+=($hold_flag); fi

  # 额外提示（若选择 fnos，给出提醒）
  if [[ "$dd_target_hint" == "fnos" ]]; then
    echo -e "${YELLOW}提示：你选择了 fnOS 作为目标镜像类型。请确保镜像为 fnOS 官方或兼容 raw/dd 镜像（未损坏）。${PLAIN}"
  fi

  title
  echo -e "${GREEN}将执行命令：${PLAIN} ${cmd[*]}"
  run_cmd "${cmd[@]}"
}

alpine_live() {
  title
  echo -e "${YELLOW}启动 Alpine Live（内存系统，不会自动重装）${PLAIN}"
  read -rp "$(echo -e "${BLUE}是否设置密码（root 默认 123@@@）？(y/N): ${PLAIN}")" pw_yes
  if [[ "${pw_yes,,}" == "y" ]]; then read -s -rp "请输入密码: " password; echo; fi
  read -rp "$(echo -e "${BLUE}是否设置 SSH 公钥？(y/N): ${PLAIN}")" key_yes
  if [[ "${key_yes,,}" == "y" ]]; then read -rp "请输入公钥或路径： " ssh_key; fi

  cmd=("bash" "./reinstall.sh" "alpine" "--hold=1")
  if [[ "${pw_yes,,}" == "y" ]]; then cmd+=(--password "$password"); fi
  if [[ "${key_yes,,}" == "y" ]]; then cmd+=(--ssh-key "$ssh_key"); fi

  title
  echo -e "${GREEN}将执行命令：${PLAIN} ${cmd[*]}"
  run_cmd "${cmd[@]}"
}

netboot_xyz() {
  title
  echo -e "${YELLOW}引导到 netboot.xyz（用于手动安装，不会删除数据）${PLAIN}"
  cmd=("bash" "./reinstall.sh" "netboot.xyz")
  echo -e "${GREEN}将执行命令：${PLAIN} ${cmd[*]}"
  run_cmd "${cmd[@]}"
}

windows_install() {
  title
  echo -e "${YELLOW}Windows 安装（ISO 模式）${PLAIN}"
  echo " 1) 自动查找 ISO（脚本会尝试从 massgrave.dev 获取官方 ISO）"
  echo " 2) 手动指定 ISO 链接或 magnet"
  read -rp "$(echo -e "${BLUE}请选择：${PLAIN}")" wmode
  read -rp "请输入映像名称（image-name，例如：Windows 11 Enterprise LTSC 2024）: " img_name
  read -rp "请输入语言代码（例如 zh-cn, en-us）: " lang

  cmd=("bash" "./reinstall.sh" "windows" "--image-name" "$img_name" "--lang" "$lang")
  if [[ "$wmode" == "2" ]]; then
    read -rp "请输入 ISO 链接或 magnet 链接: " iso
    if [[ -z "$iso" ]]; then echo -e "${RED}ISO 链接不能为空，取消。${PLAIN}"; sleep 1; return; fi
    cmd+=("--iso" "$iso")
  fi

  read -rp "$(echo -e "${BLUE}是否设置管理员密码？(y/N): ${PLAIN}")" pw_yes
  if [[ "${pw_yes,,}" == "y" ]]; then read -s -rp "请输入密码: " password; echo; cmd+=(--password "$password"); fi
  read -rp "$(echo -e "${BLUE}是否允许 Ping？(y/N): ${PLAIN}")" ping_yes
  if [[ "${ping_yes,,}" == "y" ]]; then cmd+=(--allow-ping); fi
  read -rp "$(echo -e "${BLUE}是否修改 RDP 端口？(y/N): ${PLAIN}")" rdp_yes
  if [[ "${rdp_yes,,}" == "y" ]]; then read -rp "请输入 RDP 端口: " rdp_port; cmd+=(--rdp-port "$rdp_port"); fi

  title
  echo -e "${GREEN}将执行命令：${PLAIN} ${cmd[*]}"
  run_cmd "${cmd[@]}"
}

main_menu() {
  while true; do
    title
    # 确保 reinstall.sh 可用；若失败会提示用户手动准备
    if ! ensure_reinstall; then
      echo -e "${YELLOW}提示：若你在 Windows 上运行，请手动下载 reinstall.bat 并在 cmd 下运行。${PLAIN}"
    fi
    echo -e "${YELLOW}请选择功能：${PLAIN}"
    echo " 1) 一键重装到 Linux"
    echo " 2) 一键 DD Raw 镜像到硬盘"
    echo " 3) 引导到 Alpine Live OS（内存）"
    echo " 4) 引导到 netboot.xyz"
    echo " 5) 一键重装到 Windows (ISO)"
    echo " 0) 退出"
    read -rp "$(echo -e "${BLUE}请输入序号：${PLAIN}")" m
    case "$m" in
      1) linux_install ;;
      2) dd_install ;;
      3) alpine_live ;;
      4) netboot_xyz ;;
      5) windows_install ;;
      0) echo -e "${GREEN}再见！${PLAIN}"; exit 0 ;;
      *) echo -e "${RED}无效输入。回到主菜单。${PLAIN}"; sleep 1 ;;
    esac
  done
}

main_menu
