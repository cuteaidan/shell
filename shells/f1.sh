#!/usr/bin/env bash
# firewalld 管理器 v7 - by Moreanp + ChatGPT
# 兼容性: firewalld / ufw / iptables，支持分页显示和监听进程解析
# 日期: 2025-10-31

set -o errexit
set -o pipefail
set -o nounset

# ====== ANSI 颜色 ======
if [ -t 1 ]; then
  RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
  BLUE='\033[1;34m'; CYAN='\033[1;36m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; DIM=""; RESET=""
fi

# ====== 全局 ======
PAGE_SIZE=10
entries=()
declare -A LISTEN
declare -A INFO

# ====== 检测系统 & 防火墙 ======
detect_fw() {
  if command -v firewall-cmd >/dev/null 2>&1; then
    FW=firewalld
  elif command -v ufw >/dev/null 2>&1; then
    FW=ufw
  elif command -v iptables >/dev/null 2>&1; then
    FW=iptables
  else
    FW=none
  fi
}

# ====== 获取监听信息 ======
scan_listeners() {
  LISTEN=(); INFO=()
  while read -r proto port pid exe comm; do
    key="${proto}:${port}"
    LISTEN["$key"]=1
    short_path="$exe"
    if [ ${#exe} -gt 28 ]; then
      short_path=".../${exe##*/}"
    fi
    INFO["$key"]="${comm:-?}(${pid:-?}) $short_path"
  done < <(
    ss -lntuHp 2>/dev/null | awk '
      NR>1 {
        proto=$1
        sub(/:$/, "", proto)
        split($5,a,":"); port=a[length(a)]
        match($0,/pid=([0-9]+),fd=[0-9]+/ ,p)
        match($0,/users:\(\\"([^\\"]+)\\"/,c)
        match($0,/\\"([^\\"]+)\\"/ ,ex)
        if (p[1] && port ~ /^[0-9]+$/) {
          printf "%s %s %s %s %s\n", proto, port, p[1], ex[1], c[1]
        }
      }')
}

# ====== 获取开放端口 ======
get_ports() {
  entries=()
  if [ "$FW" = "firewalld" ]; then
    ports=$(firewall-cmd --list-ports 2>/dev/null || true)
    if [ -z "$ports" ]; then
      for svc in $(firewall-cmd --list-services 2>/dev/null || true); do
        info=$(firewall-cmd --info-service "$svc" 2>/dev/null || true)
        line=$(echo "$info" | grep -E '^ports:' | cut -d' ' -f2-)
        for token in $line; do
          p=${token%%/*}; proto=${token##*/}
          entries+=("in|$proto|$p")
        done
      done
    else
      for token in $ports; do
        p=${token%%/*}; proto=${token##*/}
        entries+=("in|$proto|$p")
      done
    fi
  else
    entries+=("in|tcp|22")
  fi
}

# ====== 检查监听状态 ======
check_status() {
  local proto=$1 port=$2
  if [[ "$port" == *-* ]]; then
    IFS='-' read -r s e <<<"$port"
    for ((p=s; p<=e; p++)); do
      if [ "${LISTEN["$proto:$p"]+1}" ]; then
        echo "✔|${INFO["$proto:$p"]}"
        return
      fi
    done
    echo "✖|-"
  else
    if [ "${LISTEN["$proto:$port"]+1}" ]; then
      echo "✔|${INFO["$proto:$port"]}"
    else
      echo "✖|-"
    fi
  fi
}

# ====== 显示菜单 + 翻页 ======
show_menu() {
  detect_fw
  scan_listeners
  get_ports
  total=${#entries[@]}
  page=1
  pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))

  while true; do
    clear -x
    echo -e "${CYAN}================ 防火墙状态 =================${RESET}"
    fwstat=$(systemctl is-active firewalld 2>/dev/null || echo stopped)
    if [ "$fwstat" = "active" ]; then
      echo -e "firewalld 状态: ${GREEN}running${RESET}"
    else
      echo -e "firewalld 状态: ${RED}stopped${RESET}"
    fi
    echo -e "${YELLOW}已启用服务:${RESET} $(firewall-cmd --list-services 2>/dev/null || echo '-')"
    echo
    printf "%-6s %-6s %-15s %-8s %-35s\n" "方向" "协议" "端口" "监听" "程序"
    echo "----------------------------------------------------------------------------"

    start=$(( (page-1)*PAGE_SIZE ))
    end=$(( start+PAGE_SIZE-1 ))
    [ $end -ge $((total-1)) ] && end=$((total-1))

    for i in $(seq $start $end); do
      IFS='|' read -r dir proto port <<<"${entries[$i]}"
      res=$(check_status "$proto" "$port")
      st=${res%%|*}; info=${res#*|}
      if [ "$st" = "✔" ]; then
        st="${GREEN}✔${RESET}"
      else
        st="${DIM}✖${RESET}"
      fi
      printf "%-6s %-6s %-15s %-8b %-35.35s\n" "$dir" "$proto" "$port" "$st" "$info"
    done

    echo "----------------------------------------------------------------------------"
    echo -e "${CYAN}第 ${page}/${pages} 页 | n 下一页 | b 上一页 | 选择功能 [1-6,0退出]${RESET}"
    echo -e "${BLUE}================ 防火墙管理菜单 ================${RESET}"
    echo "1) 临时开/关防火墙"
    echo "2) 永久开/关防火墙"
    echo "3) 开放端口"
    echo "4) 关闭端口"
    echo "5) 安装防火墙"
    echo "6) 卸载防火墙"
    echo "0) 退出"
    echo -n "请选择操作: "
    read -r CH </dev/tty
    case "$CH" in
      n|N) [ $page -lt $pages ] && page=$((page+1)) ;;
      b|B) [ $page -gt 1 ] && page=$((page-1)) ;;
      1) toggle_temp ;;
      2) toggle_perm ;;
      3) open_port ;;
      4) close_port ;;
      5) install_fw ;;
      6) uninstall_fw ;;
      0) exit 0 ;;
      *) ;;
    esac
  done
}

# ====== 各功能项 ======
toggle_temp() {
  read -rp "输入操作(open/o, close/c): " A </dev/tty
  A=$(echo "$A" | tr '[:upper:]' '[:lower:]')
  case "$A" in
    open|o) systemctl start firewalld && echo -e "${GREEN}已启动${RESET}" ;;
    close|c) systemctl stop firewalld && echo -e "${RED}已关闭${RESET}" ;;
  esac
}

toggle_perm() {
  read -rp "输入操作(enable/e, disable/d): " A </dev/tty
  A=$(echo "$A" | tr '[:upper:]' '[:lower:]')
  case "$A" in
    enable|e) systemctl enable --now firewalld && echo -e "${GREEN}已永久启用${RESET}" ;;
    disable|d) systemctl disable --now firewalld && echo -e "${RED}已永久禁用${RESET}" ;;
  esac
}

open_port() {
  read -rp "端口号: " P </dev/tty
  read -rp "协议(tcp/udp): " PRO </dev/tty
  firewall-cmd --permanent --add-port="$P/$PRO" && firewall-cmd --reload
}

close_port() {
  read -rp "端口号: " P </dev/tty
  read -rp "协议(tcp/udp): " PRO </dev/tty
  firewall-cmd --permanent --remove-port="$P/$PRO" && firewall-cmd --reload
}

install_fw() {
  if command -v yum >/dev/null 2>&1; then
    yum install -y firewalld
  elif command -v apt >/dev/null 2>&1; then
    apt update && apt install -y firewalld
  fi
}

uninstall_fw() {
  systemctl stop firewalld || true
  yum remove -y firewalld 2>/dev/null || apt remove -y firewalld 2>/dev/null || true
}

# ====== 启动 ======
detect_fw
show_menu
