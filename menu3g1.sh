# 绘制文本行，严格计算中英文及符号宽度，保证右侧边框对齐
draw_text() {
  local text="$1"
  local clean_text
  local len=0
  local i char

  # 去掉 ANSI 转义序列
  clean_text=$(echo -ne "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')

  # 计算可见长度
  len=0
  for ((i=0; i<${#clean_text}; i++)); do
    char="${clean_text:i:1}"
    # 中文字符 (CJK)
    if [[ "$char" =~ [\u4E00-\u9FFF] ]]; then
      len=$((len + 2))
    # 全角符号（兼容常用全角标点）
    elif [[ "$char" =~ [\u3000-\u303F] ]]; then
      len=$((len + 2))
    else
      len=$((len + 1))
    fi
  done

  # 右侧填充空格，保证总宽度 = BOX_WIDTH
  local padding=$((BOX_WIDTH - len - 3))  # 3 = 左右边框 + 左侧空格
  ((padding < 0)) && padding=0

  # 打印行，右侧边框颜色统一为 C_BOX
  printf "%b║ %s%*s║%b\n" "$C_BOX" "$text" "$padding" "" "$C_BOX"
}
