#!/bin/bash
# =========================================
# 自动生成重装命令的启动脚本
# 支持交互式选择系统、版本号及常用参数
# =========================================

# 可选操作系统列表（可扩展）
OS_LIST=(
"Alpine"
"Debian"
"Kali"
"Ubuntu"
"Anolis"
"RHEL/AlmaLinux/Rocky/Oracle"
"OpenCloudOS"
"CentOS Stream"
"Fedora"
"openEuler"
"openSUSE"
"NixOS"
"Arch"
"Gentoo"
"AOSC"
"fnOS"
"Windows (DD)"
"Windows (ISO)"
)

# 系统版本映射
declare -A OS_VERSIONS
OS_VERSIONS["Alpine"]="3.19 3.20 3.21 3.22"
OS_VERSIONS["Debian"]="9 10 11 12 13"
OS_VERSIONS["Kali"]="rolling"
OS_VERSIONS["Ubuntu"]="16.04 18.04 20.04 22.04 24.04 25.10"
OS_VERSIONS["Anolis"]="7 8 23"
OS_VERSIONS["RHEL/AlmaLinux/Rocky/Oracle"]="8 9 10"
OS_VERSIONS["OpenCloudOS"]="8 9 23"
OS_VERSIONS["CentOS Stream"]="9 10"
OS_VERSIONS["Fedora"]="41 42"
OS_VERSIONS["openEuler"]="20.03 22.03 24.03 25.09"
OS_VERSIONS["openSUSE"]="15.6 16.0 tumbleweed"
OS_VERSIONS["NixOS"]="25.05"
OS_VERSIONS["Arch"]="rolling"
OS_VERSIONS["Gentoo"]="rolling"
OS_VERSIONS["AOSC"]="rolling"
OS_VERSIONS["fnOS"]="public"
OS_VERSIONS["Windows (DD)"]="any"
OS_VERSIONS["Windows (ISO)"]="Vista 7 8.x 10 11 Server"

# ===========================
# 交互式选择系统
# ===========================
echo "请选择要安装的操作系统:"
for i in "${!OS_LIST[@]}"; do
    echo "$((i+1)). ${OS_LIST[i]}"
done
read -p "输入序号: " os_choice

if ! [[ "$os_choice" =~ ^[0-9]+$ ]] || [ "$os_choice" -lt 1 ] || [ "$os_choice" -gt "${#OS_LIST[@]}" ]; then
    echo "无效输入，退出"
    exit 1
fi

OS_NAME="${OS_LIST[$((os_choice-1))]}"
echo "已选择: $OS_NAME"

# ===========================
# 交互式选择版本号（如果有多个）
# ===========================
VERSIONS=${OS_VERSIONS[$OS_NAME]}
VERSION=""
if [ "$VERSIONS" != "public" ] && [ "$VERSIONS" != "any" ] && [ "$VERSIONS" != "rolling" ]; then
    VERSION_ARRAY=($VERSIONS)
    echo "请选择版本号:"
    for i in "${!VERSION_ARRAY[@]}"; do
        echo "$((i+1)). ${VERSION_ARRAY[i]}"
    done
    read -p "输入序号（回车选择最新）: " ver_choice
    if [[ "$ver_choice" =~ ^[0-9]+$ ]] && [ "$ver_choice" -ge 1 ] && [ "$ver_choice" -le "${#VERSION_ARRAY[@]}" ]; then
        VERSION="${VERSION_ARRAY[$((ver_choice-1))]}"
    else
        VERSION="${VERSION_ARRAY[-1]}"
    fi
    echo "已选择版本: $VERSION"
fi

# ===========================
# 用户输入可选参数
# ===========================
read -p "是否设置 root/administrator 密码? (y/n): " use_pass
PASS=""
if [[ "$use_pass" =~ ^[Yy]$ ]]; then
    read -s -p "请输入密码: " PASS
    echo
fi

read -p "是否修改 SSH 端口? (y/n): " use_ssh
SSH_PORT=""
if [[ "$use_ssh" =~ ^[Yy]$ ]]; then
    read -p "请输入 SSH 端口: " SSH_PORT
fi

read -p "是否修改 Web 端口? (y/n): " use_web
WEB_PORT=""
if [[ "$use_web" =~ ^[Yy]$ ]]; then
    read -p "请输入 Web 端口: " WEB_PORT
fi

# ===========================
# 构建最终命令
# ===========================
CMD="bash reinstall.sh"

# 系统与版本
if [ -n "$VERSION" ]; then
    CMD+=" ${OS_NAME,,} $VERSION"
else
    CMD+=" ${OS_NAME,,}"
fi

# 可选参数
[ -n "$PASS" ] && CMD+=" --password $PASS"
[ -n "$SSH_PORT" ] && CMD+=" --ssh-port $SSH_PORT"
[ -n "$WEB_PORT" ] && CMD+=" --web-port $WEB_PORT"

# ===========================
# 显示命令并提示执行
# ===========================
echo
echo "生成的安装命令如下:"
echo -e "\033[1;32m$CMD\033[0m"
read -p "是否执行该命令? (y/n): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    eval "$CMD"
else
    echo "操作已取消"
fi
