#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# ================= 配置 =================
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10
BOX_WIDTH=50
# ========================================

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
    echo "❌ 无法下载配置文件: $CONFIG_URL"
    exit 1
fi

mapfile -t ALL_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")
TOTAL=${#ALL_LINES[@]}
PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))

# ===== 色彩 =====
C_RESET="\033[0m"
C_BOX="\033[38;5;208m"   # 橙色边框
C_TITLE="\033[1;38;5;202m"
C_KEY="\033[1;32m"       # 绿色序号
C_NAME="\033[1;38;5;39m" # 蓝色脚本名
C_DIV="\033[38;5;240m"
C_HINT="\033[0;37m"
# ====================

# 计算可见长度（去掉 ANSI）
visible_len() {
    local str="$1"
    echo -n "$str" | sed 's/\x1B\[[0-9;]*[JKmsu]//g' | wc -c
}

# ===== 绘制 =====
draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_text() {
    local text="$1"
    local len=$(visible_len "$text")
    local pad=$((BOX_WIDTH - len - 3))
    ((pad<0)) && pad=0
    printf "%b║ %s%*s║%b\n" "$C_BOX" "$text" "$pad" "" "$C_RESET"
}

print_page() {
    local page="$1"
    local start=$(( (page-1)*PER_PAGE ))
    local end=$(( start + PER_PAGE -1 ))
    (( end >= TOTAL )) && end=$(( TOTAL-1 ))

    clear
    draw_line
    local title="${C_TITLE}脚本管理器 (by Moreanp)${C_RESET}"
    local pad=$(( (BOX_WIDTH - $(visible_len "$title") -2)/2 ))
    printf "%b║%*s%s%*s║%b\n" "$C_BOX" "$pad" "" "$title" "$((BOX_WIDTH - pad - $(visible_len "$title") -2))" "" "$C_RESET"
    draw_mid

    for slot in $(seq 0 $((PER_PAGE-1))); do
        idx=$(( start + slot ))
        if (( idx <= end )); then
            name="${ALL_LINES[idx]%%|*}"
            text="$(echo -e "${C_KEY}[$slot]${C_RESET} ${C_NAME}${name}${C_RESET}")"
            draw_text "$text"
        else
            draw_text ""
        fi
    done

    draw_mid
    draw_text "第 $page/$PAGES 页   共 $TOTAL 项"
    draw_text "[ n ] 下一页   [ b ] 上一页"
    draw_text "[ q ] 退出     [ 0-9 ] 选择"
    draw_bot
}

run_slot() {
    local page="$1" slot="$2"
    local start=$(( (page-1)*PER_PAGE ))
    local idx=$(( start + slot ))
    (( idx<0 || idx>=TOTAL )) && { echo "❌ 无效选项"; return; }

    selected="${ALL_LINES[idx]}"
    name="${selected%%|*}"
    rest="${selected#*|}"
    cmd="${rest%%|*}"
    args=""
    [[ "$rest" == *"|"* ]] && args="${rest#*|}"

    clear
    echo -e "${C_KEY}👉 正在执行：${C_NAME}${name}${C_RESET}"
    echo -e "${C_DIV}-----------------------------------------${C_RESET}"

    if [[ "$cmd" =~ ^CMD: ]]; then
        eval "${cmd#CMD:} ${args}"
    elif [[ "$cmd" =~ ^https?:// ]]; then
        bash <(curl -fsSL "${cmd}") ${args:+$args}
    else
        eval "$cmd ${args}"
    fi

    echo -e "${C_DIV}-----------------------------------------${C_RESET}"
    read -rp $'按回车返回菜单...' _
}

# ===== 主循环 =====
page=1
while true; do
    print_page "$page"
    read -rn1 -p "请选择 (0-9 / n / b / q): " key || true
    echo
    case "$key" in
        [0-9]) run_slot "$page" "$key" ;;
        n) ((page<PAGES)) && ((page++)) || echo "已是最后一页" ;;
        b) ((page>1)) && ((page--)) || echo "已是第一页" ;;
        q) clear; echo "👋 再见！"; exit 0 ;;
        *) ;;
    esac
done
