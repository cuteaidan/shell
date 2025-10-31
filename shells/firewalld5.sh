#!/usr/bin/env bash
# firewalld5.sh
# firewalld 管理脚本 v5
# - 分页显示开放端口（每页10条，n 下一页，b 上一页，q 返回）
# - 显示方向/协议/端口/监听状态/程序名（支持 TCP + UDP，范围端口检测：若范围内任一端口在监听则视为监听）
# - 兼容性/安全性：保留 SSH，兼容无颜色终端与 firewalld 停止时不退出

set -o errexit
set -o pipefail
set -o nounset

# ---------------- Colors ----------------
if [ -t 1 ]; then
    RED="\033[1;31m"
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;34m"
    CYAN="\033[1;36m"
    RESET="\033[0m"
    DIM="\033[2m"
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""; DIM=""
fi

# ---------------- Config ----------------
PAGE_SIZE=10

# ---------------- Utility ----------------
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

# safe run block to avoid errexit for optional commands
safe_run() {
    set +e
    "$@"
    local rc=$?
    set -e
    return $rc
}

# ---------------- Gather listeners (TCP + UDP) ----------------
# Build associative arrays:
# LISTENING["tcp:80"]="1"
# PROC["tcp:80"]="nginx"
declare -A LISTENING
declare -A PROC

gather_listeners() {
    # clear arrays
    LISTENING=()
    PROC=()

    # TCP listeners
    set +e
    tcp_lines=$(ss -ltnp 2>/dev/null || true)
    udp_lines=$(ss -lunp 2>/dev/null || true)
    set -e

    # Parse TCP: find lines containing "0.0.0.0:80" or "[::]:80"
    # Example: LISTEN   0      128         0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=123,fd=6))
    if [ -n "$tcp_lines" ]; then
        while IFS= read -r line; do
            # extract address:port (the 4th or 5th column may vary) -- use awk to find fields containing ':' (address:port)
            addrport=$(echo "$line" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /:[0-9]+$/) { print $i; exit } }')
            procfield=$(echo "$line" | grep -oP 'users:\(\K.*(?=\))' 2>/dev/null || true)
            if [ -n "$addrport" ]; then
                # extract port
                port=$(echo "$addrport" | awk -F: '{print $NF}')
                key="tcp:${port}"
                LISTENING["$key"]="1"
                if [ -n "$procfield" ]; then
                    # procfield could be: ("nginx",pid=123,fd=6),("...")...
                    # extract first program name
                    pname=$(echo "$procfield" | sed -E 's/^"([^"]+)".*/\1/' 2>/dev/null || true)
                    if [ -z "$pname" ]; then
                        # fallback parse
                        pname=$(echo "$procfield" | awk -F'[(",)]' '{for(i=1;i<=NF;i++) if ($i ~ /^[a-zA-Z0-9._-]+$/) {print $i; exit}}' 2>/dev/null || true)
                    fi
                    PROC["$key"]="$pname"
                fi
            fi
        done <<< "$tcp_lines"
    fi

    # Parse UDP
    if [ -n "$udp_lines" ]; then
        while IFS= read -r line; do
            addrport=$(echo "$line" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /:[0-9]+$/) { print $i; exit } }')
            procfield=$(echo "$line" | grep -oP 'users:\(\K.*(?=\))' 2>/dev/null || true)
            if [ -n "$addrport" ]; then
                port=$(echo "$addrport" | awk -F: '{print $NF}')
                key="udp:${port}"
                LISTENING["$key"]="1"
                if [ -n "$procfield" ]; then
                    pname=$(echo "$procfield" | sed -E 's/^"([^"]+)".*/\1/' 2>/dev/null || true)
                    if [ -z "$pname" ]; then
                        pname=$(echo "$procfield" | awk -F'[(",)]' '{for(i=1;i<=NF;i++) if ($i ~ /^[a-zA-Z0-9._-]+$/) {print $i; exit}}' 2>/dev/null || true)
                    fi
                    PROC["$key"]="$pname"
                fi
            fi
        done <<< "$udp_lines"
    fi
}

# Helper: check if any port in a range is listening, return proc name for first match (or -)
# input: proto (tcp/udp) and port_str (e.g., 80 or 39000-40000)
check_listen_and_proc() {
    local proto=$1
    local port_str=$2
    local key
    if [[ "$port_str" == *-* ]]; then
        IFS='-' read -r start end <<< "$port_str"
        # safeguard numeric
        if ! [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]]; then
            echo "0|-"  # not numeric range
            return
        fi
        for ((p=start; p<=end; p++)); do
            key="${proto}:${p}"
            if [ "${LISTENING[$key]:-}" = "1" ]; then
                echo "1|${PROC[$key]:--}"
                return
            fi
        done
        echo "0|-"
    else
        key="${proto}:${port_str}"
        if [ "${LISTENING[$key]:-}" = "1" ]; then
            echo "1|${PROC[$key]:--}"
        else
            echo "0|-"
        fi
    fi
}

# ---------------- Show firewall status & paged ports ----------------
show_fw_status_with_paging() {
    echo -e "${CYAN}================ 防火墙状态 =================${RESET}"

    if [ "$FW_TYPE" = "firewalld" ]; then
        # tolerate failures here
        set +e
        firewalld_status=$(systemctl is-active firewalld 2>/dev/null || true)
        ports_raw=$(firewall-cmd --list-ports 2>/dev/null || true)
        services=$(firewall-cmd --list-services 2>/dev/null || true)
        set -e

        if [ "$firewalld_status" = "active" ]; then
            STATUS="${GREEN}running${RESET}"
        else
            STATUS="${RED}stopped${RESET}"
        fi
        echo -e "firewalld 状态: $STATUS"
        echo -e "${YELLOW}已启用服务: ${RESET}${services:--}"
    elif [ "$FW_TYPE" = "ufw" ]; then
        echo -e "${YELLOW}ufw 状态:${RESET}"
        set +e
        ufw status verbose || true
        set -e
        return
    elif [ "$FW_TYPE" = "iptables" ]; then
        echo -e "${YELLOW}iptables 规则:${RESET}"
        set +e
        iptables -L -n -v || true
        set -e
        return
    else
        echo -e "${RED}未检测到可用防火墙${RESET}"
        return
    fi

    # Build array of port entries (direction/proto/port_str)
    IFS=$'\n' read -r -d '' -a port_entries <<< "$(printf "%s\n" $ports_raw; printf "\0")"

    # flatten: some systems may return nothing -> handle
    entries=()
    for entry in "${port_entries[@]:-}"; do
        # skip empty
        [ -z "$entry" ] && continue
        # entry format examples: "80/tcp" or "39000-40000/tcp"
        proto="${entry##*/}"
        portstr="${entry%%/*}"
        entries+=("in|${proto}|${portstr}")
    done

    # if no entries, show message
    if [ ${#entries[@]} -eq 0 ]; then
        echo "开放端口表格: （暂无开放端口）"
        echo -e "${CYAN}===========================================${RESET}"
        return
    fi

    # gather listeners snapshot
    gather_listeners

    # Pagination variables
    total=${#entries[@]}
    pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))
    page=1

    # Pagination loop
    while true; do
        clear -x
        echo -e "${CYAN}================ 防火墙状态 =================${RESET}"
        if [ "$firewalld_status" = "active" ]; then
            STATUS="${GREEN}running${RESET}"
        else
            STATUS="${RED}stopped${RESET}"
        fi
        echo -e "firewalld 状态: $STATUS"
        echo -e "${YELLOW}已启用服务: ${RESET}${services:--}"
        echo
        echo -e "${YELLOW}开放端口表格 (第 ${page}/${pages} 页)：${RESET}"
        printf "%-6s %-8s %-18s %-10s %-16s\n" "方向" "协议" "端口" "监听" "程序"
        echo "-------------------------------------------------------------------------------"

        start=$(( (page-1) * PAGE_SIZE ))
        end=$(( start + PAGE_SIZE - 1 ))
        if [ $end -ge $(( total - 1 )) ]; then
            end=$(( total - 1 ))
        fi

        for idx in $(seq $start $end); do
            line="${entries[$idx]}"
            IFS='|' read -r direction proto portstr <<< "$line"

            # check listen & proc
            res=$(check_listen_and_proc "$proto" "$portstr")
            is_listen=${res%%|*}
            pname=${res#*|}
            if [ "$is_listen" = "1" ]; then
                listen_display="${GREEN}✔${RESET}"
                pname_display="${pname:--}"
            else
                listen_display="${DIM}✖${RESET}"
                pname_display="-"
            fi

            printf "%-6s %-8s %-18s %-10s %-16s\n" "$direction" "$proto" "$portstr" "$listen_display" "$pname_display"
        done

        echo "-------------------------------------------------------------------------------"
        echo -e "${CYAN}操作: n 下一页 | b 上一页 | q 返回菜单${RESET}"
        read -r -p "输入: " nav </dev/tty
        nav=$(echo "$nav" | tr '[:upper:]' '[:lower:]' | xargs || true)
        case "$nav" in
            n)
                if [ $page -lt $pages ]; then
                    page=$((page+1))
                else
                    # already last
                    :
                fi
                ;;
            b)
                if [ $page -gt 1 ]; then
                    page=$((page-1))
                else
                    :
                fi
                ;;
            q|"")
                break
                ;;
            *)
                # treat numbers as jump to page optionally
                if [[ "$nav" =~ ^[0-9]+$ ]]; then
                    if [ "$nav" -ge 1 ] && [ "$nav" -le $pages ]; then
                        page=$nav
                    fi
                fi
                ;;
        esac
    done

    echo -e "${CYAN}===========================================${RESET}"
}

# ---------------- Other operations (temp/permanent/open/close/install/uninstall) ----------------

toggle_fw_temp() {
    if [ "$FW_TYPE" != "firewalld" ]; then
        echo -e "${RED}当前非 firewalld，暂不支持临时开关（脚本支持 ufw/iptables 的部分功能）${RESET}"
        return
    fi
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
}

toggle_fw_permanent() {
    if [ "$FW_TYPE" != "firewalld" ]; then
        echo -e "${RED}当前非 firewalld，暂不支持永久开关（脚本支持 ufw/iptables 的部分功能）${RESET}"
        return
    fi
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
}

open_port() {
    read -r -p "请输入端口号: " PORT </dev/tty
    read -r -p "请输入协议(tcp/udp): " PROTO </dev/tty
    PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]' | xargs)
    if [ "$PORT" -eq 22 ] 2>/dev/null; then
        echo -e "${YELLOW}SSH 端口默认开放，无需修改${RESET}"
        return
    fi
    if [ "$FW_TYPE" = "firewalld" ]; then
        set +e
        firewall-cmd --permanent --add-port="$PORT/$PROTO" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        set -e
        echo -e "${GREEN}$PORT/$PROTO 已开放${RESET}"
    elif [ "$FW_TYPE" = "ufw" ]; then
        ufw allow "$PORT"/"$PROTO"
    elif [ "$FW_TYPE" = "iptables" ]; then
        iptables -A INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT
    else
        echo -e "${RED}未检测到可用防火墙${RESET}"
    fi
}

close_port() {
    read -r -p "请输入端口号: " PORT </dev/tty
    read -r -p "请输入协议(tcp/udp): " PROTO </dev/tty
    PROTO=$(echo "$PROTO" | tr '[:upper:]' '[:lower:]' | xargs)
    if [ "$PORT" -eq 22 ] 2>/dev/null; then
        echo -e "${YELLOW}SSH 端口默认开放，不能关闭${RESET}"
        return
    fi
    if [ "$FW_TYPE" = "firewalld" ]; then
        set +e
        firewall-cmd --permanent --remove-port="$PORT/$PROTO" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        set -e
        echo -e "${RED}$PORT/$PROTO 已关闭${RESET}"
    elif [ "$FW_TYPE" = "ufw" ]; then
        ufw delete allow "$PORT"/"$PROTO"
    elif [ "$FW_TYPE" = "iptables" ]; then
        iptables -D INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT
    else
        echo -e "${RED}未检测到可用防火墙${RESET}"
    fi
}

install_fw() {
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt update && apt install -y ufw
        ufw enable || true
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        yum install -y firewalld || true
        systemctl enable --now firewalld || true
    else
        echo -e "${YELLOW}请根据发行版手动安装 firewalld/ufw${RESET}"
    fi
    detect_firewall
}

uninstall_fw() {
    if [ "$FW_TYPE" = "firewalld" ]; then
        systemctl stop firewalld || true
        if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
            yum remove -y firewalld || true
        fi
    elif [ "$FW_TYPE" = "ufw" ]; then
        ufw disable || true
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            apt remove -y ufw || true
        fi
    else
        echo -e "${YELLOW}无已知防火墙可卸载${RESET}"
    fi
    detect_firewall
}

# ---------------- Main menu ----------------
main_menu() {
    while true; do
        clear
        detect_firewall
        show_fw_status_with_paging
        echo -e "${BLUE}================ 防火墙管理菜单 ================${RESET}"
        echo "1) 临时开/关防火墙"
        echo "2) 永久开/关防火墙"
        echo "3) 开放端口"
        echo "4) 关闭端口"
        echo "5) 安装防火墙"
        echo "6) 卸载防火墙"
        echo "0) 退出"
        read -r -p "请选择操作: " CHOICE </dev/tty
        case "$CHOICE" in
            1) toggle_fw_temp ;;
            2) toggle_fw_permanent ;;
            3) open_port ;;
            4) close_port ;;
            5) install_fw ;;
            6) uninstall_fw ;;
            0) exit 0 ;;
            *)
                echo -e "${RED}无效选择${RESET}"
                ;;
        esac
        echo -e "${CYAN}按回车返回菜单...${RESET}"
        read -r </dev/tty || true
    done
}

# ---------------- Start ----------------
detect_os
detect_firewall
main_menu
