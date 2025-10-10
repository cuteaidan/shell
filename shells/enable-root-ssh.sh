#!/usr/bin/env bash
# enable-root-ssh.sh
# 用途：开启 root SSH 登录（修改 /etc/ssh/sshd_config），若 root 无密码则提示设置密码，最后重启/重新加载 sshd
# 注意：请以 root 或 sudo 运行

set -euo pipefail

SSHD_CONF="/etc/ssh/sshd_config"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/etc/ssh/backup-${TIMESTAMP}"
BACKUP_FILE="${BACKUP_DIR}/sshd_config.${TIMESTAMP}.bak"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请以 root 或 sudo 运行此脚本。"
    exit 1
  fi
}

confirm() {
  # 参数: 提示文本
  read -r -p "$1 [y/N]: " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

backup_config() {
  mkdir -p "$BACKUP_DIR"
  cp -a "$SSHD_CONF" "$BACKUP_FILE"
  echo "已备份 ${SSHD_CONF} 到 ${BACKUP_FILE}"
}

# set_or_replace <option> <value>
# 如果文件中存在该 option（可能被注释或未注释）则替换为指定值，否则追加到文件末尾
set_or_replace() {
  local opt="$1"
  local val="$2"
  local file="$SSHD_CONF"

  # 使用 perl 处理注释/重复键：保留首个非注释出现的键并替换它；注释或不存在的都处理
  if grep -Ei "^[[:space:]]*#?[[:space:]]*${opt}[[:space:]]+" "$file" >/dev/null 2>&1; then
    # 将首个出现的（无论是否注释）替换为非注释的设置
    perl -0777 -pe "s/^[[:space:]]*#?[[:space:]]*${opt}[[:space:]]+.*\$/\${opt} ${val}/im" -i "$file"
    # 上面替换可能没有把 ${opt} 展开在替换体内（perl -e 执行时），所以用 safe sed fallback:
    # Use awk: rewrite file with first occurrence replaced if perl didn't work exactly
    awk -v O="${opt}" -v V="${val}" '
      BEGIN{replaced=0}
      {
        line=$0
        if(!replaced){
          # match option possibly commented
          if(match(line, "^[[:space:]]*#?[[:space:]]*" O "[[:space:]]+")){
            print O " " V
            replaced=1
            next
          }
        }
        print line
      }
      END{
        if(!replaced){
          print O " " V
        }
      }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    # 不存在则追加
    echo "${opt} ${val}" >> "$file"
  fi
}

root_password_locked() {
  # 检查 /etc/shadow 的 root 字段是否有锁定标志 '!' 或 '*' 或为空
  if ! [ -r /etc/shadow ]; then
    # 不能读取 shadow 文件，返回未知（1）
    return 1
  fi
  local shadow_line
  shadow_line="$(awk -F: '$1=="root"{print $2; exit}' /etc/shadow || true)"
  if [ -z "$shadow_line" ]; then
    # 没有密码字段（不太可能）或为空，认为需要设置
    return 0
  fi
  case "$shadow_line" in
    '!'* | '*'* )
      # 被锁定或无密码
      return 0
      ;;
    *)
      # 有密码散列（非锁定）
      return 1
      ;;
  esac
}

restart_sshd() {
  if command -v systemctl >/dev/null 2>&1; then
    # 若有 systemd
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl list-unit-files | grep -E '^sshd\.service' >/dev/null 2>&1; then
      systemctl restart sshd
      systemctl status sshd --no-pager
      return 0
    fi
    # 某些系统服务名为 ssh
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl list-unit-files | grep -E '^ssh\.service' >/dev/null 2>&1; then
      systemctl restart ssh
      systemctl status ssh --no-pager
      return 0
    fi
  fi

  # fallback to service command
  if command -v service >/dev/null 2>&1; then
    if service sshd status >/dev/null 2>&1; then
      service sshd restart || true
      service sshd status || true
      return 0
    fi
    if service ssh status >/dev/null 2>&1; then
      service ssh restart || true
      service ssh status || true
      return 0
    fi
  fi

  echo "警告：未检测到 systemd 或 service 对应的 ssh/sshd 服务管理器，请手动重启 sshd。"
  return 1
}

main() {
  require_root

  echo "本脚本将："
  echo "  1) 备份 ${SSHD_CONF}"
  echo "  2) 设置 PermitRootLogin yes"
  echo "  3) 设置 PasswordAuthentication yes（如果你想只允许密钥登录，请不要运行此脚本或修改为 no）"
  echo "  4) 如果 root 没有密码（被锁定），会提示你设置一个 root 密码"
  echo

  if ! confirm "确认要继续并修改 SSH 配置以允许 root 密码登录吗？(风险：此操作会允许使用 root 密码远程登录，若在公网请谨慎)"; then
    echo "已取消。"
    exit 0
  fi

  if [ ! -f "$SSHD_CONF" ]; then
    echo "错误：找不到 ${SSHD_CONF}。你的系统可能使用不同路径，请检查。"
    exit 1
  fi

  backup_config

  echo "修改配置：设置 PermitRootLogin yes"
  # 首先移除可能存在的重复注释行，确保最终文件中有明确设置
  # 采用更简单、可控的方法：使用 awk 将首个匹配行替换或在末尾追加
  # 为避免复杂 perl/sed 兼容性问题，直接调用 set_or_replace
  set_or_replace "PermitRootLogin" "yes"
  set_or_replace "PasswordAuthentication" "yes"
  # 为安全考虑，禁止空密码登录
  set_or_replace "PermitEmptyPasswords" "no"

  echo "配置文件已修改（备份见 ${BACKUP_FILE}）。"

  # 如果 root 帐号被锁定或无密码，提示设置
  if root_password_locked; then
    echo
    echo "检测到 root 帐号可能未设置密码或被锁定。"
    echo "你需要为 root 设置一个密码才能通过密码登录（如果你想用密钥认证，可忽略此步骤）。"
    if confirm "现在为 root 设置密码？(将运行 passwd root)"; then
      echo "正在调用 passwd 设置 root 密码，请按提示输入并确认新密码..."
      passwd root
      echo "root 密码已更新（请确保使用强密码）。"
    else
      echo "跳过设置 root 密码：如果 root 没有密码/被锁定，root 密码登录仍将不可用。"
    fi
  else
    echo "检测到 root 已有密码（或无 /etc/shadow 可读）。"
  fi

  echo
  echo "正在重启或重新加载 sshd 服务..."
  if restart_sshd; then
    echo "sshd 已重启/重新加载（若命令返回错误请手动检查）。"
  else
    echo "请手动重启你的 sshd 服务，例如：systemctl restart sshd 或 service sshd restart"
  fi

  echo
  echo "说明："
  echo " - 备份文件：${BACKUP_FILE}"
  echo " - 若你想改回更安全的设置，推荐使用："
  echo "     PermitRootLogin prohibit-password"
  echo "     PasswordAuthentication no"
  echo "   并使用公私钥认证登录（推荐）。"
  echo
  echo "完成。"
}

main "$@"
