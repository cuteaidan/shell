print_page() {
  local page="$1"
  local start=$(( (page - 1) * PER_PAGE ))
  local end=$(( start + PER_PAGE - 1 ))
  (( end >= TOTAL )) && end=$(( TOTAL - 1 ))

  clear
  draw_line
  local title="脚本管理器 (by Moreanp)"
  local pad=$(( (BOX_WIDTH - ${#title} - 2) / 2 ))
  printf "%b║%*s%s%*s║%b\n" "$C_BOX" "$pad" "" "$title" "$((BOX_WIDTH - pad - ${#title} - 2))" "" "$C_RESET"
  draw_mid

  for slot in $(seq 0 $((PER_PAGE-1))); do
    idx=$(( start + slot ))
    if (( idx <= end )); then
      name="${ALL_LINES[idx]%%|*}"
      # 去掉颜色码计算长度
      clean_len=${#name}
      # 序号宽度固定 4 个字符 "[0] "
      padding=$((BOX_WIDTH - 4 - clean_len - 2))
      ((padding<0)) && padding=0
      printf "%b║ %b[%d]%b %b%s%*s║%b\n" \
        "$C_BOX" "$C_KEY" "$slot" "$C_BOX" "$C_NAME" "$name" "$padding" "" "$C_RESET"
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
