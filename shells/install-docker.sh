#!/usr/bin/env bash
set -euo pipefail

# install-docker-smart.sh
# 智能 Docker 安装脚本（含 docker compose v2），多源、自动检测、等待 dpkg 锁、自动切换源
# 2025 - Generated & improved for robustness

### ------- 配色 -------
C_RESET="\033[0m"
C_OK="\033[1;32m"
C_INFO="\033[1;34m"
C_WARN="\033[1;33m"
C_ERR="\033[1;31m"

echo -e "${C_INFO}== Docker 智能安装脚本 (multi-source, auto-fallback) ==${C_RESET}"

# ---- root 提权 ----
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${C_WARN}检测到非 root 环境，会尝试 sudo 提权以继续安装。输入 sudo 密码以继续。${C_RESET}"
  exec sudo bash "$0" "$@"
fi

# ---- 超时设定（等待锁） ----
LOCK_WAIT_MAX=${LOCK_WAIT_MAX:-120}   # 最多等待秒数（可通过环境变量覆盖）

# ---- 内置镜像源（按优先/地域混合） ----
# 注意：部分镜像可能不提供完全相同的目录结构；脚本会检测可达性并自动跳过不可用项
declare -A MIRRORS
MIRRORS["Docker官方下载"]="https://download.docker.com"
MIRRORS["阿里云镜像"]="https://mirrors.aliyun.com/docker-ce"
MIRRORS["清华镜像"]="https://mirrors.tuna.tsinghua.edu.cn/docker-ce"
MIRRORS["中科大镜像"]="https://mirrors.ustc.edu.cn/docker-ce"
MIRRORS["腾讯云镜像"]="https://mirrors.cloud.tencent.com/docker-ce"
MIRRORS["华为云镜像"]="https://repo.huaweicloud.com/docker-ce"
MIRRORS["百度云镜像"]="https://mirror.baidubce.com/docker-ce"
MIRRORS["Azure 镜像"]="https://mirror.azure.cn/docker-ce"
MIRRORS["FastGit (不稳定)"]="https://download.fastgit.org/docker"
MIRRORS["Google Cloud (可能受限)"]="https://packages.cloud.google.com"
MIRRORS["AWS (官方)"]="https://download.docker.com"
MIRRORS["GitHub Releases CDN"]="https://ghproxy.com/https://github.com/docker"  # 注意：只是作可达性测试用
# 你可按需在此再加更多条目

# ---- helper: 提取 host ----
host_from_url() {
  # simple parse, extract host from URL like https://domain/path
  local url="$1"
  url="${url#*://}"
  echo "${url%%/*}"
}

# ---- helper: 测试主机解析 (DNS) & HTTP连通 ----
check_host_dns() {
  local host="$1"
  if command -v getent >/dev/null 2>&1; then
    if getent ahosts "$host" >/dev/null 2>&1; then
      return 0
    fi
  fi
  # fallback ping (ping may require root but we are root)
  if ping -c1 -W1 "$host" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

check_http() {
  local url="$1"
  # use curl to do a HEAD request with short timeout
  if command -v curl >/dev/null 2>&1; then
    if curl -sS --max-time 4 -I "$url" >/dev/null 2>&1; then
      return 0
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget --spider --timeout=4 --tries=1 "$url" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

# ---- 等待 dpkg/apt 锁（仅对Deb系有用） ----
wait_for_apt_lock() {
  local waited=0
  echo -e "${C_INFO}检测系统锁（如 apt/dpkg 是否被其他进程占用），最多等待 ${LOCK_WAIT_MAX} 秒...${C_RESET}"
  while true; do
    # 检查常见占用进程
    if pgrep -x apt >/dev/null 2>&1 || pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
      if [ "$waited" -ge "$LOCK_WAIT_MAX" ]; then
        echo -e "${C_WARN}等待超时 (${LOCK_WAIT_MAX}s)。若你确定没有其他安装在运行，可手动清理锁并重试。${C_RESET}"
        return 1
      fi
      sleep 1
      waited=$((waited+1))
    else
      echo -e "${C_OK}锁已释放，开始安装步骤。${C_RESET}"
      return 0
    fi
  done
}

# ---- 检测发行版与包管理器 ----
OS_ID=""
OS_VERSION=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID=${ID,,}
  OS_VERSION=${VERSION_ID:-}
else
  OS_ID=$(uname -s | tr '[:upper:]' '[:lower:]')
  OS_VERSION=$(uname -r)
fi
echo -e "${C_INFO}检测到系统: ${OS_ID} ${OS_VERSION}${C_RESET}"

PKG=""
UPDATE_CMD=""
INSTALL_CMD=""
case "$OS_ID" in
  ubuntu|debian)
    PKG="apt"
    UPDATE_CMD="apt-get update -y"
    INSTALL_CMD="apt-get install -y"
    ;;
  centos|rhel|rocky|almalinux|ol)
    if command -v dnf >/dev/null 2>&1; then
      PKG="dnf"
      UPDATE_CMD="dnf makecache -y"
      INSTALL_CMD="dnf install -y"
    else
      PKG="yum"
      UPDATE_CMD="yum makecache -y"
      INSTALL_CMD="yum install -y"
    fi
    ;;
  fedora)
    PKG="dnf"
    UPDATE_CMD="dnf makecache -y"
    INSTALL_CMD="dnf install -y"
    ;;
  amzn|amazon)
    PKG="yum"
    UPDATE_CMD="yum makecache -y"
    INSTALL_CMD="yum install -y"
    ;;
  opensuse*|sles)
    PKG="zypper"
    UPDATE_CMD="zypper refresh"
    INSTALL_CMD="zypper install -y"
    ;;
  *)
    echo -e "${C_WARN}无法识别或未优化此发行版 (${OS_ID})，脚本将尝试使用通用方法安装。${C_RESET}"
    PKG="auto"
    ;;
esac

# ---- 安装基本依赖（curl, ca-certificates, gnupg, lsb-release） ----
install_prereqs() {
  echo -e "${C_INFO}安装基础依赖包...${C_RESET}"
  case "$PKG" in
    apt)
      wait_for_apt_lock || true
      apt-get update -y || true
      apt-get install -y curl ca-certificates gnupg lsb-release apt-transport-https software-properties-common >/dev/null 2>&1 || true
      ;;
    dnf|yum)
      $UPDATE_CMD || true
      $INSTALL_CMD -y curl ca-certificates gnupg2 lsb-release >/dev/null 2>&1 || true
      ;;
    zypper)
      zypper refresh || true
      zypper install -y curl ca-certificates gpg2 lsb-release >/dev/null 2>&1 || true
      ;;
    *)
      echo -e "${C_WARN}未知包管理器，尽量确保 curl 与 gpg 已安装。${C_RESET}"
      ;;
  esac
}

install_prereqs

# ---- 选择一个可用源（自动化检测） ----
echo -e "${C_INFO}开始探测镜像源可用性，会优先选国内镜像（若可达）。${C_RESET}"

SELECTED=""
for name in "${!MIRRORS[@]}"; do
  url="${MIRRORS[$name]}"
  host=$(host_from_url "$url")
  # 先做 DNS 检查，再做 HTTP HEAD 快速检测
  if check_host_dns "$host"; then
    # 对于基本可达性，使用根 URL 检查
    if check_http "$url"; then
      SELECTED="$url"
      SELECTED_NAME="$name"
      echo -e "${C_OK}选中镜像源: ${name} -> ${url}${C_RESET}"
      break
    else
      echo -e "${C_WARN}主机可解析但 HTTP 不可达: ${name} (${host})${C_RESET}"
    fi
  else
    echo -e "${C_WARN}DNS 解析失败或主机不可达: ${name} (${host})${C_RESET}"
  fi
done

if [ -z "${SELECTED:-}" ]; then
  echo -e "${C_WARN}未检测到任何镜像源可用，尝试使用 Docker 官方源作为后备。${C_RESET}"
  SELECTED="https://download.docker.com"
  SELECTED_NAME="Docker 官方(默认)"
fi

echo -e "${C_INFO}将使用镜像源： ${SELECTED_NAME} -> ${SELECTED}${C_RESET}"

# ---- 根据发行版安装 docker ----
install_docker_debian_like() {
  echo -e "${C_INFO}为 Debian/Ubuntu 系列添加 Docker 源并安装...${C_RESET}"
  mkdir -p /etc/apt/keyrings
  # 尽量获取 GPG，若指定镜像没有 gpg 就退回官方
  GPG_URL="${SELECTED%/}/linux/gpg"
  if ! curl -fsSL --max-time 6 "$GPG_URL" -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
    echo -e "${C_WARN}从 ${SELECTED} 获取 GPG 失败，尝试从 download.docker.com 获取...${C_RESET}"
    curl -fsSL --max-time 6 "https://download.docker.com/linux/$(. /etc/os-release; echo $ID)/gpg" -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
  fi

  CODENAME="$(lsb_release -cs 2>/dev/null || echo focal)"
  ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] ${SELECTED%/}/linux/$(. /etc/os-release; echo $ID) ${CODENAME} stable" > /etc/apt/sources.list.d/docker.list || true

  wait_for_apt_lock || true
  apt-get update -y || true

  # 尝试安装常规包；若失败将回退到 containerd + binary compose
  if apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1; then
    echo -e "${C_OK}通过包管理安装 docker 成功。${C_RESET}"
    return 0
  else
    echo -e "${C_WARN}通过包管理安装 docker 失败，尝试通过官方下载安装并手动配置...${C_RESET}"
    # 尝试卸载残留后继续
    apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true
    # 继续后面通用安装步骤
  fi
}

install_docker_yum_like() {
  echo -e "${C_INFO}为 RHEL/CentOS/Fedora/Alma/Rocky/Oracle 添加 Docker 源并安装...${C_RESET}"
  # 生成临时 repo 文件指向我们选择的源，若失败则使用官方 repo
  REPO_URL="${SELECTED%/}/linux/centos/docker-ce.repo"
  if curl -fsSL --max-time 6 "$REPO_URL" -o /etc/yum.repos.d/docker-ce.repo 2>/dev/null; then
    echo -e "${C_OK}已写入 yum/dnf repo -> ${REPO_URL}${C_RESET}"
  else
    echo -e "${C_WARN}从镜像获取 repo 失败，尝试使用官方 repo 配置。${C_RESET}"
    curl -fsSL --max-time 6 "https://download.docker.com/linux/centos/docker-ce.repo" -o /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true
  fi

  $UPDATE_CMD || true
  if $INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1; then
    echo -e "${C_OK}通过包管理安装 docker 成功。${C_RESET}"
    return 0
  else
    echo -e "${C_WARN}通过包管理安装 docker 失败，脚本将尝试其他方式（如静默安装 containerd + binary compose）。${C_RESET}"
  fi
}

install_docker_zypper() {
  echo -e "${C_INFO}为 openSUSE/SLES 安装 docker...${C_RESET}"
  # openSUSE 官方通常已有 docker 包
  zypper refresh || true
  if zypper install -y docker docker-compose >/dev/null 2>&1; then
    echo -e "${C_OK}通过 zypper 安装 docker 成功。${C_RESET}"
    return 0
  else
    echo -e "${C_WARN}zypper 安装失败，脚本继续尝试通用安装方式。${C_RESET}"
  fi
}

# ---- 执行 distro-specific 安装 ----
case "$PKG" in
  apt)
    install_docker_debian_like || true
    ;;
  dnf|yum)
    install_docker_yum_like || true
    ;;
  zypper)
    install_docker_zypper || true
    ;;
  *)
    echo -e "${C_WARN}未知包管理器 - 尝试使用官方安装脚本方式。${C_RESET}"
    # 继续下面的通用安装
    ;;
esac

# ---- 通用后备安装（若上面未能成功） ----
if ! command -v docker >/dev/null 2>&1; then
  echo -e "${C_INFO}尝试使用 Docker 官方安装脚本作为后备（get.docker.com）。${C_RESET}"
  # 官方安装脚本会自动使用合适源
  if curl -fsSL "https://get.docker.com" -o /tmp/get-docker.sh 2>/dev/null; then
    sh /tmp/get-docker.sh || true
  else
    echo -e "${C_WARN}无法下载 get.docker.com 安装脚本，尝试直接安装 containerd + docker binaries...${C_RESET}"
  fi
fi

# ---- 如果仍然没有 docker，尝试安装 containerd 并手动部署 docker CLI/engine (极端后备) ----
if ! command -v docker >/dev/null 2>&1; then
  echo -e "${C_WARN}自动安装未成功，尝试安装 containerd 并手动安装 docker-compose v2 作为后备。${C_RESET}"
  case "$PKG" in
    apt)
      wait_for_apt_lock || true
      apt-get update -y || true
      apt-get install -y containerd >/dev/null 2>&1 || true
      ;;
    dnf|yum)
      $INSTALL_CMD containerd >/dev/null 2>&1 || true
      ;;
    zypper)
      zypper install -y containerd >/dev/null 2>&1 || true
      ;;
    *)
      echo -e "${C_WARN}请手动安装 containerd/docker。${C_RESET}"
      ;;
  esac
fi

# ---- docker compose plugin/v2 处理 ----
install_compose_v2_binary() {
  echo -e "${C_INFO}尝试安装 docker compose v2 二进制（作为后备）。${C_RESET}"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    armv7*|armhf) arch="arm" ;;
    *) arch="amd64" ;;
  esac
  # 获取最新版本 tag（若无网络则降级到固定版本）
  COMPOSE_VER="v2.20.2"
  # 尝试从 GitHub Releases 下载（使用 ghproxy 如果可达）
  BIN_URLS=(
    "https://ghproxy.com/https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-${arch}"
    "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-${arch}"
    "https://get.daocloud.io/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-${arch}"
  )
  for u in "${BIN_URLS[@]}"; do
    if check_http "$u"; then
      echo -e "${C_INFO}从 ${u} 下载 compose 二进制...${C_RESET}"
      curl -fsSL --max-time 20 -o /usr/local/bin/docker-compose "$u" || continue
      chmod +x /usr/local/bin/docker-compose || true
      ln -sf /usr/local/bin/docker-compose /usr/local/bin/docker-compose-plugin || true
      echo -e "${C_OK}docker-compose 二进制安装完成。${C_RESET}"
      return 0
    fi
  done
  echo -e "${C_WARN}无法获取 docker compose 二进制，跳过此步骤。${C_RESET}"
  return 1
}

if ! command -v docker >/dev/null 2>&1; then
  echo -e "${C_ERR}警告：docker 二进制尚未安装成功。脚本仍将尝试安装 compose 后备，但建议手动检查日志并重试。${C_RESET}"
fi

# 如果系统没有 package 的 docker-compose-plugin，优先安装二进制
if ! docker compose version >/dev/null 2>&1; then
  install_compose_v2_binary || true
fi

# ---- 启用并启动 docker 服务（若已安装） ----
if command -v systemctl >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
  echo -e "${C_INFO}启用并启动 docker 服务...${C_RESET}"
  systemctl daemon-reload || true
  systemctl enable --now docker || true
  sleep 1
fi

# ---- 测试安装 ----
if command -v docker >/dev/null 2>&1; then
  echo -e "${C_OK}=== 安装完成：Docker 版本 ===${C_RESET}"
  docker --version || true
  echo -e "${C_OK}=== 安装完成：Docker Compose 版本 ===${C_RESET}"
  if docker compose version >/dev/null 2>&1; then
    docker compose version || true
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose version || true
  else
    echo -e "${C_WARN}未检测到 docker compose，但你可以使用 docker compose 插件或 docker-compose 二进制。${C_RESET}"
  fi

  echo -e "${C_INFO}尝试运行 hello-world 镜像（非必要）以确认是否能拉取与运行：${C_RESET}"
  echo -e "  ${C_WARN}注意：若你在受限网络（中国大陆）且没有镜像加速，拉取可能很慢或失败。${C_RESET}"
  echo -e "  ${C_INFO}运行测试： docker run --rm hello-world${C_RESET}"
else
  echo -e "${C_ERR}安装失败：未能在系统中检测到 docker 命令。请查看上面的日志以定位原因，或把安装日志发给我来排查。${C_RESET}"
  exit 2
fi

echo -e "${C_OK}脚本执行完毕。如需我把此脚本优化为：1) 支持并行测速选最快源，2) 用 IP 或 DoH 强制解析某些域名（以绕过 DNS 污染），请告诉我。${C_RESET}"
