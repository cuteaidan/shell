#!/usr/bin/env bash
set -euo pipefail

# ===========================
#   Docker 一键安装脚本
#   支持全Linux发行版 & 多源自动选择
#   作者: GPT-5 改进版 (2025)
# ===========================

# ---- 颜色定义 ----
C_RESET="\033[0m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_BLUE="\033[1;34m"

# ---- 提权 ----
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${C_YELLOW}当前不是root用户，是否提权安装？ (Y/n): ${C_RESET}"
  read -r ans
  [[ "${ans,,}" != "n" ]] && exec sudo -i bash "$0" || exit 1
fi

# ---- 检测系统 ----
get_os_info() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=${ID,,}
    OS_VERSION=${VERSION_ID:-unknown}
  elif command -v lsb_release >/dev/null 2>&1; then
    OS_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    OS_VERSION=$(lsb_release -sr)
  else
    OS_ID=$(uname -s | tr '[:upper:]' '[:lower:]')
    OS_VERSION=$(uname -r)
  fi
  echo -e "${C_GREEN}检测到系统: ${OS_ID} ${OS_VERSION}${C_RESET}"
}
get_os_info

# ---- 包管理器 ----
if command -v apt >/dev/null 2>&1; then
  PKG_INSTALL="apt-get install -y"
  UPDATE_CMD="apt-get update -y"
elif command -v dnf >/dev/null 2>&1; then
  PKG_INSTALL="dnf install -y"
  UPDATE_CMD="dnf makecache -y"
elif command -v yum >/dev/null 2>&1; then
  PKG_INSTALL="yum install -y"
  UPDATE_CMD="yum makecache -y"
elif command -v zypper >/dev/null 2>&1; then
  PKG_INSTALL="zypper install -y"
  UPDATE_CMD="zypper refresh"
else
  echo -e "${C_RED}未检测到兼容的包管理器，无法自动安装。${C_RESET}"
  exit 1
fi

# ---- 多源列表 ----
declare -A SOURCES=(
  ["Docker官方"]="https://download.docker.com"
  ["中国官方镜像站(阿里云)"]="https://mirrors.aliyun.com/docker-ce"
  ["清华大学镜像"]="https://mirrors.tuna.tsinghua.edu.cn/docker-ce"
  ["中科大镜像"]="https://mirrors.ustc.edu.cn/docker-ce"
  ["腾讯云镜像"]="https://mirrors.cloud.tencent.com/docker-ce"
  ["华为云镜像"]="https://repo.huaweicloud.com/docker-ce"
  ["百度云镜像"]="https://mirror.baidubce.com/docker-ce"
  ["Azure美国西部镜像"]="https://mirror.azure.cn/docker-ce"
  ["AWS美国东部镜像"]="https://download.docker.com"
  ["GitHub镜像（fastgit）"]="https://download.fastgit.org/docker"
  ["Google Cloud US镜像"]="https://packages.cloud.google.com"
)

echo -e "${C_BLUE}请选择Docker安装源:${C_RESET}"
i=1
for name in "${!SOURCES[@]}"; do
  echo "  [$i] $name"
  ((i++))
done
echo "  [0] 自动选择最快源"

read -p "请输入序号 [0]: " choice
choice=${choice:-0}

if [[ "$choice" -eq 0 ]]; then
  # 默认优先顺序
  for key in \
    "阿里云" "腾讯云" "清华" "华为" "Docker官方" \
    "中科大" "AWS" "Azure" "百度" "Google"; do
    for name in "${!SOURCES[@]}"; do
      if [[ "$name" == *"$key"* ]]; then
        URL="${SOURCES[$name]}"
        if curl -s --head --max-time 2 "$URL" >/dev/null; then
          SELECTED_SOURCE="$URL"
          echo -e "${C_GREEN}自动选择源: $name ($URL)${C_RESET}"
          break 2
        fi
      fi
    done
  done
else
  key=$(printf "%s\n" "${!SOURCES[@]}" | sed -n "${choice}p")
  SELECTED_SOURCE="${SOURCES[$key]}"
  echo -e "${C_GREEN}手动选择源: $key ($SELECTED_SOURCE)${C_RESET}"
fi

# ---- 安装依赖 ----
echo -e "${C_BLUE}正在安装依赖包...${C_RESET}"
$UPDATE_CMD
$PKG_INSTALL curl ca-certificates gnupg lsb-release >/dev/null 2>&1 || true

# ---- 添加源并安装 ----
case "$OS_ID" in
  ubuntu|debian)
    mkdir -p /etc/apt/keyrings
    curl -fsSL "$SELECTED_SOURCE/linux/$OS_ID/gpg" -o /etc/apt/keyrings/docker.gpg || true
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $SELECTED_SOURCE/linux/$OS_ID \
      $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    ;;
  centos|rhel|rocky|almalinux|ol|fedora|amazon)
    yum-config-manager --add-repo "$SELECTED_SOURCE/linux/centos/docker-ce.repo" || true
    $PKG_INSTALL docker-ce docker-ce-cli containerd.io docker-compose-plugin
    ;;
  opensuse*|sles)
    zypper addrepo "$SELECTED_SOURCE/linux/sles/docker-ce.repo" docker-ce
    zypper install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    ;;
  *)
    echo -e "${C_RED}暂不支持自动识别的系统，请手动安装 Docker。${C_RESET}"
    exit 1
    ;;
esac

# ---- 启动与测试 ----
systemctl enable docker
systemctl start docker
docker --version
docker compose version || docker-compose version

echo -e "${C_GREEN}✅ Docker 已安装完成！${C_RESET}"
echo -e "${C_YELLOW}您可以使用以下命令测试运行:${C_RESET}"
echo -e "  ${C_BLUE}docker run hello-world${C_RESET}"
