#!/usr/bin/env bash
# 一键安装 Moreanp 动态登录 Banner
# 功能：彩色艺术字 + 动态 CPU/MEM/DISK/IP + 自动注册到登录

set -e

BANNER_PATH="/usr/local/bin/moreanp_banner.sh"

echo -e "\033[1;34m[ Moreanp Banner Installer ]\033[0m"
read -p "是否安装 Moreanp 专用动态 Banner？(y/N): " CONFIRM
CONFIRM=${CONFIRM:-n}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❎ 已取消安装。"
    exit 0
fi

# =========================================================
# 1) 生成 banner 脚本
# =========================================================
cat > "$BANNER_PATH" <<'EOF'
#!/usr/bin/env bash
# Moreanp 动态 Banner
clear

# 彩色定义
RED="\033[1;31m"; GRN="\033[1;32m"; YEL="\033[1;33m"
BLU="\033[1;34m"; CYN="\033[1;36m"; MAG="\033[1;35m"; RST="\033[0m"

# 获取系统信息
CPU=$(top -bn1 | awk '/Cpu\(s\)/ {printf "%.1f%%", 100 - $8}')
MEM=$(free -m | awk '/Mem:/ {printf "%.1f%%", $3/$2*100}')
DISK=$(df -h / | awk 'NR==2{print $5}')
IP=$(curl -s --max-time 2 https://api.ipify.org || echo "N/A")

# 彩色艺术字（原样保留）
echo -e "${RED}▄${RST}    ${CYN}▄${RST}                                          "
echo -e "${YEL}█${GRN}█${RST}  ${CYN}█${BLU}█${RST}  ${MAG}▄${RED}▄▄${RST}    ${CYN}▄${RST} ${BLU}▄▄${RST}   ${RED}▄${YEL}▄▄${RST}    ${BLU}▄▄${MAG}▄${RST}   ${YEL}▄${GRN}▄▄${RST}   ${BLU}▄${MAG}▄▄${RED}▄${RST}  "
echo -e "${GRN}█${RST} ${CYN}█${BLU}█${RST} ${MAG}█${RST} ${RED}█▀${RST} ${YEL}▀${GRN}█${RST}   ${BLU}█▀${RST}  ${RED}▀${RST} ${YEL}█▀${RST}  ${CYN}█${RST}  ${BLU}▀${RST}   ${RED}█${RST}  ${GRN}█▀${RST}  ${BLU}█${RST}  ${MAG}█${RED}▀${RST} ${YEL}▀█${RST} "
echo -e "${CYN}█${RST} ${BLU}▀${MAG}▀${RST} ${RED}█${RST} ${YEL}█${RST}   ${CYN}█${RST}   ${MAG}█${RST}     ${GRN}█▀${CYN}▀▀${BLU}▀${RST}  ${MAG}▄${RED}▀▀${YEL}▀█${RST}  ${CYN}█${RST}   ${MAG}█${RST}  ${RED}█${RST}   ${GRN}█${RST} "
echo -e "${BLU}█${RST}    ${YEL}█${GRN}▀█${CYN}▄█${BLU}▀${RST}   ${RED}█${RST}     ${CYN}▀█${BLU}▄▄${MAG}▀${RST}  ${RED}▀${YEL}▄▄${GRN}▀█${RST}  ${BLU}█${RST}   ${RED}█${RST}  ${YEL}█${GRN}█▄${CYN}█▀${RST} "
echo -e "                                           ${GRN}█${RST}     "
echo -e "                                           ${CYN}▀${RST}     "
echo
echo -e "                                  Powered by Moreanp"
echo -e " -------------------------------------------------------"

# 动态信息（简洁一行）
printf " ${GRN}CPU${RST}:${YEL}%-7s${RST} | ${GRN}MEM${RST}:${YEL}%-7s${RST} | ${GRN}DISK${RST}:${YEL}%-6s${RST} | ${GRN}IP${RST}:${CYN}%s${RST}\n" "$CPU" "$MEM" "$DISK" "$IP"
echo -e " -------------------------------------------------------"
EOF

chmod +x "$BANNER_PATH"
echo -e "\033[1;32m✅ Banner 脚本已生成：$BANNER_PATH\033[0m"

# =========================================================
# 2) 注册登录自动执行
# =========================================================
if ! grep -q "moreanp_banner.sh" ~/.bashrc; then
    echo -e "\n# >>> Moreanp 动态 Banner <<<" >> ~/.bashrc
    echo "bash $BANNER_PATH" >> ~/.bashrc
    echo "# >>> End <<<" >> ~/.bashrc
    echo -e "\033[1;32m✅ 已注册登录自动显示 Banner\033[0m"
else
    echo -e "\033[1;33m⚠️ 登录自动显示已存在，无需重复添加\033[0m"
fi

# =========================================================
# 3) 禁用 MOTD 与 SSH Banner
# =========================================================
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

echo -e "\033[1;36m→ 安装完成！下次登录自动显示动态 Banner\033[0m"
echo -e "\033[1;35m(可立即测试：bash $BANNER_PATH)\033[0m"
