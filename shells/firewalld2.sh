#!/usr/bin/env bash
# universal_firewall_manager_safe_v3.sh
# 安全、兼容、防止菜单自动退出，表格化显示防火墙状态

set -o errexit
set -o pipefail
set -o nounset

# ====== 颜色 ======
if [ -t 1 ]; then
    RED="\033[1;31m"
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;34m"
    CYAN="\033[1;36m"
    RESET="\033[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    RESET=""
fi

# ====== 系统检测 ======
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s)
    fi
}

# ====== 防火墙类型检测 ======
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

# ====== 显示防火墙状态和端口表格 ======
show_fw_status() {
    echo -e "${CYAN}================ 防火墙状态 =================${RESET}"
    if [ "$FW_TYPE" = "firewalld" ]; then
        # 安全获取 firewalld 状态
        firewalld_status=$(systemctl is-active firewalld 2>/dev/null)
        if [ "$firewalld_status" = "active" ]; then
            STATUS="${GREEN}running${RESET}"
        else
            STATUS="${RED}stopped${RESET}"
        fi
        echo -e "firewalld 状态: $STATUS"

        # 表格化端口显示
        echo -e "${YELLOW}开放端口表格:${RESET}"
        printf "%-8s %-10s %-20s\n" "方向" "协议" "端口"
        echo "-------------------------------------------"
        # 入站 TCP/UDP
        for port in $(firewall-cmd --list-ports 2>/dev/null); do
            proto="${port##*/}"
            p="${port%%/*}"
            printf "%-8s %-10s %-20s\n" "in" "$proto" "$p"
        done
        # ICMP（仅支持的版本）
        if firewall-cmd --help | grep -q -- "--get-icmp-blocks"; then
            icmp_list=$(firewall-cmd --get-icmp-blocks 2>/dev/null)
            [ -n "$icmp_list" ] && printf "%-8s %-10s %-20s\n" "in" "icmp" "$icmp_list"
        fi
        # 服务
        services=$(firewall-cmd --list-services 2>/dev/null)
        [ -n "$services" ] && echo -e "${GREEN}已启用服务: $services${RESET}"
    elif [ "$FW_TYPE" = "ufw" ]; then
        ufw status verbose
    elif [ "$FW_TYPE" = "iptables" ]; then
        echo -e "${YELLOW}iptables 规则表:${RESET}"
        printf "%-8s %-10s %-10s %-10s\n" "链" "协议" "端口" "动作"
        echo "---------------------------------------------"
        iptables -L -n -v | awk '
        /^Chain/ {chain=$2}
        /^[ ]*[0-9]/ {proto=$1; action=$4; port=""; if($1=="tcp" || $1=="udp") {port=$12} print chain"\t"proto"\t"port"\t"action}'
    else
        echo -e "${RED}未检测到可用防火墙${RESET}"
    fi
    echo -e "${CYAN}===========================================${RESET}"
}

# ====== 临时开关防火墙（保留 SSH 端口） ======
toggle_fw_temp() {
    if [ "$FW_TYPE" = "firewalld" ]; then
        read -r -p "请输入操作(open/close): " ACTION </dev/tty
        if [ "$ACTION" = "close" ]; then
            echo -e "${YELLOW}注意：关闭防火墙可能会断开远程 SSH${RESET}"
            read -r -p "确认关闭防火墙？(yes/no): " CONF </dev/tty
            if [ "$CONF" = "yes" ]; then
                systemctl stop firewalld
                echo -e "${RED}firewalld 已临时停止${RESET}"
            fi
        elif [ "$ACTION" = "open" ]; then
            systemctl start firewalld
            echo -e "${GREEN}firewalld 已临时启动${RESET}"
        fi
    elif [ "$FW_TYPE" = "ufw" ]; then
        read -r -p "请输入操作(enable/disable): " ACTION </dev/tty
        ufw "$ACTION"
    elif [ "$FW_TYPE" = "iptables" ]; then
        echo -e "${YELLOW}iptables 临时操作可通过手动规则管理${RESET}"
    else
        echo -e "${RED}未检测到可用防火墙${RESET}"
    fi
}

# ====== 永久开关防火墙（保留 SSH） ======
toggle_fw_permanent() {
    if [ "$FW_TYPE" = "firewalld" ]; then
        read -r -p "请输入操作(enable/disable): " ACTION </dev/tty
        if [ "$ACTION" = "disable" ]; then
            echo -e "${YELLOW}注意：禁用防火墙可能断开 SSH${RESET}"
            read -r -p "确认禁用防火墙？(yes/no): " CONF </dev/tty
            if [ "$CONF" = "yes" ]; then
                systemctl disable --now firewalld
                echo -e "${RED}firewalld 已永久禁用${RESET}"
            fi
        elif [ "$ACTION" = "enable" ]; then
            systemctl enable --now firewalld
            echo -e "${GREEN}firewalld 已永久启用${RESET}"
        fi
    elif [ "$FW_TYPE" = "ufw" ]; then
        read -r -p "请输入操作(enable/disable): " ACTION </dev/tty
        ufw "$ACTION"
    else
        echo -e "${RED}永久开关暂不支持此防火墙${RESET}"
    fi
}

# ====== 开放端口（自动保留 SSH） ======
open_port() {
    read -r -p "请输入端口号: " PORT </dev/tty
    read -r -p "请输入协议(tcp/udp): " PROTO </dev/tty
    if [ "$PORT" -eq 22 ] 2>/dev/null; then
        echo -e "${YELLOW}SSH 端口默认开放，无需修改${RESET}"
        return
    fi
    if [ "$FW_TYPE" = "firewalld" ]; then
        firewall-cmd --permanent --add-port="$PORT/$PROTO"
        firewall-cmd --reload
        echo -e "${GREEN}$PORT/$PROTO 已开放${RESET}"
    elif [ "$FW_TYPE" = "ufw" ]; then
        ufw allow "$PORT"/"$PROTO"
    elif [ "$FW_TYPE" = "iptables" ]; then
        iptables -A INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT
        echo -e "${GREEN}$PORT/$PROTO 已开放${RESET}"
    else
        echo -e "${RED}未检测到可用防火墙${RESET}"
    fi
}

# ====== 关闭端口 ======
close_port() {
    read -r -p "请输入端口号: " PORT </dev/tty
    read -r -p "请输入协议(tcp/udp): " PROTO </dev/tty
    if [ "$PORT" -eq 22 ] 2>/dev/null; then
        echo -e "${YELLOW}SSH 端口默认开放，不能关闭${RESET}"
        return
    fi
    if [ "$FW_TYPE" = "firewalld" ]; then
        firewall-cmd --permanent --remove-port="$PORT/$PROTO"
        firewall-cmd --reload
        echo -e "${RED}$PORT/$PROTO 已关闭${RESET}"
    elif [ "$FW_TYPE" = "ufw" ]; then
        ufw delete allow "$PORT"/"$PROTO"
    elif [ "$FW_TYPE" = "iptables" ]; then
        iptables -D INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT
        echo -e "${RED}$PORT/$PROTO 已关闭${RESET}"
    else
        echo -e "${RED}未检测到可用防火墙${RESET}"
    fi
}

# ====== 安装防火墙 ======
install_fw() {
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt update && apt install -y ufw
        echo -e "${GREEN}ufw 安装完成${RESET}"
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        yum install -y firewalld
        systemctl enable --now firewalld
        echo -e "${GREEN}firewalld 安装完成${RESET}"
    else
        echo -e "${RED}系统不支持自动安装防火墙，请手动安装${RESET}"
    fi
    detect_firewall
}

# ====== 卸载防火墙 ======
uninstall_fw() {
    if [ "$FW_TYPE" = "firewalld" ]; then
        systemctl stop firewalld
        if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
            yum remove -y firewalld
        fi
        echo -e "${RED}firewalld 已卸载${RESET}"
    elif [ "$FW_TYPE" = "ufw" ]; then
        ufw disable
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            apt remove -y ufw
        fi
        echo -e "${RED}ufw 已卸载${RESET}"
    else
        echo -e "${RED}未检测到可卸载的防火墙${RESET}"
    fi
    detect_firewall
}

# ====== 菜单 ======
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

# ====== 执行 ======
detect_os
detect_firewall
main_menu
