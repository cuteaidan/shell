#!/usr/bin/env bash
# ========================================================
# Moreanp 彩色登录 Banner 安装脚本（兼容大多数 Linux）
# ========================================================

set -e

BANNER_PATH="/usr/local/bin/moreanp_banner.sh"

# 安装确认
echo -e "\033[1;34m[ Moreanp Banner Installer ]\033[0m"
read -p "是否安装 Moreanp 专用 Banner？(y/N): " CONFIRM
CONFIRM=${CONFIRM:-n}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❎ 已取消安装。"
    exit 0
fi

# ========================================================
# 生成 banner 脚本
# ========================================================
cat > "$BANNER_PATH" <<'EOF'
#!/usr/bin/env bash

# 彩色定义
RED="\033[1;31m"
GRN="\033[1;32m"
YEL="\033[1;33m"
CYN="\033[1;36m"
RST="\033[0m"

# CPU 使用率计算
if [ -r /proc/stat ]; then
    CPU=($(awk '/^cpu /{for(i=2;i<=5;i++) t+=$i; print $2,$3,$4,$5}' /proc/stat))
    TOTAL=$((CPU[0]+CPU[1]+CPU[2]+CPU[3]))
    IDLE=${CPU[3]}
    CPU_NUM=$((100*(TOTAL-IDLE)/TOTAL))
    if [ "$CPU_NUM" -gt 70 ]; then
        CPU_USAGE="${RED}${CPU_NUM}%${RST}"
    else
        CPU_USAGE="${GRN}${CPU_NUM}%${RST}"
    fi
else
    CPU_USAGE="N/A"
fi

# 内存已用/总量
MEM=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%d/%d", $3,$2}')
MEM=${MEM:-N/A}

# 根目录磁盘已用/总量
DISK=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,""); printf "%d/%d",$3,$2}')
DISK=${DISK:-N/A}

# 外网 IP
EXT_IP=$(curl -s --max-time 2 https://api.ipify.org || echo "N/A")

# ================== 保留艺术字 ==================
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

# ================== 系统信息行 ==================
printf " CPU:%-5s | MEM:%-7s | DISK:%-7s | IP:%s\n" "$CPU_USAGE" "$MEM" "$DISK" "$EXT_IP"
echo -e " -------------------------------------------------------"
EOF

chmod +x "$BANNER_PATH"

# ========================================================
# 注册登录自动执行（保留 Last login）
# ========================================================
if ! grep -q "moreanp_banner.sh" ~/.bashrc; then
    echo -e "\n# >>> Moreanp Banner <<<" >> ~/.bashrc
    echo "bash $BANNER_PATH" >> ~/.bashrc
    echo "# >>> End <<<" >> ~/.bashrc
fi

# ========================================================
# 禁用 MOTD 与 SSH Banner
# ========================================================
for f in /etc/pam.d/sshd /etc/pam.d/login; do
  [ -f "$f" ] && sudo sed -i 's/^\(session\s\+optional\s\+pam_motd.so.*\)$/# \1/' "$f"
done
[ -d /etc/update-motd.d ] && sudo chmod -x /etc/update-motd.d/* 2>/dev/null
[ -f /etc/motd ] && sudo mv /etc/motd /etc/motd.disabled 2>/dev/null

for cfg in /etc/ssh/sshd_config /etc/ssh/ssh_config; do
  if [ -f "$cfg" ]; then
    sudo sed -i 's/^[# ]*Banner.*/# Banner none/' "$cfg"
    if ! grep -q '^# Banner none' "$cfg"; then
      echo "# Banner none" | sudo tee -a "$cfg" >/dev/null
    fi
  fi
done

echo -e "\033[1;36m→ 安装完成！下次登录自动显示彩色 Banner\033[0m"
