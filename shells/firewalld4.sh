#!/usr/bin/env bash
# universal_firewall_manager_v4.1.sh
# 修复 firewalld 停止后脚本自动退出的问题 + 保留颜色、菜单与缩写功能

set -o errexit
set -o pipefail
set -o nounset

if [ -t 1 ]; then
    RED="\033[1;31m"
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;34m"
    CYAN="\033[1;36m"
    RESET="\033[0m"
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s)
    fi
}

detect_firewall() {
    if command -v firewall-cmd >/dev/null 2>&1; then
        FW_TYPE="firewalld"
    elif command -v ufw >/dev/null 2>&1; then
        FW_TYPE="ufw"
    elif command -v iptables >/dev/null 2>&1; then
        FW_TYPE="iptables"
    else
        FW_TYPE="none"
    fi
}

show_fw_status() {
    echo -e "${CYAN}================ 防火墙状态 =================${RESET}"
    if [ "$FW_TYPE" = "firewalld" ]; then
        # 🔧 临时关闭 errexit，防止命令失败导致退出
        set +e
        firewalld_status=$(systemctl is-active firewalld 2>/dev/null)
        ports=$(firewall-cmd --list-ports 2>/dev/null)
        services=$(firewall-cmd --list-services 2>/dev/null)
        set -e

        if [ "$firewalld_status" = "active" ]; then
            STATUS="${GREEN}running${RESET}"
        else
            STATUS="${RED}stopped${RESET}"
        fi

        echo -e "firewalld 状态: $STATUS"
        echo -e "${YELLOW}开放端口表格:${RESET}"
        printf "%-8s %-10s %-20s\n" "方向" "协议" "端口"
        echo "-------------------------------------------"

        if [ -n "$ports" ]; then
            for port in $ports; do
                proto="${port##*/}"
                p="${port%%/*}"
                printf "%-8s %-10s %-20s\n" "in" "$proto" "$p"
            done
        else
            echo "（暂无开放端口）"
        fi

        [ -n "$services" ] && echo -e "${GREEN}已启用服务: $services${RESET}"
    elif [ "$FW_TYPE" = "ufw" ]; then
        set +e
        ufw status verbose 2>/dev/null || echo -e "${RED}ufw 未启动${RESET}"
        set -e
    elif [ "$FW_TYPE" = "iptables" ]; then
        echo -e "${YELLOW}iptables 规则表:${RESET}"
        set +e
        iptables -L -n -v 2>/dev/null || echo -e "${RED}iptables 未启动${RESET}"
        set -e
    else
        echo -e "${RED}未检测到可用防火墙${RESET}"
    fi
    echo -e "${CYAN}===========================================${RESET}"
}

toggle_fw_temp() {
    if [ "$FW_TYPE" = "firewalld" ]; then
        read -r -p "请输入操作(open/o, close/c): " ACTION </dev/tty
        ACTION=$(echo "$ACTION" | tr '[:upper:]' '[:lower:]' | xargs)
        case "$ACTION" in
            open|o)
                systemctl start firewalld && echo -e "${GREEN}firewalld 已临时启动${RESET}"
                ;;
            close|c)
                echo -e "${YELLOW}注意：关闭防火墙可能断开 SSH${RESET}"
                read -r -p "确认关闭防火墙？(yes/y): " CONF </dev/tty
                CONF=$(echo "$CONF" | tr '[:upper:]' '[:lower:]' | xargs)
                if [[ "$CONF" == "yes" || "$CONF" == "y" ]]; then
                    systemctl stop firewalld && echo -e "${RED}firewalld 已临时关闭${RESET}"
                fi
                ;;
            *)
                echo -e "${RED}无效输入${RESET}"
                ;;
        esac
    else
        echo -e "${RED}当前防火墙类型不支持该操作${RESET}"
    fi
}

toggle_fw_permanent() {
    if [ "$FW_TYPE" = "firewalld" ]; then
        read -r -p "请输入操作(enable/e, disable/d): " ACTION </dev/tty
        ACTION=$(echo "$ACTION" | tr '[:upper:]' '[:lower:]' | xargs)
        case "$ACTION" in
            enable|e)
                systemctl enable --now firewalld && echo -e "${GREEN}firewalld 已永久启用${RESET}"
                ;;
            disable|d)
                echo -e "${YELLOW}注意：禁用防火墙可能断开 SSH${RESET}"
                read -r -p "确认禁用防火墙？(yes/y): " CONF </dev/tty
                CONF=$(echo "$CONF" | tr '[:upper:]' '[:lower:]' | xargs)
                if [[ "$CONF" == "yes" || "$CONF" == "y" ]]; then
                    systemctl disable --now firewalld && echo -e "${RED}firewalld 已永久禁用${RESET}"
                fi
                ;;
            *)
                echo -e "${RED}无效输入${RESET}"
                ;;
        esac
    else
        echo -e "${RED}当前防火墙不支持该操作${RESET}"
    fi
}

open_port() {
    read -r -p "请输入端口号: " PORT </dev/tty
    read -r -p "请输入协议(tcp/udp): " PROTO </dev/tty
    PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]' | xargs)
    [ "$PORT" -eq 22 ] 2>/dev/null && { echo -e "${YELLOW}SSH 端口不能修改${RESET}"; return; }

    if [ "$FW_TYPE" = "firewalld" ]; then
        firewall-cmd --permanent --add-port="$PORT/$PROTO" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        echo -e "${GREEN}$PORT/$PROTO 已开放${RESET}"
    fi
}

close_port() {
    read -r -p "请输入端口号: " PORT </dev/tty
    read -r -p "请输入协议(tcp/udp): " PROTO </dev/tty
    PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]' | xargs)
    [ "$PORT" -eq 22 ] 2>/dev/null && { echo -e "${YELLOW}SSH 端口不能关闭${RESET}"; return; }

    if [ "$FW_TYPE" = "firewalld" ]; then
        firewall-cmd --permanent --remove-port="$PORT/$PROTO" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        echo -e "${RED}$PORT/$PROTO 已关闭${RESET}"
    fi
}

install_fw() {
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        yum install -y firewalld && systemctl enable --now firewalld
    elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt update && apt install -y ufw && ufw enable
    fi
    detect_firewall
}

uninstall_fw() {
    if [ "$FW_TYPE" = "firewalld" ]; then
        systemctl stop firewalld
        yum remove -y firewalld
    elif [ "$FW_TYPE" = "ufw" ]; then
        ufw disable
        apt remove -y ufw
    fi
    detect_firewall
}

main_menu() {
    while true; do
        clear
        detect_firewall
        show_fw_status
        echo -e "${BLUE}================ 防火墙管理菜单 ================${RESET}"
        echo "1) 临时开/关防火墙"
        echo "2) 永久开/关防火墙"
        echo "3) 开放端口"
        echo "4) 关闭端口"
        echo "5) 安装防火墙"
        echo "6) 卸载防火墙"
        echo "0) 退出"
        read -r -p "请选择操作: " CHOICE </dev/tty
        case $CHOICE in
            1) toggle_fw_temp ;;
            2) toggle_fw_permanent ;;
            3) open_port ;;
            4) close_port ;;
            5) install_fw ;;
            6) uninstall_fw ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选择${RESET}" ;;
        esac
        echo -e "${CYAN}按回车返回菜单...${RESET}"
        read -r </dev/tty
    done
}

detect_os
detect_firewall
main_menu
