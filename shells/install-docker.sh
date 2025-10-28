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

# ====== 网络检测 ======
echo -e "${C_INFO}检测网络环境中...${C_RESET}"
if curl -fsSL --connect-timeout 3 https://get.docker.com >/dev/null 2>&1; then
  NET_ENV="global"
  echo -e "${C_SUCCESS}✅ 可访问 Docker 官方网站，建议使用国外源${C_RESET}"
else
  NET_ENV="china"
  echo -e "${C_WARN}⚠️ 检测到访问官方源缓慢，建议使用国内镜像源${C_RESET}"
fi

# ====== 源选择菜单 ======
echo -e "\n${C_TITLE}请选择 Docker 安装源:${C_RESET}"
echo " 1) Docker 官方源 (get.docker.com)"
echo " 2) 阿里云源"
echo " 3) 腾讯云源"
echo " 4) 华为云源"
echo " 5) 清华大学源 (TUNA)"
echo " 6) DaoCloud 源"
echo " 7) 宝塔面板源"
echo " 8) 中科大源 (USTC)"
echo " 9) Docker 官方测试通道 (test.docker.com)"
echo "10) Azure 全球镜像"
echo
read -rp "请输入序号 [1-10]: " SRC_CHOICE

case $SRC_CHOICE in
  1) SRC_NAME="Docker 官方源"; INSTALL_MODE="official";;
  2) SRC_NAME="阿里云源"; INSTALL_MODE="aliyun";;
  3) SRC_NAME="腾讯云源"; INSTALL_MODE="tencent";;
  4) SRC_NAME="华为云源"; INSTALL_MODE="huawei";;
  5) SRC_NAME="清华大学源"; INSTALL_MODE="tuna";;
  6) SRC_NAME="DaoCloud 源"; INSTALL_MODE="daocloud";;
  7) SRC_NAME="宝塔面板源"; INSTALL_MODE="bt";;
  8) SRC_NAME="中科大源"; INSTALL_MODE="ustc";;
  9) SRC_NAME="Docker 官方测试通道"; INSTALL_MODE="test_official";;
  10) SRC_NAME="Azure 全球镜像"; INSTALL_MODE="azure_global";;
  *) echo -e "${C_WARN}输入无效，退出。${C_RESET}"; exit 1;;
esac

echo -e "${C_INFO}已选择安装源: ${SRC_NAME}${C_RESET}"
sleep 1

# ====== Docker 安装函数 ======
install_docker() {
  echo -e "\n${C_TITLE}开始安装 Docker...${C_RESET}"
  case $INSTALL_MODE in
    official)
      curl -fsSL https://get.docker.com | bash
      ;;
    aliyun)
      if [[ "$OS" =~ ^(centos|rhel|rocky|almalinux)$ ]]; then
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
    tencent)
      curl -fsSL https://mirrors.cloud.tencent.com/install-docker.sh | bash || curl -fsSL https://get.daocloud.io/docker | bash
      ;;
    huawei)
      curl -fsSL https://repo.huaweicloud.com/docker-ce/install.sh | bash || curl -fsSL https://get.daocloud.io/docker | bash
      ;;
    tuna)
      curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/install.sh | bash || curl -fsSL https://get.daocloud.io/docker | bash
      ;;
    daocloud)
      curl -fsSL https://get.daocloud.io/docker | sh
      ;;
    bt)
      curl -fsSL https://download.bt.cn/install/docker_install.sh | bash
      ;;
    ustc)
      curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/install.sh | bash || curl -fsSL https://get.daocloud.io/docker | bash
      ;;
    test_official)
      curl -fsSL https://test.docker.com | bash
      ;;
    azure_global)
      curl -fsSL https://mirror.azure.cn/docker-ce/install.sh | bash || curl -fsSL https://get.docker.com | bash
      ;;
  esac
}

install_docker

# ====== 启动并验证 ======
systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker || true

echo -e "\n${C_INFO}验证 Docker 是否安装成功...${C_RESET}"
if docker version >/dev/null 2>&1; then
  echo -e "${C_SUCCESS}✅ Docker 安装成功！${C_RESET}"
else
  echo -e "${C_WARN}❌ Docker 安装失败，请检查日志。${C_RESET}"
  exit 1
fi

# ====== 安装 Docker Compose ======
echo -e "\n${C_TITLE}安装 Docker Compose...${C_RESET}"
if ! command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
  curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  echo -e "${C_SUCCESS}Docker Compose 安装完成！${C_RESET}"
else
  echo -e "${C_INFO}Docker Compose 已存在，跳过安装。${C_RESET}"
fi

docker-compose version || true

echo -e "\n${C_SUCCESS}🎉 Docker 与 Compose 已安装完成！${C_RESET}"
