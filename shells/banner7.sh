#!/usr/bin/env bash
# ========================================================
# Moreanp 彩色登录 Banner 安装脚本（兼容大多数 Linux）
# ========================================================

BANNER_PATH="/usr/local/bin/moreanp_banner.sh"

echo -e "\033[1;34m[ Moreanp Banner Installer ]\033[0m"

read -p "是否安装 Moreanp 专用 Banner？(y/N): " CONFIRM
CONFIRM=${CONFIRM:-n}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❎ 已取消安装。"
    exit 0
fi

# ========================================================
# 生成独立 Banner 脚本
# ========================================================
cat > "$BANNER_PATH" <<'EOF'
#!/usr/bin/env bash
# 清屏
clear

# 彩色
RED="\033[1;31m"
GRN="\033[1;32m"
YEL="\033[1;33m"
CYN="\033[1;36m"
RST="\033[0m"

# ---------------- 系统信息 ----------------
# CPU 使用率
CPU_IDLE=$(awk -v FS=" " '/^cpu / {print $5}' /proc/stat)
CPU_TOTAL=$(awk -v FS=" " '/^cpu / {sum=0; for(i=2;i<=5;i++) sum+=$i; print sum}' /proc/stat)
CPU_USAGE=$(awk -v total="$CPU_TOTAL" -v idle="$CPU_IDLE" 'BEGIN{printf "%.0f", (total-idle)/total*100}')
if [ "$CPU_USAGE" -gt 70 ]; then
    CPU_DISPLAY="${RED}${CPU_USAGE}%${RST}"
else
    CPU_DISPLAY="${GRN}${CPU_USAGE}%${RST}"
fi

# 内存已用/总量 GB
MEM_USED=$(free -b | awk '/Mem:/ {printf "%.1f", $3/1024/1024/1024}')
MEM_TOTAL=$(free -b | awk '/Mem:/ {printf "%.1f", $2/1024/1024/1024}')
MEM_DISPLAY="${MEM_USED}/${MEM_TOTAL}"

# 根目录磁盘已用/总量 GB
DISK_USED=$(df --block-size=1 / | awk 'NR==2{printf "%.1f", $3/1024/1024/1024}')
DISK_TOTAL=$(df --block-size=1 / | awk 'NR==2{printf "%.1f", $2/1024/1024/1024}')
DISK_DISPLAY="${DISK_USED}/${DISK_TOTAL}"

# 外网 IP
EXT_IP=$(curl -s --max-time 2 https://api.ipify.org || echo "N/A")

# ---------------- 彩色艺术字 ----------------
echo -e "[0;1;31;91m▄[0m    [0;1;36;96m▄[0m                                          "
echo -e "[0;1;33;93m█[0;1;32;92m█[0m  [0;1;36;96m█[0;1;34;94m█[0m  [0;1;35;95m▄[0;1;31;91m▄▄[0m    [0;1;36;96m▄[0m [0;1;34;94m▄▄[0m   [0;1;31;91m▄[0;1;33;93m▄▄[0m    [0;1;34;94m▄▄[0;1;35;95m▄[0m   [0;1;33;93m▄[0m [0;1;32;92m▄▄[0m   [0;1;34;94m▄[0;1;35;95m▄▄[0;1;31;91m▄[0m  "
echo -e "[0;1;32;92m█[0m [0;1;36;96m█[0;1;34;94m█[0m [0;1;35;95m█[0m [0;1;31;91m█▀[0m [0;1;33;93m▀[0;1;32;92m█[0m   [0;1;34;94m█▀[0m  [0;1;31;91m▀[0m [0;1;33;93m█▀[0m  [0;1;36;96m█[0m  [0;1;34;94m▀[0m   [0;1;31;91m█[0m  [0;1;32;92m█▀[0m  [0;1;34;94m█[0m  [0;1;35;95m█[0;1;31;91m▀[0m [0;1;33;93m▀█[0m "
echo -e "[0;1;36;96m█[0m [0;1;34;94m▀[0;1;35;95m▀[0m [0;1;31;91m█[0m [0;1;33;93m█[0m   [0;1;36;96m█[0m   [0;1;35;95m█[0m     [0;1;32;92m█▀[0;1;36;96m▀▀[0;1;34;94m▀[0m  [0;1;35;95m▄[0;1;31;91m▀▀[0;1;33;93m▀█[0m  [0;1;36;96m█[0m   [0;1;35;95m█[0m  [0;1;31;91m█[0m   [0;1;32;92m█[0m "
echo -e "[0;1;34;94m█[0m    [0;1;33;93m█[0m [0;1;32;92m▀█[0;1;36;96m▄█[0;1;34;94m▀[0m   [0;1;31;91m█[0m     [0;1;36;96m▀█[0;1;34;94m▄▄[0;1;35;95m▀[0m  [0;1;31;91m▀[0;1;33;93m▄▄[0;1;32;92m▀█[0m  [0;1;34;94m█[0m   [0;1;31;91m█[0m  [0;1;33;93m█[0;1;32;92m█▄[0;1;36;96m█▀[0m "
echo -e "                                           [0;1;32;92m█[0m     "
echo -e "                                           [0;1;36;96m▀[0m     "
echo
echo -e "                                  Powered by Moreanp     "
echo -e " -------------------------------------------------------"

# ---------------- 系统信息行 ----------------
printf " CPU:%-5s | MEM:%-9s | DISK:%-9s | IP:%s\n" "$CPU_DISPLAY" "$MEM_DISPLAY" "$DISK_DISPLAY" "$EXT_IP"
echo -e " -------------------------------------------------------"
EOF

chmod +x "$BANNER_PATH"

# ========================================================
# 注册登录自动执行
# ========================================================
if ! grep -q "moreanp_banner.sh" ~/.bashrc; then
    echo -e "\n# >>> Moreanp Banner <<<" >> ~/.bashrc
    echo "bash $BANNER_PATH" >> ~/.bashrc
    echo "# >>> End <<<" >> ~/.bashrc
fi

echo -e "\033[1;36m→ 安装完成！下次登录自动显示彩色 Banner\033[0m"
