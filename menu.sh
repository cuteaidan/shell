# ====== 下载配置（新增备用源机制） ======
download_conf() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$TMP_CONF"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_CONF" "$url"
  else
    echo "X 系统未安装 curl 或 wget"
    exit 1
  fi
}

echo -e "\033[1;34m⏳ 正在加载远程配置...\033[0m"
if ! download_conf "$CONFIG_URL"; then
  echo -e "\033[1;33m! 主源下载失败，尝试备用源...\033[0m"
  if ! download_conf "$BACKUP_URL"; then
    echo -e "\033[1;31mX 无法下载配置文件，请检查网络连接。\033[0m"
    exit 1
  fi
fi
