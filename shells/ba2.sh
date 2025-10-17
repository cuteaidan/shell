#!/bin/sh
# 安装登录后显示的彩色 Banner（仅显示 /etc/banner，禁用 MOTD）
BANNER_FILE="/etc/banner"
PROFILE_FILE="/etc/profile"

# 1) 如果 /etc/banner 不存在，创建文件（只写静态图案，不写动态信息）
if [ ! -f "$BANNER_FILE" ]; then
cat > "$BANNER_FILE" <<'EOF'
[0;1;31;91m▄[0m    [0;1;36;96m▄[0m                                          
[0;1;33;93m█[0;1;32;92m█[0m  [0;1;36;96m█[0;1;34;94m█[0m  [0;1;35;95m▄[0;1;31;91m▄▄[0m    [0;1;36;96m▄[0m [0;1;34;94m▄▄[0m   [0;1;31;91m▄[0;1;33;93m▄▄[0m    [0;1;34;94m▄▄[0;1;35;95m▄[0m   [0;1;33;93m▄[0m [0;1;32;92m▄▄[0m   [0;1;34;94m▄[0;1;35;95m▄▄[0;1;31;91m▄[0m  
[0;1;32;92m█[0m [0;1;36;96m█[0;1;34;94m█[0m [0;1;35;95m█[0m [0;1;31;91m█▀[0m [0;1;33;93m▀[0;1;32;92m█[0m   [0;1;34;94m█▀[0m  [0;1;31;91m▀[0m [0;1;33;93m█▀[0m  [0;1;36;96m█[0m  [0;1;34;94m▀[0m   [0;1;31;91m█[0m  [0;1;32;92m█▀[0m  [0;1;34;94m█[0m  [0;1;35;95m█[0;1;31;91m▀[0m [0;1;33;93m▀█[0m 
[0;1;36;96m█[0m [0;1;34;94m▀[0;1;35;95m▀[0m [0;1;31;91m█[0m [0;1;33;93m█[0m   [0;1;36;96m█[0m   [0;1;35;95m█[0m     [0;1;32;92m█▀[0;1;36;96m▀▀[0;1;34;94m▀[0m  [0;1;35;95m▄[0;1;31;91m▀▀[0;1;33;93m▀█[0m  [0;1;36;96m█[0m   [0;1;35;95m█[0m  [0;1;31;91m█[0m   [0;1;32;92m█[0m 
[0;1;34;94m█[0m    [0;1;33;93m█[0m [0;1;32;92m▀█[0;1;36;96m▄█[0;1;34;94m▀[0m   [0;1;31;91m█[0m     [0;1;36;96m▀█[0;1;34;94m▄▄[0;1;35;95m▀[0m  [0;1;31;91m▀[0;1;33;93m▄▄[0;1;32;92m▀█[0m  [0;1;34;94m█[0m   [0;1;31;91m█[0m  [0;1;33;93m█[0;1;32;92m█▄[0;1;36;96m█▀[0m 
                                           [0;1;32;92m█[0m     
                                           [0;1;36;96m▀[0m     
                                             
                                  Powered by Moreanp    
 -------------------------------------------------------
EOF
fi

# 2) 在 /etc/profile 添加调用逻辑（避免重复追加）
if ! grep -q '### SHOW /etc/banner ###' "$PROFILE_FILE" 2>/dev/null; then
cat >> "$PROFILE_FILE" <<'EOF'

### SHOW /etc/banner ###
# 仅交互式 shell 才显示
if [ -n "$PS1" ]; then
    # 显示静态 Banner 图案
    [ -f /etc/banner ] && cat /etc/banner

    # 动态信息：CPU、内存、硬盘占用、公网 IP（彩色显示）
    CPU_INFO=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^ //')
    MEM_INFO=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    DISK_INFO=$(df -h / | awk 'NR==2 {print $3 "/" $2}')
    PUB_IP=$(curl -s4 ifconfig.me || echo "N/A")

    echo -e " \033[1;33mCPU:\033[0m \033[1;36m$CPU_INFO\033[0m | \033[1;33mMEM:\033[0m \033[1;32m$MEM_INFO\033[0m | \033[1;33mDISK:\033[0m \033[1;34m$DISK_INFO\033[0m | \033[1;33mIP:\033[0m \033[1;35m$PUB_IP\033[0m"
    echo -e " \033[1;36m-------------------------------------------------------\033[0m"
fi
### END SHOW /etc/banner ###

EOF
fi

# 3) 禁用 MOTD（Ubuntu 特有）
# 注释 pam_motd 调用
if [ -f /etc/pam.d/sshd ]; then
    sed -i 's/^\(session\s\+optional\s\+pam_motd.so.*\)$/# \1/' /etc/pam.d/sshd
fi
if [ -f /etc/pam.d/login ]; then
    sed -i 's/^\(session\s\+optional\s\+pam_motd.so.*\)$/# \1/' /etc/pam.d/login
fi

# 禁用 update-motd.d 脚本执行权限
if [ -d /etc/update-motd.d ]; then
    chmod -x /etc/update-motd.d/*
fi

echo "✅彩色Banner已配置完成（每次登录动态显示系统信息，已屏蔽 Ubuntu MOTD）"
