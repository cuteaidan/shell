#!/usr/bin/env bash
# reinstall-launcher.sh
# 一键重装脚本启动器 by ChatGPT (为 bin456789/reinstall 定制)
# 兼容绝大多数 Linux 发行版（bash/sh）

# ==========【颜色定义】==========
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
RESET='\033[0m'

# ==========【标题显示函数】==========
title() {
  clear
  echo -e "${BLUE}╔══════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║     一键 VPS 系统重装 启动器        ║${RESET}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${RESET}"
  echo
}

pause() {
  echo
  read -rp "按回车键继续..." _
}

# ==========【检测并下载 reinstall.sh】==========
download_script() {
  echo -e "${YELLOW}正在检测网络环境...${RESET}"
  if curl -s --connect-timeout 3 https://raw.githubusercontent.com >/dev/null 2>&1; then
    SRC="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
    echo -e "${GREEN}检测到国外网络环境，使用 GitHub 源${RESET}"
  else
    SRC="https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh"
    echo -e "${GREEN}检测到国内网络环境，使用 CNB 镜像源${RESET}"
  fi

  if [ ! -f reinstall.sh ]; then
    echo -e "${YELLOW}正在下载 reinstall.sh ...${RESET}"
    if ! curl -fsSL "$SRC" -o reinstall.sh && ! wget -qO reinstall.sh "$SRC"; then
      echo -e "${RED}下载失败，请检查网络连接！${RESET}"
      exit 1
    fi
  else
    echo -e "${GREEN}检测到已有 reinstall.sh 文件，将直接使用${RESET}"
  fi

  chmod +x reinstall.sh
}

# ==========【菜单：选择系统】==========
choose_system() {
  title
  echo -e "${CYAN}请选择要安装的系统：${RESET}"
  echo "  1) Ubuntu"
  echo "  2) Debian"
  echo "  3) CentOS / AlmaLinux / Rocky"
  echo "  4) Fedora"
  echo "  5) openEuler"
  echo "  6) Alpine"
  echo "  7) Arch"
  echo "  8) Windows"
  echo "  9) 退出"
  echo
  read -rp "请输入编号 [1-9]: " sys_choice

  case $sys_choice in
    1) SYSTEM="ubuntu" ;;
    2) SYSTEM="debian" ;;
    3) SYSTEM="almalinux" ;;
    4) SYSTEM="fedora" ;;
    5) SYSTEM="openeuler" ;;
    6) SYSTEM="alpine" ;;
    7) SYSTEM="arch" ;;
    8) SYSTEM="windows" ;;
    9) echo -e "${YELLOW}已退出。${RESET}"; exit 0 ;;
    *) echo -e "${RED}无效输入！${RESET}"; pause; choose_system ;;
  esac
}

# ==========【菜单：选择版本】==========
choose_version() {
  title
  case $SYSTEM in
    ubuntu)
      echo -e "${CYAN}请选择 Ubuntu 版本：${RESET}"
      echo "1) 16.04   2) 18.04   3) 20.04"
      echo "4) 22.04   5) 24.04   6) 25.10"
      read -rp "请输入编号 [1-6]: " v
      VERSION=(16.04 18.04 20.04 22.04 24.04 25.10) 
      VERSION=${VERSION[$((v-1))]:-24.04}
      ;;
    debian)
      echo -e "${CYAN}请选择 Debian 版本：${RESET}"
      echo "1) 9   2) 10   3) 11   4) 12   5) 13"
      read -rp "请输入编号 [1-5]: " v
      VERSION=(9 10 11 12 13)
      VERSION=${VERSION[$((v-1))]:-12}
      ;;
    almalinux)
      echo -e "${CYAN}请选择 CentOS/AlmaLinux/Rocky 版本：${RESET}"
      echo "1) 8   2) 9   3) 10"
      read -rp "请输入编号 [1-3]: " v
      VERSION=(8 9 10)
      VERSION=${VERSION[$((v-1))]:-9}
      ;;
    fedora)
      echo -e "${CYAN}请选择 Fedora 版本：${RESET}"
      echo "1) 41   2) 42"
      read -rp "请输入编号 [1-2]: " v
      VERSION=(41 42)
      VERSION=${VERSION[$((v-1))]:-42}
      ;;
    openeuler)
      echo -e "${CYAN}请选择 openEuler 版本：${RESET}"
      echo "1) 20.03  2) 22.03  3) 24.03  4) 25.09"
      read -rp "请输入编号 [1-4]: " v
      VERSION=(20.03 22.03 24.03 25.09)
      VERSION=${VERSION[$((v-1))]:-24.03}
      ;;
    alpine)
      echo -e "${CYAN}请选择 Alpine 版本：${RESET}"
      echo "1) 3.19  2) 3.20  3) 3.21  4) 3.22"
      read -rp "请输入编号 [1-4]: " v
      VERSION=(3.19 3.20 3.21 3.22)
      VERSION=${VERSION[$((v-1))]:-3.21}
      ;;
    arch)
      VERSION="rolling"
      ;;
    windows)
      echo -e "${CYAN}请选择 Windows 版本：${RESET}"
      echo "1) Windows 10  (2021 LTSC)"
      echo "2) Windows 11  (2024 LTSC)"
      echo "3) Windows Server 2025"
      read -rp "请输入编号 [1-3]: " v
      case $v in
        1) IMAGE_NAME="Windows 10 Enterprise LTSC 2021";;
        2) IMAGE_NAME="Windows 11 Enterprise LTSC 2024";;
        3) IMAGE_NAME="Windows Server 2025 SERVERDATACENTER";;
        *) IMAGE_NAME="Windows 11 Enterprise LTSC 2024";;
      esac
      ;;
  esac
}

# ==========【输入参数】==========
input_params() {
  echo
  read -rp "请输入 root 密码 (默认: 123@@@): " PASSWORD
  PASSWORD=${PASSWORD:-123@@@}

  read -rp "请输入 SSH 端口 (默认: 22): " SSH_PORT
  SSH_PORT=${SSH_PORT:-22}

  read -rp "请输入 Web 日志端口 (默认: 80): " WEB_PORT
  WEB_PORT=${WEB_PORT:-80}

  if [[ $SYSTEM == "windows" ]]; then
    read -rp "允许被 Ping？(y/N): " ALLOW_PING
    [ "${ALLOW_PING,,}" = "y" ] && ALLOW_PING="--allow-ping" || ALLOW_PING=""
    read -rp "语言 (默认 zh-cn): " LANG
    LANG=${LANG:-zh-cn}
  else
    read -rp "是否添加 SSH 公钥？(y/N): " ADD_KEY
    if [[ ${ADD_KEY,,} == "y" ]]; then
      read -rp "请输入公钥内容或URL: " SSH_KEY
      SSH_KEY="--ssh-key \"$SSH_KEY\""
    else
      SSH_KEY=""
    fi
  fi
}

# ==========【生成命令】==========
build_command() {
  if [[ $SYSTEM == "windows" ]]; then
    CMD="bash reinstall.sh windows --image-name \"$IMAGE_NAME\" --lang $LANG --password \"$PASSWORD\" --ssh-port $SSH_PORT --web-port $WEB_PORT $ALLOW_PING"
  else
    CMD="bash reinstall.sh $SYSTEM $VERSION --password \"$PASSWORD\" --ssh-port $SSH_PORT --web-port $WEB_PORT $SSH_KEY"
  fi
}

# ==========【确认并执行】==========
confirm_and_run() {
  echo
  echo -e "${YELLOW}即将执行以下命令：${RESET}"
  echo -e "${GREEN}$CMD${RESET}"
  echo
  read -rp "确认开始安装吗？(y/N): " CONFIRM
  if [[ ${CONFIRM,,} == "y" ]]; then
    eval "$CMD"
  else
    echo -e "${RED}已取消安装。${RESET}"
  fi
}

# ==========【主程序入口】==========
main() {
  title
  echo -e "${CYAN}欢迎使用一键 VPS 系统重装 启动器${RESET}"
  echo
  echo -e "${YELLOW}本启动器将引导你选择系统、版本，并调用官方 reinstall.sh${RESET}"
  echo -e "${RED}警告：此操作将清空硬盘所有数据，请谨慎使用！${RESET}"
  echo
  pause

  download_script
  choose_system
  choose_version
  input_params
  build_command
  confirm_and_run
}

main
