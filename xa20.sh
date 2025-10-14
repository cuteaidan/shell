#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权（兼容 bash <(curl …) / curl | bash / 本地文件） ======
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[1;33m⚠️ 检测到当前用户不是 root。\033[0m"
    if ! command -v sudo >/dev/null 2>&1; then
        echo -e "\033[1;31m❌ 系统未安装 sudo，请使用 root 用户运行本脚本。\033[0m"
        exit 1
    fi
    echo -e "\033[1;32m🔑 请输入当前用户的密码以获取管理员权限（sudo）...\033[0m"
    # 判断当前脚本是否为普通文件
    if [ -f "$0" ] && [ -r "$0" ]; then
        # 直接重启脚本
        exec sudo -E bash "$0" "$@"
        exit $?
    fi
    # 若为 /dev/fd 或 STDIN，则复制内容到临时文件
    TMP_SCRIPT="$(mktemp /tmp/menu_manager.XXXXXX.sh)"
    if [ -e "$0" ]; then
        if ! cat "$0" > "$TMP_SCRIPT" 2>/dev/null; then
            cat > "$TMP_SCRIPT"
        fi
    else
        cat > "$TMP_SCRIPT"
    fi
    chmod +x "$TMP_SCRIPT"
    echo -e "\033[1;34mℹ️ 已将脚本内容写入临时文件：$TMP_SCRIPT\033[0m"
    echo -e "\033[1;34m➡️ 正在以 root 权限重新运行...\033[0m"
    # 以 root 重新运行，并在执行完后自动删除自身
    exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
    exit $?
fi

# ====== 提权检测结束 ======

# ====== 配置部分 ======
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/script2.conf"
PER_PAGE=10
BOX_WIDTH=50
LEFT_INDENT=" "
TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
    echo "❌ 无法下载配置文件: $CONFIG_URL"
    exit 1
fi

# ====== 数据结构定义 ======
declare -a MENU_ITEMS
declare -a MENU_NAMES
declare -a MENU_COMMANDS
declare -a MENU_PARENTS
declare -a MENU_LEVELS
declare -a MENU_IS_PAGE

# ====== 解析配置文件 ======
parse_config() {
    local line_count=0
    local current_parent=-1
    local level_stack=()
    local parent_stack=()
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # 计算缩进级别（连续的|数量）
        local indent_level=0
        local temp_line="$line"
        while [[ "$temp_line" =~ ^\| ]]; do
            ((indent_level++))
            temp_line="${temp_line:1}"
        fi
        
        # 解析字段
        IFS='|' read -ra fields <<< "$temp_line"
        local name="${fields[0]}"
        local command="${fields[1]}"
        
        # 清理字段中的空格
        name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        command=$(echo "$command" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 确定是否为页面节点
        local is_page=0
        if [[ "$command" == "page" ]]; then
            is_page=1
            command=""
        fi
        
        # 处理层级关系
        while [[ ${#level_stack[@]} -gt 0 ]] && [[ ${level_stack[-1]} -ge $indent_level ]]; do
            unset 'level_stack[${#level_stack[@]}-1]'
            unset 'parent_stack[${#parent_stack[@]}-1]'
        done
        
        if [[ ${#level_stack[@]} -eq 0 ]]; then
            current_parent=-1
        else
            current_parent=${parent_stack[-1]}
        fi
        
        # 添加到数组
        MENU_ITEMS[$line_count]="$line_count"
        MENU_NAMES[$line_count]="$name"
        MENU_COMMANDS[$line_count]="$command"
        MENU_PARENTS[$line_count]=$current_parent
        MENU_LEVELS[$line_count]=$indent_level
        MENU_IS_PAGE[$line_count]=$is_page
        
        # 如果是页面节点，压入栈
        if [[ $is_page -eq 1 ]]; then
            level_stack+=($indent_level)
            parent_stack+=($line_count)
        fi
        
        ((line_count++))
    done < "$TMP_CONF"
}

# 解析配置
parse_config
TOTAL=${#MENU_ITEMS[@]}

# ====== 导航栈 ======
declare -a NAV_STACK=(-1)
CURRENT_PAGE=-1

# ====== 色彩定义 ======
C_RESET="\033[0m"
C_BOX="\033[1;38;5;202m"
C_TITLE="\033[1;38;5;220m"
C_KEY="\033[1;32m"
C_NAME="\033[1;38;5;39m"
C_HINT="\033[1;32m"
C_DIV="\033[38;5;240m"
C_SEARCH="\033[1;35m"

# ====== 宽度计算（支持全角字符） ======
str_width() {
    local text="$1"
    text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
    local len=0 i ch code
    for ((i=0;i<${#text};i++)); do
        ch="${text:i:1}"
        code=$(printf '%d' "'$ch" 2>/dev/null || true)
        if (( (code>=19968 && code<=40959) || (code>=65281 && code<=65519) || (code>=12288 && code<=12351) || (code>=12352 && code<=12543) )); then
            len=$((len+2))
        else
            len=$((len+1))
        fi
    done
    echo "$len"
}

# ====== 绘制边框函数 ======
draw_line() {
    printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET";
}
draw_mid() {
    printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET";
}
draw_bot() {
    printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET";
}
draw_text() {
    local text="$1"
    local width
    width=$(str_width "$text")
    local padding=$((BOX_WIDTH - width - ${#LEFT_INDENT} - 2))
    ((padding<0)) && padding=0
    printf "%b║%s%b%*s%b║%b\n" "$C_BOX" "$LEFT_INDENT" "$text" "$padding" "" "$C_BOX" "$C_RESET"
}
draw_title() {
    local title="$1"
    local width
    width=$(str_width "$title")
    local left_pad=$(( (BOX_WIDTH - width - 2)/2 ))
    local right_pad=$((BOX_WIDTH - width - left_pad - 2))
    [ $left_pad -lt 0 ] && left_pad=0
    [ $right_pad -lt 0 ] && right_pad=0
    printf "%b║%*s%b%s%b%*s%b║%b\n" "$C_BOX" "$left_pad" "" "$C_TITLE" "$title" "$C_RESET" "$right_pad" "" "$C_BOX" "$C_RESET"
}

# ====== 获取当前页面项 ======
get_current_items() {
    local -n result=$1
    result=()
    local parent=${NAV_STACK[-1]}
    
    for i in "${!MENU_ITEMS[@]}"; do
        if [[ ${MENU_PARENTS[$i]} -eq $parent ]]; then
            result+=("$i")
        fi
    done
}

# ====== 全局搜索功能 ======
search_items() {
    local -n result=$1
    local keyword="$2"
    result=()
    
    for i in "${!MENU_ITEMS[@]}"; do
        # 只搜索叶子节点（有命令且不是页面）
        if [[ -n "${MENU_COMMANDS[$i]}" ]] && [[ ${MENU_IS_PAGE[$i]} -eq 0 ]]; then
            local name_lower
            name_lower=$(echo "${MENU_NAMES[$i]}" | tr '[:upper:]' '[:lower:]')
            local keyword_lower
            keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$name_lower" == *"$keyword_lower"* ]]; then
                result+=("$i")
            fi
        fi
    done
}

# ====== 绘制菜单页 ======
print_page() {
    local page="$1"
    local search_mode="${2:-0}"
    local search_keyword="${3:-}"
    
    local current_items=()
    if [[ $search_mode -eq 1 ]]; then
        current_items=("${SEARCH_RESULTS[@]}")
    else
        get_current_items current_items
    fi
    
    local total_items=${#current_items[@]}
    local pages=$(( (total_items + PER_PAGE - 1) / PER_PAGE ))
    local start=$(( (page-1)*PER_PAGE ))
    local end=$(( start+PER_PAGE-1 ))
    ((end>=total_items)) && end=$((total_items-1))
    
    clear
    
    # 标题
    draw_line
    if [[ $search_mode -eq 1 ]]; then
        draw_title "搜索: $search_keyword (共 $total_items 项)"
    else
        draw_title "脚本管理器 (by Moreanp)"
    fi
    draw_mid
    
    # 菜单项
    for slot in $(seq 0 $((PER_PAGE-1))); do
        local display_idx=$((start+slot))
        if ((display_idx < total_items)); then
            local item_idx=${current_items[$display_idx]}
            local name="${MENU_NAMES[$item_idx]}"
            if [[ ${MENU_IS_PAGE[$item_idx]} -eq 1 ]]; then
                draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${name}${C_RESET} ${C_DIV}➔${C_RESET}"
            else
                draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${name}${C_RESET}"
            fi
        else
            draw_text ""
        fi
    done
    
    draw_mid
    
    # 页面信息和操作提示
    if [[ $search_mode -eq 1 ]]; then
        draw_text "第 $page/$pages 页 共 $total_items 项"
        draw_text "[ n ] 下一页 [ b ] 上一页 [ p ] 返回首页"
        draw_text "[ q ] 退出 [ 0-9 ] 选择"
    else
        draw_text "第 $page/$pages 页 共 $total_items 项"
        if [[ ${#NAV_STACK[@]} -gt 1 ]]; then
            draw_text "[ n ] 下一页 [ b ] 上一页 [ p ] 向上翻页"
        else
            draw_text "[ n ] 下一页 [ b ] 上一页"
        fi
        draw_text "[ s ] 搜索 [ q ] 退出 [ 0-9 ] 选择"
    fi
    
    draw_bot
}

# ====== 执行选项 ======
run_slot() {
    local page="$1"
    local slot="$2"
    local search_mode="${3:-0}"
    
    local current_items=()
    if [[ $search_mode -eq 1 ]]; then
        current_items=("${SEARCH_RESULTS[@]}")
    else
        get_current_items current_items
    fi
    
    local total_items=${#current_items[@]}
    local start=$(( (page-1)*PER_PAGE ))
    local idx=$((start+slot))
    
    if (( idx<0 || idx>=total_items )); then
        echo "❌ 无效选项"
        read -rp "按回车返回..." _
        return
    fi
    
    local item_idx=${current_items[$idx]}
    local name="${MENU_NAMES[$item_idx]}"
    local command="${MENU_COMMANDS[$item_idx]}"
    
    # 如果是页面节点，进入子菜单
    if [[ ${MENU_IS_PAGE[$item_idx]} -eq 1 ]]; then
        NAV_STACK+=("$item_idx")
        return
    fi
    
    # 执行命令
    clear
    echo -e "${C_KEY}👉 正在执行：${C_NAME}${name}${C_RESET}"
    echo -e "${C_DIV}-----------------------------------------${C_RESET}"
    
    if [[ "$command" =~ ^CMD: ]]; then
        eval "${command#CMD:}"
    elif [[ "$command" =~ ^https?:// ]]; then
        bash <(curl -fsSL "${command}")
    else
        eval "$command"
    fi
    
    echo -e "${C_DIV}-----------------------------------------${C_RESET}"
    read -rp $'按回车返回...' _
}

# ====== 搜索模式处理 ======
handle_search() {
    local search_page=1
    local search_keyword=""
    
    clear
    echo -e "${C_SEARCH}🔍 请输入搜索关键词:${C_RESET} "
    read -r search_keyword
    
    if [[ -z "$search_keyword" ]]; then
        echo "❌ 搜索关键词不能为空"
        read -rp "按回车返回..." _
        return
    fi
    
    search_items SEARCH_RESULTS "$search_keyword"
    local total_search=${#SEARCH_RESULTS[@]}
    
    if [[ $total_search -eq 0 ]]; then
        echo "❌ 未找到匹配项"
        read -rp "按回车返回..." _
        return
    fi
    
    while true; do
        print_page "$search_page" 1 "$search_keyword"
        printf "%b请输入选项 (0-9 / n / b / p / q): %b" "$C_HINT" "$C_RESET"
        read -r key || true
        
        case "$key" in
            [0-9])
                run_slot "$search_page" "$key" 1
                ;;
            n|N)
                local search_pages=$(( (total_search + PER_PAGE - 1) / PER_PAGE ))
                ((search_page < search_pages)) && ((search_page++)) || {
                    echo "已是最后一页"; read -rp "按回车返回..." _;
                }
                ;;
            b|B)
                ((search_page > 1)) && ((search_page--)) || {
                    echo "已是第一页"; read -rp "按回车返回..." _;
                }
                ;;
            p|P)
                # 返回首页
                return
                ;;
            q|Q)
                clear; echo "👋 再见！"; exit 0
                ;;
            *)
                echo "⚠️ 无效输入，请重试"; sleep 0.6
                ;;
        esac
    done
}

# ====== 主循环 ======
page=1
while true; do
    print_page "$page"
    printf "%b请输入选项 (0-9 / n / b / p / s / q): %b" "$C_HINT" "$C_RESET"
    read -r key || true
    
    case "$key" in
        [0-9])
            run_slot "$page" "$key"
            page=1  # 重置页码
            ;;
        n|N)
            local current_items=()
            get_current_items current_items
            local total_items=${#current_items[@]}
            local pages=$(( (total_items + PER_PAGE - 1) / PER_PAGE ))
            ((page < pages)) && ((page++)) || {
                echo "已是最后一页"; read -rp "按回车返回..." _;
            }
            ;;
        b|B)
            ((page > 1)) && ((page--)) || {
                echo "已是第一页"; read -rp "按回车返回..." _;
            }
            ;;
        p|P)
            # 向上翻页（返回上级菜单）
            if [[ ${#NAV_STACK[@]} -gt 1 ]]; then
                unset 'NAV_STACK[${#NAV_STACK[@]}-1]'
                page=1
            else
                echo "已在根目录"; read -rp "按回车返回..." _;
            fi
            ;;
        s|S)
            handle_search
            page=1
            ;;
        q|Q)
            clear; echo "👋 再见！"; exit 0
            ;;
        *)
            echo "⚠️ 无效输入，请重试"; sleep 0.6
            ;;
    esac
done
