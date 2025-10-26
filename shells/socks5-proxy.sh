#!/bin/bash
# ==============================================
# SOCKS5 全局代理管理脚本
# 兼容大多数 Linux 发行版（Ubuntu / Debian / CentOS / Arch）
# by Aidan & GPT-5
# ==============================================

ENV_FILE="/etc/environment"
TMP_FILE="/tmp/proxy_env"

# 颜色定义
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

# 显示当前代理状态
show_status() {
    echo -e "\n${BLUE}当前代理状态：${NC}"
    echo "----------------------------------"
    echo "临时代理:"
    echo "  http_proxy=$http_proxy"
    echo "  https_proxy=$https_proxy"
    echo "  all_proxy=$all_proxy"
    echo
    echo "永久代理(来自 /etc/environment):"
    grep -E "http_proxy|https_proxy|all_proxy" "$ENV_FILE" 2>/dev/null || echo "  无"
    echo "----------------------------------"
}

# 设置临时代理
set_temp_proxy() {
    read -p "请输入 SOCKS5 代理 IP (例如 127.0.0.1): " ip
    read -p "请输入 SOCKS5 端口 (例如 1080): " port

    export http_proxy="socks5h://$ip:$port"
    export https_proxy="socks5h://$ip:$port"
    export all_proxy="socks5h://$ip:$port"

    echo "http_proxy=$http_proxy" > $TMP_FILE
    echo "https_proxy=$https_proxy" >> $TMP_FILE
    echo "all_proxy=$all_proxy" >> $TMP_FILE

    echo -e "${GREEN}✅ 临时代理已启用: socks5h://$ip:$port${NC}"
}

# 关闭临时代理
unset_temp_proxy() {
    unset http_proxy https_proxy all_proxy
    rm -f $TMP_FILE
    echo -e "${YELLOW}🟡 临时代理已关闭${NC}"
}

# 设置永久代理
set_perm_proxy() {
    read -p "请输入 SOCKS5 代理 IP (例如 127.0.0.1): " ip
    read -p "请输入 SOCKS5 端口 (例如 1080): " port

    sudo sed -i '/http_proxy\|https_proxy\|all_proxy/d' "$ENV_FILE"
    {
        echo "http_proxy=\"socks5h://$ip:$port\""
        echo "https_proxy=\"socks5h://$ip:$port\""
        echo "all_proxy=\"socks5h://$ip:$port\""
    } | sudo tee -a "$ENV_FILE" >/dev/null

    echo -e "${GREEN}✅ 永久代理已写入 /etc/environment${NC}"
    echo "请注销或重新登录后生效。"
}

# 关闭永久代理
unset_perm_proxy() {
    sudo sed -i '/http_proxy\|https_proxy\|all_proxy/d' "$ENV_FILE"
    echo -e "${YELLOW}🟡 永久代理已从 /etc/environment 移除${NC}"
}

# 菜单主界面
while true; do
    clear
    echo -e "${GREEN}╔════════════════════════════════════╗"
    echo -e "║       SOCKS5 全局代理管理器        ║"
    echo -e "╠════════════════════════════════════╣"
    echo -e "║ [1] 设置临时代理 (当前终端有效)    ║"
    echo -e "║ [2] 关闭临时代理                   ║"
    echo -e "║ [3] 设置永久代理 (全系统有效)      ║"
    echo -e "║ [4] 关闭永久代理                   ║"
    echo -e "║ [5] 查看当前代理状态               ║"
    echo -e "║ [0] 退出                           ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    read -p "请选择操作 [0-5]: " choice

    case "$choice" in
        1) set_temp_proxy ;;
        2) unset_temp_proxy ;;
        3) set_perm_proxy ;;
        4) unset_perm_proxy ;;
        5) show_status; read -p "按回车键继续..." ;;
        0) echo "退出..."; exit 0 ;;
        *) echo "无效选项，请重试。"; sleep 1 ;;
    esac
done
