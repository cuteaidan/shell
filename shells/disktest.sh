#!/bin/bash
# 磁盘寿命健康度读写性能测试工具
# 适配：Armbian / FnOS / OpenWrt (ARM64)
# aminsire@qq.com

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 标记文件路径
INSTALL_FLAG="/etc/.smartctl_installed_by_script"
SELECTED_DISK=""

# 检查权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}${BOLD}错误:${NC} 请使用 sudo 或 root 运行此脚本。"
  exit 1
fi

# ----------------- 依赖管理 -----------------
check_and_install_deps() {
    if ! command -v smartctl &> /dev/null; then
        echo -e "${YELLOW}检测到缺少关键依赖: ${CYAN}smartmontools${NC}"
        read -p "是否由本脚本代为安装? (y/n): " confirm
        if [[ "$confirm" == [yY] ]]; then
            echo -e "${BLUE}正在尝试安装...${NC}"
            if command -v apt-get &> /dev/null; then
                apt-get update && apt-get install -y smartmontools && touch "$INSTALL_FLAG"
            elif command -v yum &> /dev/null; then
                yum install -y smartmontools && touch "$INSTALL_FLAG"
            elif command -v opkg &> /dev/null; then
                opkg update && opkg install smartmontools && touch "$INSTALL_FLAG"
            fi
        fi
    fi
}

uninstall_deps() {
    if [ ! -f "$INSTALL_FLAG" ]; then
        echo -e "${RED}拒绝操作：smartmontools 不是由本脚本安装的。${NC}"
        return
    fi
    read -p "确认卸载 smartmontools? (y/n): " confirm
    if [[ "$confirm" == [yY] ]]; then
        apt-get remove -y smartmontools && rm -f "$INSTALL_FLAG"
        echo -e "${GREEN}卸载完成。${NC}"
    fi
}

# ----------------- 进度条绘制 -----------------
draw_progress() {
    local percent=$1
    local label=$2
    ((percent > 100)) && percent=100
    ((percent < 0)) && percent=0

    local filled=$((percent / 10))
    local empty=$((10 - filled))
    local color=$GREEN
    ((percent >= 70)) && color=$YELLOW
    ((percent >= 90)) && color=$RED

    local bar=$(printf "%${filled}s" | tr ' ' '#')$(printf "%${empty}s" | tr ' ' '-')
    printf "${BOLD}%-15s${NC}: ${color}[%s] %d%%${NC}\n" "$label" "$bar" "$percent"
}

# ----------------- 健康度解析 -----------------
check_health() {
    [ -z "$SELECTED_DISK" ] && { echo -e "${RED}请先选择磁盘！${NC}"; return; }
    
    local total_size=$(lsblk -d -n -o SIZE "$SELECTED_DISK")
    echo -e "\n${BLUE}${BOLD}┏━━━━ 磁盘详细健康档案 ━━━━┓${NC}"
    echo -e "  设备路径: ${YELLOW}$SELECTED_DISK${NC}"
    echo -e "  总 容 量: ${CYAN}$total_size${NC}"
    echo -e "------------------------------------------"

    if [[ "$SELECTED_DISK" == *"/mmcblk"* ]]; then
        # eMMC 逻辑：修正路径匹配，排除 SD 卡混淆
        local dev_name=$(basename "$SELECTED_DISK")
        local sys_path="/sys/block/$dev_name/device"
        if [ -f "$sys_path/life_time" ]; then
            local lifetime=$(cat "$sys_path/life_time")
            local val_a=$(( $(echo $lifetime | awk '{print $1}') ))
            local val_b=$(( $(echo $lifetime | awk '{print $2}') ))
            echo -e "  磁盘类型: ${CYAN}eMMC 存储 (内置)${NC}"
            draw_progress "$((val_a * 10))" "SLC 区域损耗"
            draw_progress "$((val_b * 10))" "MLC 区域损耗"
            local max_val=$(( val_a > val_b ? val_a : val_b ))
            echo -e "  ${BOLD}估算剩余寿命: ${GREEN}$((100 - max_val * 10))%${NC}"
        else
            echo -e "  ${RED}无法获取 eMMC 寿命数据${NC}"
        fi
    else
        # SATA/NVMe 逻辑
        if ! command -v smartctl &> /dev/null; then
            echo -e "${RED}请安装 smartmontools 后查看${NC}"; return
        fi
        local raw_smart=$(smartctl -a "$SELECTED_DISK" 2>/dev/null)
        local hours=$(echo "$raw_smart" | grep -i "Power_On_Hours" | awk '{print $NF}' | tr -d ',')
        # 兼容 NVMe 的 Percentage Used 和 SATA 的 Wear Leveling
        local wear_out=$(echo "$raw_smart" | grep -i "Percentage Used" | awk '{print $NF}' | tr -d '%')
        [ -z "$wear_out" ] && wear_out=$(echo "$raw_smart" | grep -i "Wear_Leveling_Count" | awk '{print $4}')
        
        echo -e "  磁盘类型: ${CYAN}外置磁盘/SSD${NC}"
        echo -e "  通电时间: ${YELLOW}${hours:-未知} 小y时${NC}"
        
        if [[ "$wear_out" =~ ^[0-9]+$ ]]; then
            draw_progress "$wear_out" "寿命已用"
            echo -e "  ${BOLD}剩余健康度: ${GREEN}$((100 - wear_out))%${NC}"
        else
            echo -e "  ${YELLOW}该设备不支持读取剩余寿命百分比${NC}"
        fi
    fi
    echo -e "${BLUE}${BOLD}┗━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

# ----------------- 测速功能 -----------------
test_speed() {
    [ -z "$SELECTED_DISK" ] && return
    # 核心修正：寻找该磁盘下的挂载点，如果没有挂载，则无法进行文件级测试
    local mnt_point=$(lsblk -n -o MOUNTPOINT "$SELECTED_DISK" | grep -v "^$" | head -n 1)
    
    if [ -z "$mnt_point" ]; then
        echo -e "${RED}错误: 该磁盘未挂载，无法测试读写性能。请先挂载分区。${NC}"
        return
    fi

    echo -e "\n${PURPLE}--- 性能测试 (写入目标: $mnt_point) ---${NC}"
    local test_file="$mnt_point/test_speed_tmp.img"
    
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    echo -n "同步写入速度: "
    # 使用 100MB 进行测试，增加 oflag=dsync 确保真实性
    dd if=/dev/zero of="$test_file" bs=1M count=100 oflag=dsync 2>&1 | awk '/copied/ {print $(NF-1), $NF}'
    
    echo -n "同步读取速度: "
    dd if="$test_file" of=/dev/null bs=1M count=100 2>&1 | awk '/copied/ {print $(NF-1), $NF}'
    
    rm -f "$test_file"
}

# ----------------- 主程序入口 -----------------
check_and_install_deps

while true; do
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}磁盘管理专家${NC} (当前: ${YELLOW}${SELECTED_DISK:-未选择}${NC})"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}1.${NC} 选择磁盘"
    echo -e "  ${BLUE}2.${NC} 查看寿命与健康度"
    echo -e "  ${BLUE}3.${NC} 读写性能测试"
    [ -f "$INSTALL_FLAG" ] && echo -e "  ${BLUE}4.${NC} ${RED}卸载安装的依赖${NC}"
    echo -e "  ${RED}q.${NC} 退出脚本"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "请输入选项: " opt
    
    case $opt in
        1) 
            echo -e "\n系统磁盘列表:"
            lsblk -d -n -o NAME,SIZE,MODEL | awk '{print NR") /dev/"$1 " ["$2"] " $3}'
            read -p "请选择编号: " choice
            line=$(lsblk -d -n -o NAME | sed -n "${choice}p")
            if [ -n "$line" ]; then
                SELECTED_DISK="/dev/$line"
                echo -e "${GREEN}已选择: $SELECTED_DISK${NC}"
            else
                echo -e "${RED}无效选择${NC}"
            fi
            ;;
        2) check_health ;;
        3) test_speed ;;
        4) [ -f "$INSTALL_FLAG" ] && uninstall_deps ;;
        q|Q) echo "退出中..."; exit 0 ;;
        *) echo "无效输入" ;;
    esac
done
