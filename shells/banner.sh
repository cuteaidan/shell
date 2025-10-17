#!/bin/bash
# Moreanp 专用动态 Banner 安装脚本 v2
# 功能：保留原艺术字 + 动态系统信息 + 自动禁用 MOTD 与 SSH Banner

BANNER_FILE="/etc/banner"
PROFILE_FILE="/etc/profile"
SSH_CONFIGS=("/etc/ssh/sshd_config" "/etc/ssh/ssh_config")

read -p "是否安装 Moreanp 专用动态 Banner？(y/N): " CONFIRM
CONFIRM=${CONFIRM:-n}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "❎ 已取消安装。"
  exit 0
fi

# =========================================================
# 1) 创建 /etc/banner （保持上方艺术字原样，仅底部动态信息）
# =========================================================
cat > "$BANNER_FILE" <<'EOF'
#!/bin/bash
# 动态 Banner 内容生成器
clear

# 彩色定义
RED="\033[1;31m"
GRN="\033[1;32m"
YEL="\033[1;33m"
BLU="\033[1;34m"
CYN="\033[1;36m"
MAG="\033[1;35m"
RST="\033[0m"

# 获取系统信息
CPU_USAGE=$(top -bn1 | awk '/Cpu\(s\)/ {printf "%.1f%%", 100 - $8}')
MEM_USAGE=$(free -m | awk '/Mem:/ {printf "%.1f%%", $3/$2*100}')
DISK_USAGE=$(df -h / | awk 'NR==2{print $5}')
EXT_IP=$(curl -s --max-time 2 https://api.ipify.org || echo "N/A")

# 保留原艺术字
echo -e "[0;1;31;91m▄[0m    [0;1;36;96m▄[0m                                          "
echo -e "[0;1;33;93m█[0;1;32;92m█[0m  [0;1;36;96m█[0;1;34;94m█[0m  [0;1;35;95m▄[0;1;31;91m▄▄[0m    [0;1;36;96m▄[0m [0;1;34;94m▄▄[0m   [0;1;31;91m▄[0;1;33;93m▄▄[0m    [0;1;34;94m▄▄[0;1;35;95m▄[0m   [0;1;33;93m▄[0m [0;1;32;92m▄▄[0m   [0;1;34;94m▄[0;1;35;95m▄▄[0;1;31;91m▄[0m  "
echo -e "[0;1;32;92m█[0m [0;1;36;96m█[0;1;34;94m█[0m [0;1;35;95m█[0m [0;1;31;91m█▀[0m [0;1;33;93m▀[0;1;32;92m█[0m   [0;1;34;94m█▀[0m  [0;1;31;91m▀[0m [0;1;33;93m█▀[0m  [0;1;36;96m█[0m  [0;1;34;94m▀[0m   [0;1;31;91m█[0m  [0;1;32;92m█▀[0m  [0;1;34;94m█[0m  [0;1;35;95m█[0;1;31;91m▀[0m [0;1;33;93m▀█[0m "
echo -e "[0;1;36;96m█[0m [0;1;34;94m▀[0;1;35;95m▀[0m [0;1;31;91m█[0m [0;1;33;93m█[0m   [0;1;36;96m█[0m   [0;1;35;95m█[0m     [0;1;32;92m█▀[0;1;36;96m▀▀[0;1;34;94m▀[0m  [0;1;35;95m▄[0;1;31;91m▀▀[0;1;33;93m▀█[0m  [0;1;36;96m█[0m   [0;1;35;95m█[0m  [0;1;31;91m█[0m   [0;1;32;92m█[0m "
echo -e "[0;1;34;94m█[0m    [0;1;33;93m█[0m [0;1;32;92m▀█[0;1;36;96m▄█[0;1;34;94m▀[0m   [0;1;31;91m█[0m     [0;1;36;96m▀█[0;1;34;94m▄▄[0;1;35;95m▀[0m  [0;1;31;91m▀[0;1;33;93m▄▄[0;1;32;92m▀█[0m  [0;1;34;94m█[0m   [0;1;31;91m█[0m  [0;1;33;93m█[0;1;32;92m█▄[0;1;36;96m█▀[0m "
echo -e "                                           [0;1;32;92m█[0m     "
echo -e "                                           [0;1;36;96m▀[0m     "
echo -e "                                             "
echo -e "                                  Powered by Moreanp    "
echo -e " -------------------------------------------------------"

# 🌈 动态信息区（简洁一行）
printf " ${GRN}CPU${RST}:${YEL}%-7s${RST} | ${GRN}MEM${RST}:${YEL}%-7s${RST} | ${GRN}DISK${RST}:${YEL}%-6s${RST} | ${GRN}IP${RST}:${CYN}%s${RST}\n" "$CPU_USAGE" "$MEM_USAGE" "$DISK_USAGE" "$EXT_IP"

echo -e " -------------------------------------------------------"
EOF

chmod +x "$BANNER_FILE"

# =========================================================
# 2) 修改 /etc/profile 调用 Banner
# =========================================================
if ! grep -q '### SHOW /etc/banner ###' "$PROFILE_FILE" 2>/dev/null; then
cat >> "$PROFILE_FILE" <<'EOF'

### SHOW /etc/banner ###
# 登录时显示动态 Banner
if [ -n "$PS1" ]; then
    [ -x /etc/banner ] && /etc/banner
fi
### END SHOW /etc/banner ###

EOF
fi

# =========================================================
# 3) 禁用 MOTD + SSH Banner
# =========================================================
for f in /etc/pam.d/sshd /etc/pam.d/login; do
  [ -f "$f" ] && sed -i 's/^\(session\s\+optional\s\+pam_motd.so.*\)$/# \1/' "$f"
done

[ -d /etc/update-motd.d ] && chmod -x /etc/update-motd.d/* 2>/dev/null
[ -f /etc/motd ] && mv /etc/motd /etc/motd.disabled 2>/dev/null

for cfg in "${SSH_CONFIGS[@]}"; do
  if [ -f "$cfg" ]; then
    sed -i 's/^[# ]*Banner.*/# Banner none/' "$cfg"
    if ! grep -q '^# Banner none' "$cfg"; then
      echo "# Banner none" >> "$cfg"
    fi
  fi
done

# =========================================================
# 4) 完成提示
# =========================================================
echo "✅ Moreanp 动态 Banner 安装完成！"
echo "   - 保留原彩色艺术字"
echo "   - 动态展示 CPU/MEM/DISK/IP"
echo "   - 已禁用 MOTD 与 SSH Banner"
echo
echo "👉 可执行命令预览效果："
echo "   bash /etc/banner"
