#!/usr/bin/env bash
# check_domains_sorted_table.sh
# 功能：按要求随机/全部选择域名，每个域名测试 3 次 TLS 连接耗时（ms），显示进度条并按平均延迟排序输出表格
set -o errexit
set -o pipefail
set -o nounset

# ---------- 域名列表（来自你提供） ----------
domains=(
"amd.com" "aws.com" "c.6sc.co" "j.6sc.co" "b.6sc.co" "intel.com" "r.bing.com" "th.bing.com"
"www.amd.com" "www.aws.com" "ipv6.6sc.co" "www.xbox.com" "www.sony.com" "rum.hlx.page"
"www.bing.com" "xp.apple.com" "www.wowt.com" "www.apple.com" "www.intel.com" "www.tesla.com"
"www.xilinx.com" "www.oracle.com" "www.icloud.com" "apps.apple.com" "c.marsflag.com"
"www.nvidia.com" "snap.licdn.com" "aws.amazon.com" "drivers.amd.com" "cdn.bizibly.com"
"s.go-mpulse.net" "tags.tiqcdn.com" "cdn.bizible.com" "ocsp2.apple.com" "cdn.userway.org"
"download.amd.com" "d1.awsstatic.com" "s0.awsstatic.com" "mscom.demdex.net" "a0.awsstatic.com"
"go.microsoft.com" "apps.mzstatic.com" "sisu.xboxlive.com" "www.microsoft.com" "s.mp.marsflag.com"
"images.nvidia.com" "vs.aws.amazon.com" "c.s-microsoft.com" "statici.icloud.com" "beacon.gtv-pub.com"
"ts4.tc.mm.bing.net" "ts3.tc.mm.bing.net" "d2c.aws.amazon.com" "ts1.tc.mm.bing.net" "ce.mf.marsflag.com"
"d0.m.awsstatic.com" "t0.m.awsstatic.com" "ts2.tc.mm.bing.net" "statici.icloud.com" "tag.demandbase.com"
"assets-www.xbox.com" "logx.optimizely.com" "azure.microsoft.com" "aadcdn.msftauth.net"
"d.oracleinfinity.io" "assets.adobedtm.com" "lpcdn.lpsnmedia.net" "res-1.cdn.office.net"
"is1-ssl.mzstatic.com" "electronics.sony.com" "intelcorp.scene7.com" "acctcdn.msftauth.net"
"cdnssl.clicktale.net" "catalog.gamepass.com" "consent.trustarc.com" "gsp-ssl.ls.apple.com"
"munchkin.marketo.net" "s.company-target.com" "cdn77.api.userway.org" "cua-chat-ui.tesla.com"
"assets-xbxweb.xbox.com" "ds-aksb-a.akamaihd.net" "static.cloud.coveo.com" "api.company-target.com"
"devblogs.microsoft.com" "s7mbrstream.scene7.com" "fpinit.itunes.apple.com" "digitalassets.tesla.com"
"d.impactradius-event.com" "downloadmirror.intel.com" "iosapps.itunes.apple.com" "www.google-analytics.com"
"se-edge.itunes.apple.com" "publisher.liveperson.net" "tag-logger.demandbase.com" "services.digitaleast.mobi"
"configuration.ls.apple.com" "gray-wowt-prod.gtv-cdn.com" "visualstudio.microsoft.com"
"prod.log.shortbread.aws.dev" "amp-api-edge.apps.apple.com" "store-images.s-microsoft.com"
"cdn-dynmedia-1.microsoft.com" "github.gallerycdn.vsassets.io" "prod.pa.cdn.uis.awsstatic.com"
"a.b.cdn.console.awsstatic.com" "d3agakyjgjv5i8.cloudfront.net" "vscjava.gallerycdn.vsassets.io"
"location-services-prd.tesla.com" "ms-vscode.gallerycdn.vsassets.io" "ms-python.gallerycdn.vsassets.io"
"gray-config-prod.api.arc-cdn.net" "i7158c100-ds-aksb-a.akamaihd.net" "downloaddispatch.itunes.apple.com"
"res.public.onecdn.static.microsoft" "gray.video-player.arcpublishing.com"
"gray-config-prod.api.cdn.arcpublishing.com" "img-prod-cms-rt-microsoft-com.akamaized.net"
"prod.us-east-1.ui.gcr-chat.marketing.aws.dev"
)

# ---------- 小工具函数 ----------
now_ms() {
    # 返回毫秒整数（尝试 GNU date，否则回退 python3）
    if date +%s%3N >/dev/null 2>&1; then
        date +%s%3N
    else
        # python3 fallback
        python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
    fi
}

# 渲染进度条： completed / total
render_progress() {
    local done=$1 total=$2
    local cols=40  # 进度条长度
    local perc=0
    if [ "$total" -gt 0 ]; then
        perc=$(( done * 100 / total ))
    fi
    local filled=$(( perc * cols / 100 ))
    local empty=$(( cols - filled ))
    printf "\rProgress: |"
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s-" $(seq 1 $empty)
    printf "| %3d%% (%d/%d attempts)" "$perc" "$done" "$total"
}

# ---------- 交互选择 ----------
cat <<'EOT'
选择测试模式：
  回车（空输入） 或 输入 1   -> 随机 10 个（默认）
  输入 2                      -> 随机 20 个
  输入 a 或 all               -> 测试全部（去重后）
  或者直接输入正整数作为测试数量
请输入： (按 Enter 默认 10)
EOT

read -r choice

case "$choice" in
    "" ) n=10 ;;
    1 ) n=10 ;;
    2 ) n=20 ;;
    a|A|all|ALL ) n=0 ;;   # 0 表示全部
    * )
       if [[ "$choice" =~ ^[0-9]+$ ]]; then
           if [ "$choice" -gt 0 ]; then
               n="$choice"
           else
               echo "输入无效，使用默认 10 个"
               n=10
           fi
       else
           echo "无法识别输入，使用默认 10 个"
           n=10
       fi
       ;;
esac

# ---------- 去重并准备待测列表 ----------
unique_list=$(printf "%s\n" "${domains[@]}" | awk '!seen[$0]++')
total_unique=$(printf "%s\n" "$unique_list" | wc -l | tr -d ' ')

if [ "$n" -eq 0 ]; then
    selected_list="$unique_list"
    echo "选择：全部 $total_unique 个域名进行测试"
else
    if [ "$n" -ge "$total_unique" ]; then
        selected_list="$unique_list"
        echo "请求的数量 $n >= 可用域名数 $total_unique，改为测试全部 $total_unique 个"
    else
        if command -v shuf >/dev/null 2>&1; then
            selected_list=$(printf "%s\n" "$unique_list" | shuf -n "$n")
        else
            selected_list=$(printf "%s\n" "$unique_list" | sort -R | head -n "$n")
        fi
        echo "随机选择 $n 个域名进行测试（从 $total_unique 个去重后域名中）"
    fi
fi

# 把 selected_list 转成数组 domains_to_test
mapfile -t domains_to_test < <(printf "%s\n" "$selected_list")

num_domains=${#domains_to_test[@]}
if [ "$num_domains" -eq 0 ]; then
    echo "没有待测试的域名，退出。"
    exit 1
fi

ATTEMPTS_PER_DOMAIN=3
total_attempts=$(( num_domains * ATTEMPTS_PER_DOMAIN ))
completed=0

# 临时文件保存中间结果（每行：avg|min|max|succ|domain 或 TIMEOUT表示）
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

echo
echo "开始测试，每个域名测试 $ATTEMPTS_PER_DOMAIN 次，单次超时 1 秒。"
echo "总尝试次数: $total_attempts"
echo

# ---------- 测试循环 ----------
for d in "${domains_to_test[@]}"; do
    # per-domain stats
    sum=0
    min=0
    max=0
    succ=0

    for i in $(seq 1 $ATTEMPTS_PER_DOMAIN); do
        t1=$(now_ms)
        if timeout 1 openssl s_client -connect "${d}:443" -servername "$d" </dev/null &>/dev/null; then
            t2=$(now_ms)
            diff=$(( t2 - t1 ))
            # update stats
            sum=$(( sum + diff ))
            if [ "$succ" -eq 0 ] || [ "$diff" -lt "$min" ]; then min=$diff; fi
            if [ "$succ" -eq 0 ] || [ "$diff" -gt "$max" ]; then max=$diff; fi
            succ=$(( succ + 1 ))
        else
            # a timeout or fail, we don't add to sum or succ
            :
        fi
        completed=$(( completed + 1 ))
        render_progress "$completed" "$total_attempts"
        # small sleep to yield (avoid flooding)
        sleep 0.05
    done

    # calculate average if any success
    if [ "$succ" -gt 0 ]; then
        avg=$(( sum / succ ))
        # write line: avg|min|max|succ|domain
        printf "%d|%d|%d|%d|%s\n" "$avg" "$min" "$max" "$succ" "$d" >> "$tmpfile"
    else
        # use very large avg for sorting so TIMEOUTS go last
        printf "%d|%s\n" "9999999" "$d" >> "$tmpfile"
    fi
done

# 完成进度条（100%）
render_progress "$total_attempts" "$total_attempts"
echo
echo

# ---------- 结果处理并输出表格 ----------
# 将 tmpfile 按 avg 数字排序升序
sorted=$(mktemp)
sort -t'|' -n -k1 "$tmpfile" > "$sorted"

# 决定输出条数：如果原始选择数 >= 20 或 测试全部（n==0）则只显示前10，否则显示全部
display_limit=$(( num_domains ))
if [ "$num_domains" -ge 20 ] || [ "$n" -eq 0 ]; then
    display_limit=10
fi

# 输出表头
printf "%-4s %-45s %8s %8s %8s %8s\n" "Rank" "Domain" "Avg(ms)" "Min(ms)" "Max(ms)" "Succ/3"
printf "%-4s %-45s %8s %8s %8s %8s\n" "----" "---------------------------------------------" "--------" "--------" "--------" "--------"

rank=0
while IFS='|' read -r avg rest; do
    # detect TIMEOUT line (only two fields: avg|domain)
    if [[ "$rest" =~ ^[0-9]+$ ]]; then
        # This shouldn't normally happen; handled below
        :
    fi

    # count rank and decide whether to print
    rank=$(( rank + 1 ))
    if [ "$rank" -gt "$display_limit" ]; then
        break
    fi

    # parse line fields
    # lines with success have 5 fields: avg|min|max|succ|domain
    IFS='|' read -r favg fmin fmax fsucc fdomain_extra <<< "$avg|$rest"
    # Note: the above split yields favg in favg, and the rest parsed
    # But because we already read avg variable, better reparse full line:
    line=$(sed -n "${rank}p" "$sorted")
    IFS='|' read -r lavg lmin lmax lsucc ldomain <<< "$line"

    if [ "$lavg" -ge 9999999 ]; then
        status="TIMEOUT"
        printf "%-4d %-45s %8s %8s %8s %8s\n" "$rank" "$ldomain" "-" "-" "-" "0/3"
    else
        printf "%-4d %-45s %8d %8d %8d %8s\n" "$rank" "$ldomain" "$lavg" "$lmin" "$lmax" "$lsucc/3"
    fi

done < "$sorted"

# 如果被截断（只显示 top 10），提示用户
if [ "$display_limit" -lt "$num_domains" ]; then
    echo
    echo "（已显示延迟最低的前 $display_limit 项 — 共测试 $num_domains 个域名；若要查看全部结果请选择更少域名或输入 '1'/'回车' 进行 10 个测试。）"
fi

# 清理
rm -f "$sorted"
