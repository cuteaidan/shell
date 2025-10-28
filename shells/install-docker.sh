#!/usr/bin/env bash
set -euo pipefail

# ====== 颜色定义 ======
C_RESET="\033[0m"
C_TITLE="\033[1;33m"
C_SUCCESS="\033[1;32m"
C_WARN="\033[1;31m"
C_INFO="\033[1;36m"

# ====== 提权检测 ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${C_WARN}! 当前用户不是 root${C_RESET}"
  read -rp "是否提权执行？(Y/n): " ans
  if [[ "${ans:-Y}" =~ ^[Yy]$ ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "$0" "$@"
    else
      echo -e "${C_WARN}未安装sudo，请切换root后重试。${C_RESET}"
      exit 1
    fi
  else
    echo "取消执行。"
    exit 0
  fi
fi

# ====== 系统检测 ======
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
  elif [ -f /etc/centos-release ]; then
    OS="centos"
    VER=$(grep -oE "[0-9]+" /etc/centos-release | head -1)
  else
    OS=$(uname -s)
    VER=$(uname -r)
  fi
}

detect_os
echo -e "${C_INFO}检测到系统: ${OS} ${VER}${C_RESET}"

# ====== 安装源选择 ======
echo -e "${C_TITLE}\n请选择Docker安装源:${C_RESET}"
echo "1) Docker 官方源 (get.docker.com)"
echo "2) 阿里云源"
echo "3) 宝塔面板源"
echo "4) DaoCloud 国内加速源"
read -rp "请输入序号 [1-4]: " SRC_CHOICE

case $SRC_CHOICE in
  1)
    INSTALL_URL="https://get.docker.com"
    DESC="Docker 官方源"
    ;;
  2)
    INSTALL_URL="https://mirrors.aliyun.com/docker-ce/linux"
    DESC="阿里云源"
    ;;
  3)
    INSTALL_URL="https://download.bt.cn/install/docker_install.sh"
    DESC="宝塔面板源"
    ;;
  4)
    INSTALL_URL="https://get.daocloud.io/docker"
    DESC="DaoCloud 国内源"
    ;;
  *)
    echo -e "${C_WARN}输入无效，退出。${C_RESET}"
    exit 1
    ;;
esac

echo -e "${C_INFO}选择安装源: ${DESC}${C_RESET}"
sleep 1

# ====== 根据安装源执行安装 ======
install_docker() {
  echo -e "${C_TITLE}开始安装 Docker...${C_RESET}"
  case $SRC_CHOICE in
    1)
      curl -fsSL https://get.docker.com | bash
      ;;
    2)
      if [[ "$OS" =~ ^(centos|rhel|rocky|almalinux)$ ]]; then
        yum remove -y docker docker-common docker-selinux docker-engine || true
        yum install -y yum-utils
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
      elif [[ "$OS" =~ ^(ubuntu|debian)$ ]]; then
        apt-get update
        apt-get install -y ca-certificates curl gnupg lsb-release
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/$OS \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
      fi
      ;;
    3)
      curl -fsSL https://download.bt.cn/install/docker_install.sh | bash
      ;;
    4)
      curl -fsSL https://get.daocloud.io/docker | sh
      ;;
  esac
}

install_docker

# ====== 启动与验证 ======
systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker || true

echo -e "${C_INFO}验证 Docker 是否安装成功...${C_RESET}"
docker version && echo -e "${C_SUCCESS}✅ Docker 安装成功！${C_RESET}" || echo -e "${C_WARN}❌ Docker 安装失败！${C_RESET}"

# ====== 安装 Docker Compose ======
echo -e "${C_TITLE}正在安装 Docker Compose...${C_RESET}"
if ! command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
  curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  echo -e "${C_SUCCESS}Docker Compose 安装完成！${C_RESET}"
else
  echo -e "${C_INFO}Docker Compose 已存在，跳过安装。${C_RESET}"
fi

docker-compose version || true

echo -e "${C_SUCCESS}\n🎉 Docker 与 Compose 安装完成！${C_RESET}"
