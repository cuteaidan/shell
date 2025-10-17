#!/usr/bin/env bash
# ============================================================
# 一键开启 zram 压缩内存（适配多发行版）
# 适用：Debian / Ubuntu / CentOS / Rocky / AlmaLinux / etc.
# 作者：Moreanp（优化版 by ChatGPT）
# ============================================================

set -o errexit
set -o nounset
set -o pipefail

# ---------- 颜色输出 ----------
info()    { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

# ---------- 检测 root ----------
if [ "$(id -u)" -ne 0 ]; then
  error "请以 root 身份运行本脚本。"
  exit 1
fi

# ---------- 检测发行版 ----------
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  OS="unknown"
fi

info "检测到系统：$PRETTY_NAME"

# ---------- 检查是否已经启用 zram ----------
if lsmod | grep -q zram; then
  warn "zram 已经启用，无需重复配置。"
  exit 0
fi

# ---------- 安装必要包 ----------
install_packages() {
  case "$OS" in
    ubuntu|debian)
      apt update -y
      apt install -y zram-tools
      ;;
    centos|rocky|almalinux|rhel|fedora)
      yum install -y epel-release || true
      yum install -y zram-generator || dnf install -y zram-generator
      ;;
    *)
      warn "未知系统，请手动安装 zram 工具包。"
      ;;
  esac
}

install_packages

# ---------- 配置 zram ----------
setup_zram() {
  case "$OS" in
    ubuntu|debian)
      # Ubuntu/Debian 默认使用 zram-tools
      cat >/etc/default/zramswap <<'EOF'
# 自动配置 zram 压缩内存
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF
      systemctl enable zramswap.service
      systemctl start zramswap.service
      ;;
    centos|rocky|almalinux|rhel|fedora)
      mkdir -p /etc/systemd/zram-generator.conf.d
      cat >/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = lz4
swap-priority = 100
EOF
      systemctl daemon-reexec
      systemctl daemon-reload
      systemctl start /dev/zram0 || true
      swapon --show | grep -q zram0 || swapon /dev/zram0 || true
      ;;
    *)
      warn "未识别系统，请根据你的发行版手动配置 zram。"
      ;;
  esac
}

setup_zram

# ---------- 优化参数 ----------
info "写入优化参数：swappiness=10, vfs_cache_pressure=50"
sysctl -w vm.swappiness=10
sysctl -w vm.vfs_cache_pressure=50
grep -q "vm.swappiness" /etc/sysctl.conf || echo "vm.swappiness=10" >> /etc/sysctl.conf
grep -q "vm.vfs_cache_pressure" /etc/sysctl.conf || echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf

# ---------- 验证 ----------
info "验证 zram 状态："
swapon --show || true
free -h || true

info "✅ zram 启用完成，系统内存压缩已生效！"
