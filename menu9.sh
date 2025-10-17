#!/usr/bin/env bash
# menu_manager_final.sh — 最终稳定版 (by Moreanp)
set -o errexit
set -o pipefail
set -o nounset

# ====== 全局配置 ======
PER_PAGE=10
C_RESET="\033[0m"
C_TITLE="\033[1;36m"
C_OPTION="\033[1;33m"
C_HINT="\033[1;32m"
C_PATH="\033[1;35m"

ROOT="ROOT"
CURRENT_PATH="$ROOT"
MENU_STACK=()
SEARCH_MODE=0
SEARCH_RETURN_PATH="$ROOT"
page=1

# ====== 示例菜单结构 ======
declare -A MENU_ITEMS=(
    ["ROOT"]="系统管理|面板安装|网络工具"
    ["系统管理"]="用户管理|磁盘工具|返回主菜单"
    ["面板安装"]="1Panel|宝塔|返回主菜单"
    ["网络工具"]="Ping工具|Curl测试|返回主菜单"
    ["系统管理/用户管理"]="添加用户|删除用户|返回上级"
    ["系统管理/磁盘工具"]="查看磁盘|清理缓存|返回上级"
)

# ====== 绘制菜单 ======
draw_menu() {
    clear
    echo -e "╔═══════════════════════════════════════╗"
    printf "║        脚本管理器 (by Moreanp)        ║\n"
    echo -e "╠═══════════════════════════════════════╣"
    local items="${MENU_ITEMS[$CURRENT_PATH]:-}"
    IFS='|' read -r -a options <<< "$items"

    local start=$(( (page - 1) * PER_PAGE ))
    local end=$(( start + PER_PAGE ))
    local total=${#options[@]}
    local page_total=$(( (total + PER_PAGE - 1) / PER_PAGE ))

    for ((i=start; i<end && i<total; i++)); do
        printf "║  [%d] %s%s\n" "$((i - start))" "${options[$i]}" "$(printf "%*s║" $((27 - ${#options[$i]})) "")"
    done
    echo -e "╠═══════════════════════════════════════╣"
    printf "║  路径：%b%s%b\n" "$C_PATH" "$CURRENT_PATH" "$C_RESET"
    echo -e "║        [ n ] 下页   [ b ] 上页        ║"
    echo -e "║        [ q ] 上级   [0-9] 选择        ║"
    echo -e "╚═══════════════════════════════════════╝"
}

# ====== 栈操作 ======
push_menu_stack() {
    MENU_STACK+=("$CURRENT_PATH")
}

pop_menu_stack() {
    if ((${#MENU_STACK[@]} == 0)); then
        CURRENT_PATH="$ROOT"
        page=1
        return 1
    fi
    local last_idx=$(( ${#MENU_STACK[@]} - 1 ))
    CURRENT_PATH="${MENU_STACK[$last_idx]}"
    unset "MENU_STACK[$last_idx]"
    page=1
    return 0
}

# ====== 搜索函数 ======
perform_search() {
    SEARCH_MODE=1
    SEARCH_RETURN_PATH="$CURRENT_PATH"
    read -e -p "$(printf "%b输入关键词进行搜索：%b" "$C_HINT" "$C_RESET")" keyword || true
    [[ -z "$keyword" ]] && return

    local results=()
    for key in "${!MENU_ITEMS[@]}"; do
        if [[ "$key" != *"返回"* && "$key" != "ROOT" ]]; then
            if [[ "$key" == *"$keyword"* ]]; then
                results+=("$key")
            else
                IFS='|' read -r -a opts <<< "${MENU_ITEMS[$key]}"
                for opt in "${opts[@]}"; do
                    [[ "$opt" == *"$keyword"* ]] && results+=("$key → $opt")
                done
            fi
        fi
    done

    if ((${#results[@]} == 0)); then
        echo -e "\n未找到匹配项，按回车返回主菜单。"
        read -r
        CURRENT_PATH="$ROOT"
        SEARCH_MODE=0
        return
    fi

    clear
    echo -e "╔═══════════════════════════════════════╗"
    echo -e "║          搜索结果 (${#results[@]}项)          ║"
    echo -e "╠═══════════════════════════════════════╣"
    for ((i=0; i<${#results[@]}; i++)); do
        printf "║  [%d] %s\n" "$i" "${results[$i]}"
    done
    echo -e "╠═══════════════════════════════════════╣"
    echo -e "║  [ q ] 返回主菜单                     ║"
    echo -e "╚═══════════════════════════════════════╝"

    read -e -p "$(printf "%b选项 (编号或 q 返回): %b" "$C_HINT" "$C_RESET")" _key || true
    [[ "${_key,,}" == "q" ]] && { SEARCH_MODE=0; CURRENT_PATH="$ROOT"; return; }

    if [[ "$_key" =~ ^[0-9]+$ && $_key -ge 0 && $_key -lt ${#results[@]} ]]; then
        echo -e "\n已选择：${results[$_key]}"
        read -r -p "按回车返回主菜单..." _
    fi

    SEARCH_MODE=0
    CURRENT_PATH="$ROOT"
}

# ====== 主循环 ======
main_loop() {
    while true; do
        draw_menu
        read -e -p "$(printf "%b选项 (0-9 or 输入关键字搜索): %b" "$C_HINT" "$C_RESET")" key || true
        case "$key" in
            n|N) ((page++)) ;;
            b|B) ((page>1)) && ((page--)) ;;
            q|Q)
                if (( SEARCH_MODE == 1 )); then
                    SEARCH_MODE=0
                    CURRENT_PATH="$ROOT"
                    MENU_STACK=()
                else
                    pop_menu_stack || true
                fi
                ;;
            [0-9])
                local items="${MENU_ITEMS[$CURRENT_PATH]:-}"
                IFS='|' read -r -a opts <<< "$items"
                local index=$((key + (page - 1) * PER_PAGE))
                if (( index < ${#opts[@]} )); then
                    local choice="${opts[$index]}"
                    case "$choice" in
                        返回主菜单) CURRENT_PATH="$ROOT"; MENU_STACK=(); page=1 ;;
                        返回上级) pop_menu_stack || true ;;
                        *)
                            if [[ -n "${MENU_ITEMS["$CURRENT_PATH/$choice"]+_}" ]]; then
                                push_menu_stack
                                CURRENT_PATH="$CURRENT_PATH/$choice"
                                page=1
                            else
                                clear
                                echo -e "你选择了：$choice"
                                read -r -p "按回车返回..." _
                            fi
                            ;;
                    esac
                fi
                ;;
            *)
                perform_search
                ;;
        esac
    done
}

# ====== 启动 ======
main_loop
