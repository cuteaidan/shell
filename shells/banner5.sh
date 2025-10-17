#!/usr/bin/env bash
# ========================================================
# Moreanp 彩色登录 Banner 安装脚本（单次显示，兼容大多数 Linux）
# ========================================================

set -e

BANNER_PATH="/usr/local/bin/moreanp_banner.sh"

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
# Moreanp 彩色 Banner（单次显示，兼容大多数 Linux）

# 获取 CPU 使用率（从 /proc/stat）
if [ -r /proc/stat ]; then
  CPU=($(awk '/^cpu /{for(i=2;i<=5;i++) t+=$i; print $2,$3,$4,$5}' /proc/stat))
  TOTAL=$((CPU[0]+CPU[1]+CPU[2]+CPU[3]))
  IDLE=${CPU[3]}
  CPU_USAGE=$((100*(TOTAL-IDLE)/TOTAL))
  CPU_USAGE="${CPU_USAGE}%"
else
  CPU_USAGE="N/A"
fi

# 获取内存占用
MEM_USAGE=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%.1f%%", $3/$2*100}')
MEM_USAGE=${MEM_USAGE:-N/A}

# 根目录磁盘占用
DISK_USAGE=$(df -h / 2>/dev/null | awk 'NR==2{print $5}')
DISK_USAGE=${DISK_USAGE:-N/A}

# 外网 IP
EXT_IP=$(curl -s --max-time 2 https://api.ipify.org || echo "N/A")

# 彩色艺术字（保持原样）
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

# 显示系统信息
printf " CPU: %-7s | MEM: %-7s | DISK: %-6s | IP: %s\n" "$CPU_USAGE" "$MEM_USAGE" "$DISK_USAGE" "$EXT_IP"
echo -e " -------------------------------------------------------"
EOF

chmod +x "$BANNER_PATH"
echo -e "\033[1;32m✅ Banner 脚本已生成：$BANNER_PATH\033[0m"

# ========================================================
# 注册登录自动执行（保留 Last login）
# ========================================================
if ! grep -q "moreanp_banner.sh" ~/.bashrc; then
    echo -e "\n# >>> Moreanp Banner <<<" >> ~/.bashrc
    echo "bash $BANNER_PATH" >> ~/.bashrc
    echo "# >>> End <<<" >> ~/.bashrc
    echo -e "\033[1;32m✅ 已注册登录自动显示 Banner\033[0m"
else
    echo -e "\033[1;33m⚠️ 登录自动显示已存在，无需重复添加\033[0m"
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
echo -e "\033[1;35m(可立即测试：bash $BANNER_PATH)\033[0m"
