#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# ====== 自动提权（兼容 bash <(curl …) / curl | bash / 本地文件） ======
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;33m⚠️  检测到当前用户不是 root。\033[0m"
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[1;31m❌ 系统未安装 sudo，请使用 root 用户运行本脚本。\033[0m"
    exit 1
  fi
  echo -e "\033[1;32m🔑  请输入当前用户的密码以获取管理员权限（sudo）...\033[0m"

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

  echo -e "\033[1;34mℹ️  已将脚本内容写入临时文件：$TMP_SCRIPT\033[0m"
  echo -e "\033[1;34m➡️  正在以 root 权限重新运行...\033[0m"

  # 以 root 重新运行，并在执行完后自动删除自身
  exec sudo -E bash -c "trap 'rm -f \"$TMP_SCRIPT\"' EXIT; bash \"$TMP_SCRIPT\" \"$@\""
  exit $?
fi
# ====== 提权检测结束 ======

# ====== 配置部分 ======
CONFIG_URL="https://raw.githubusercontent.com/cuteaidan/shell/refs/heads/main/scripts.conf"
PER_PAGE=10
BOX_WIDTH=50
LEFT_INDENT="        "

TMP_CONF="$(mktemp -t menu_conf.XXXXXX)"
trap 'rm -f "$TMP_CONF"' EXIT

if ! curl -fsSL "$CONFIG_URL" -o "$TMP_CONF"; then
  echo "❌ 无法下载配置文件: $CONFIG_URL"
  exit 1
fi

mapfile -t ALL_LINES < <(grep -vE '^\s*#|^\s*$' "$TMP_CONF")
TOTAL=${#ALL_LINES[@]}
PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))

# ====== 色彩定义 ======
C_RESET="\033[0m"
C_BOX="\033[1;38;5;202m"
C_TITLE="\033[1;38;5;220m"
C_KEY="\033[1;32m"
C_NAME="\033[1;38;5;39m"
C_HINT="\033[1;32m"
C_DIV="\033[38;5;240m"

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
draw_line() { printf "%b╔%s╗%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_mid()  { printf "%b╠%s╣%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }
draw_bot()  { printf "%b╚%s╝%b\n" "$C_BOX" "$(printf '═%.0s' $(seq 1 $((BOX_WIDTH-2))))" "$C_RESET"; }

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

# ====== ======
# 解析配置，构建树结构（minimal intrusive changes）
# 解释：配置行形式是用单竖线分隔字段，而用多个连续竖线表示层级（例如：A||B|cmd）
# 处理方法：把行按 '|' 切分，最后一个字段为命令，其前面的非空字段则是路径层级。
# ======

declare -A CMD_MAP        # key: path_key::name  -> command (可能包含 args)
declare -A IS_PARENT      # key: path_key -> 1 表示有子项
declare -A CHILDREN      # key: path_key -> 子项名称的字符串以 \x1f (unit separator) 分隔（保持顺序）
SEP=$'\x1f'              # 用不可见字符做分隔，避免和名字冲突

# helper: join array by '::' to form path key
_join_path() {
  local -n _arr=$1
  local res=""
  for part in "${_arr[@]}"; do
    if [ -z "$res" ]; then res="$part"; else res="$res::$part"; fi
  done
  echo "$res"
}

# parse each config line
for line in "${ALL_LINES[@]}"; do
  # split by '|' preserving empty fields
  IFS='|' read -r -a parts <<< "$line"
  parts_len=${#parts[@]}
  if (( parts_len < 2 )); then
    # 非法行，跳过
    continue
  fi
  # last field is command (可能包含管道或空格)
  cmd_field="${parts[parts_len-1]}"
  # the fields before last are the path components but may include empty items ('' from '||')
  # collect non-empty fields in order as path components
  path_components=()
  for ((i=0;i<parts_len-1;i++)); do
    part="${parts[i]}"
    # trim surrounding spaces
    part="$(echo -n "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -n "$part" ]; then
      path_components+=("$part")
    fi
  done

  # if no path components (e.g. line starts with |cmd), skip
  if [ ${#path_components[@]} -eq 0 ]; then
    continue
  fi

  # the leaf name is the last component
  leaf="${path_components[-1]}"

  # parent path is components without the leaf
  if [ ${#path_components[@]} -gt 1 ]; then
    parent_arr=("${path_components[@]:0:${#path_components[@]}-1}")
    parent_key="$(_join_path parent_arr)"
  else
    parent_key="ROOT"
  fi

  # register child under parent_key
  existing="${CHILDREN[$parent_key]:-}"
  # avoid duplicate child entries
  if [ -z "$existing" ] || [[ "$existing" != *"${SEP}${leaf}${SEP}"* && "$existing" != "${leaf}${SEP}"* && "$existing" != *"${SEP}${leaf}"* ]]; then
    if [ -z "$existing" ]; then
      CHILDREN[$parent_key]="${leaf}${SEP}"
    else
      CHILDREN[$parent_key]="${existing}${leaf}${SEP}"
    fi
  fi

  # record command for this specific parent+leaf (unique)
  CMD_MAP["${parent_key}::${leaf}"]="$cmd_field"

  # mark parent as having a parent (for deeper nesting)
  # also ensure that intermediate ancestors exist as keys (even if no direct children yet)
  # walk ancestors to ensure maps created
  # also mark that parent's parent is parent of parent
  if [ "${parent_key}" != "ROOT" ]; then
    # ensure parent of parent exists
    IFS='::' read -r -a pp <<< "$parent_key"
    if [ ${#pp[@]} -gt 1 ]; then
      grand_parent_arr=("${pp[@]:0:${#pp[@]}-1}")
      gp_key="$(_join_path grand_parent_arr)"
      IS_PARENT["$gp_key"]=1
    else
      IS_PARENT["ROOT"]=1
    fi
    IS_PARENT["$parent_key"]=1
  else
    IS_PARENT["ROOT"]=1
  fi
done

# ensure top-level keys exist if no explicit ROOT children (fallback to original ALL_LINES)
if [ -z "${CHILDREN[ROOT]:-}" ]; then
  # fallback: each ALL_LINES line's first non-empty field as top-level
  for line in "${ALL_LINES[@]}"; do
    IFS='|' read -r -a parts <<< "$line"
    parts_len=${#parts[@]}
    if (( parts_len < 2 )); then continue; fi
    # find first non-empty before last
    first=""
    for ((i=0;i<parts_len-1;i++)); do
      p="$(echo -n "${parts[i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [ -n "$p" ]; then first="$p"; break; fi
    done
    if [ -n "$first" ]; then
      existing="${CHILDREN[ROOT]:-}"
      if [ -z "$existing" ] || [[ "$existing" != *"${SEP}${first}${SEP}"* && "$existing" != "${first}${SEP}"* && "$existing" != *"${SEP}${first}"* ]]; then
        if [ -z "$existing" ]; then
          CHILDREN[ROOT]="${first}${SEP}"
        else
          CHILDREN[ROOT]="${existing}${first}${SEP}"
        fi
      fi
    fi
  done
fi

# ====== 辅助函数：获取 CHILDREN 列表为数组 ======
_get_children_array() {
  local key="$1"
  local -a out=()
  local raw="${CHILDREN[$key]:-}"
  if [ -z "$raw" ]; then
    echo
    return
  fi
  # raw is like "a\x1fb\x1fc\x1f"
  IFS=$'\x1f' read -r -a temp <<< "$raw"
  for v in "${temp[@]}"; do
    [ -n "$v" ] && out+=("$v")
  done
  # print lines (caller will read into array)
  for e in "${out[@]}"; do printf '%s\n' "$e"; done
}

# ====== 打印当前视图（保留你原始的样式） ======
# 参数：page, items_array (按行: "显示名")
print_page_view() {
  local page="$1"
  shift
  local -a items=("$@")
  local total=${#items[@]}
  local pages=$(( (total + PER_PAGE - 1) / PER_PAGE ))
  [ $pages -lt 1 ] && pages=1
  local start=$(( (page-1)*PER_PAGE ))
  local end=$(( start+PER_PAGE-1 ))
  ((end>=total)) && end=$((total-1))

  clear
  draw_line
  draw_title "脚本管理器 (by Moreanp)"
  draw_mid

  for slot in $(seq 0 $((PER_PAGE-1))); do
    idx=$((start+slot))
    if ((idx<=end)); then
      name="${items[idx]}"
      draw_text "${C_KEY}[$slot]${C_RESET} ${C_NAME}${name}${C_RESET}"
    else
      draw_text ""
    fi
  done

  draw_mid
  draw_text "第 $page/$pages 页   共 $total 项"
  draw_text "[ n ] 下一页   [ b ] 上一页"
  draw_text "[ q ] 退出     [ 0-9 ] 选择"
  draw_bot
}

# ====== 运行选项（保持原样） ======
run_selected() {
  local parent_key="$1"
  local selected_name="$2"

  local cmd="${CMD_MAP[${parent_key}::${selected_name}]:-}"
  # if no command recorded for this parent::name, then it's a pure parent (enter deeper)
  if [ -z "$cmd" ]; then
    # no cmd -> treat as entering sub-menu
    return 2
  fi

  # parse args if any (the command field may contain '|' originally; but we stored whole last field)
  name="$selected_name"
  rest="$cmd"
  # split rest into cmd and args if there is an extra '|' (some lines may have more than one '|')
  # But in our parse above we took everything after the last '|' as command incl. args, so run directly
  clear
  echo -e "${C_KEY}👉 正在执行：${C_NAME}${name}${C_RESET}"
  echo -e "${C_DIV}-----------------------------------------${C_RESET}"

  if [[ "$rest" =~ ^CMD: ]]; then
    eval "${rest#CMD:}"
  elif [[ "$rest" =~ ^https?:// ]]; then
    bash <(curl -fsSL "${rest}")
  else
    eval "$rest"
  fi

  echo -e "${C_DIV}-----------------------------------------${C_RESET}"
  read -rp $'按回车返回菜单...' _
  return 0
}

# ====== 搜索功能（输入位置直接触发搜索） ======
# keyword -> case-insensitive substring matching of leaf names (all levels)
search_and_show() {
  local keyword="$1"
  local -a matches=()
  [ -z "$keyword" ] && return 1
  kw_lc="$(echo "$keyword" | tr '[:upper:]' '[:lower:]')"

  # iterate over all CMD_MAP entries and CHILDREN to find matches by name
  for key in "${!CMD_MAP[@]}"; do
    # key format parent::name
    name="${key##*::}"
    name_lc="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$name_lc" == *"$kw_lc"* ]]; then
      cmd="${CMD_MAP[$key]}"
      # full display should be just the name (user要求：展示全部子项，不再展示它的上级上上级)
      matches+=("${name}|${key}|${cmd}")
    fi
  done

  # also consider children that might not have CMD_MAP entries (pure parents) - optional
  # but user asked to display subitems, so focusing on entries with commands is fine.

  if [ ${#matches[@]} -eq 0 ]; then
    echo "❌ 未找到匹配项，输入 p 返回全部列表的菜单。"
    read -rp "输入: " ans || true
    if [[ "$ans" == "p" ]]; then
      return 2
    else
      return 1
    fi
  fi

  # display matches in a paginated view (but simpler: show up to PER_PAGE per page with navigation)
  local page=1
  while true; do
    # build simple display array of names
    local -a disp=()
    for m in "${matches[@]}"; do
      name="${m%%|*}"
      disp+=("$name")
    done

    print_count=${#disp[@]}
    print_page_view "$page" "${disp[@]}"

    printf "%b请输入编号 (0-9) 执行， p 返回全部列表, q 退出: %b" "$C_HINT" "$C_RESET"
    read -r in || true
    if [[ "$in" == "p" ]]; then
      return 2
    elif [[ "$in" == "q" ]]; then
      clear; echo "👋 再见！"; exit 0
    elif [[ "$in" =~ ^[0-9]+$ ]]; then
      slot="$in"
      # convert to absolute index
      idx=$(( (page-1)*PER_PAGE + slot ))
      if (( idx < 0 || idx >= ${#matches[@]} )); then
        echo "❌ 无效编号"; read -rp "按回车继续..." _
      else
        sel="${matches[$idx]}"
        sel_name="${sel%%|*}"
        sel_key="${sel#*|}"
        sel_cmd="${sel##*|}"   # careful: ## will take last '|', but format matches is name|key|cmd; this works
        # run the command
        clear
        echo -e "${C_KEY}👉 正在执行：${C_NAME}${sel_name}${C_RESET}"
        echo -e "${C_DIV}-----------------------------------------${C_RESET}"
        if [[ "$sel_cmd" =~ ^CMD: ]]; then
          eval "${sel_cmd#CMD:}"
        elif [[ "$sel_cmd" =~ ^https?:// ]]; then
          bash <(curl -fsSL "${sel_cmd}")
        else
          eval "$sel_cmd"
        fi
        echo -e "${C_DIV}-----------------------------------------${C_RESET}"
        read -rp $'按回车返回搜索结果...' _
      fi
    elif [[ "$in" =~ ^[nN]$ ]]; then
      # next page
      ((page++))
      maxp=$(( ( ${#matches[@]} + PER_PAGE -1)/PER_PAGE ))
      if (( page > maxp )); then page=$maxp; fi
    elif [[ "$in" =~ ^[bB]$ ]]; then
      ((page--))
      if (( page < 1 )); then page=1; fi
    else
      echo "⚠️ 无效输入"; sleep 0.5
    fi
  done
}

# ====== 主循环：导航树（保留原样的交互风格） ======
current_parent="ROOT"
page=1

while true; do
  # build current view array from CHILDREN[current_parent]
  IFS=$'\n' read -r -d '' -a view_items < <(_get_children_array "$current_parent" && printf '\0')
  VIEW_TOTAL=${#view_items[@]}
  VIEW_PAGES=$(( (VIEW_TOTAL + PER_PAGE - 1) / PER_PAGE ))
  [ $VIEW_PAGES -lt 1 ] && VIEW_PAGES=1
  # show page of view_items
  print_page_view "$page" "${view_items[@]}"

  printf "%b请输入选项 (0-9 / n / b / q / 搜索关键词): %b" "$C_HINT" "$C_RESET"
  read -r key || true
  # trim spaces
  key="$(echo -n "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  case "$key" in
    [0-9])
      slot="$key"
      start=$(( (page-1)*PER_PAGE ))
      idx=$(( start + slot ))
      if (( idx<0 || idx>=VIEW_TOTAL )); then
        echo "❌ 无效选项"; read -rp "按回车返回..." _
        continue
      fi
      sel_name="${view_items[$idx]}"
      # try to run; if no command, treat as enter submenu
      run_selected "$current_parent" "$sel_name"
      rc=$?
      if [ "$rc" -eq 2 ]; then
        # no command -> enter submenu
        if [ "$current_parent" == "ROOT" ]; then
          new_parent="$sel_name"
        else
          new_parent="${current_parent}::${sel_name}"
        fi
        # if new_parent has children, descend; else show notice
        if [ -n "${CHILDREN[$new_parent]:-}" ]; then
          current_parent="$new_parent"
          page=1
        else
          echo "⚠️ 当前项无下级可进入，也无可执行命令。"
          read -rp "按回车返回..." _
        fi
      fi
      ;;
    n|N)
      ((page<VIEW_PAGES)) && ((page++)) || { echo "已是最后一页"; read -rp "按回车返回..." _; }
      ;;
    b|B)
      # go to parent of current_parent
      if [ "$current_parent" == "ROOT" ]; then
        echo "已是主菜单"; read -rp "按回车返回..." _
      else
        # trim last '::name'
        parent="$current_parent"
        if [[ "$parent" == *"::"* ]]; then
          parent="${parent%::*}"
        else
          parent="ROOT"
        fi
        current_parent="$parent"
        page=1
      fi
      ;;
    q|Q)
      clear; echo "👋 再见！"; exit 0
      ;;
    "")
      # empty input, ignore
      ;;
    *)
      # treat as search keyword (also supports pressing letters or 'ins', 'sta' etc.)
      # if user inputs exactly 'p' we treat as return to full menu
      if [[ "$key" == "p" || "$key" == "P" ]]; then
        # reset to root view
        current_parent="ROOT"
        page=1
        continue
      fi
      # call search
      search_and_show "$key"
      # return from search: if user pressed p we get return code 2, so go to root
      # search_and_show manages execution and returns/loops internally
      # after returning, continue loop - view remains what it was
      ;;
  esac
done
