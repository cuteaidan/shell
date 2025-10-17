echo "🔧 正在修复 SSH 服务..."

# 1️⃣ 备份旧配置（以防万一）
sudo mv /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s) 2>/dev/null || true

# 2️⃣ 写入一个全新的最简配置
sudo tee /etc/ssh/sshd_config >/dev/null <<'EOF'
Port 42222
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# 3️⃣ 确保运行目录存在
sudo mkdir -p /run/sshd
sudo chmod 755 /run/sshd

# 4️⃣ 重新生成 SSH 主机密钥
sudo ssh-keygen -A

# 5️⃣ 重启 SSH 服务
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart sshd || sudo systemctl restart ssh

# 6️⃣ 查看状态
echo
sudo systemctl status sshd --no-pager | head -n 15
echo
echo "✅ 检查监听端口："
ss -tunlp | grep ssh || echo "❌ SSH 仍未监听，请检查日志：journalctl -xeu ssh.service"
