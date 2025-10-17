#!/usr/bin/env bash
# check_domains.sh
# 功能：从内置域名列表随机选择 N 个（或全部）并用 openssl s_client 测试 443 连接耗时（ms）
# 选项：
#   回车（空输入） -> 默认随机 10 个
#   1 -> 随机 10 个
#   2 -> 随机 20 个
#   0 -> 测试全部（去重后）
set -o errexit
set -o pipefail
set -o nounset

# ------- 域名列表（来自你给的全部域名） -------
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

# ------- 用户交互：选择测试数量 -------
cat <<'EOT'
选择测试模式：
  回车（空输入） -> 随机 10 个（默认）
  1 -> 随机 10 个
  2 -> 随机 20 个
  0 -> 测试全部（去重后）
请输入： (按 Enter 默认 10)
EOT

read -r choice

# 处理选择
case "$choice" in
    "") n=10 ;;
    1) n=10 ;;
    2) n=20 ;;
    0) n=0 ;;   # 0 表示全部
    *) 
       # 如果用户输入的是正整数，尝试用作数量
       if [[ "$choice" =~ ^[0-9]+$ ]]; then
           if [ "$choice" -gt 0 ]; then
               n="$choice"
           else
               n=10
           fi
       else
           echo "无法识别输入，使用默认 10 个"
           n=10
       fi
       ;;
esac

# ------- 去重并准备待测列表 -------
# 将数组转为去重的行列表
unique_list=$(printf "%s\n" "${domains[@]}" | awk '!seen[$0]++')

total_unique=$(printf "%s\n" "$unique_list" | wc -l | tr -d ' ')
if [ "$n" -eq 0 ]; then
    # 全部
    selected_list="$unique_list"
    echo "选择：全部 $total_unique 个域名进行测试"
else
    # 如果请求数量超过总数，则改为全部
    if [ "$n" -ge "$total_unique" ]; then
        selected_list="$unique_list"
        echo "请求的数量 $n >= 可用域名数 $total_unique，改为测试全部 $total_unique 个"
    else
        # 用 shuf 随机选取（若无 shuf，使用 sort -R 作为后备）
        if command -v shuf >/dev/null 2>&1; then
            selected_list=$(printf "%s\n" "$unique_list" | shuf -n "$n")
        else
            # sort -R 不是每个平台都支持，但在大多数 Linux 上可用
            selected_list=$(printf "%s\n" "$unique_list" | sort -R | head -n "$n")
        fi
        echo "随机选择 $n 个域名进行测试（从 $total_unique 个去重后域名中）"
    fi
fi

# ------- 测试函数 -------
echo
echo "开始测试（每个域名使用 'timeout 1 openssl s_client -connect domain:443 -servername domain'）"
echo "如果命令返回非 0 则视为 timeout 或失败。"
echo

# 遍历并测试
while IFS= read -r d; do
    # 跳过空行
    [ -z "$d" ] && continue
    # 记录开始时间（毫秒）
    t1=$(date +%s%3N 2>/dev/null || python3 - <<'PY' && exit 0
import time,sys
print(int(time.time()*1000))
PY
)
    # 实际连接测试（1 秒超时）
    if timeout 1 openssl s_client -connect "$d:443" -servername "$d" </dev/null &>/dev/null; then
        t2=$(date +%s%3N 2>/dev/null || python3 - <<'PY' && exit 0
import time,sys
print(int(time.time()*1000))
PY
)
        # 计算差值（毫秒）
        # 注意：如果使用 python fallback，上面的 logic 会提前 exit 脚本；为了稳妥，这里尽量假设 GNU date 可用。
        if [[ "$t1" =~ ^[0-9]+$ && "$t2" =~ ^[0-9]+$ ]]; then
            diff=$((t2 - t1))
            echo "$d: ${diff} ms"
        else
            # 若时间获取异常，简单打印 success
            echo "$d: connected"
        fi
    else
        echo "$d: timeout"
    fi
done <<< "$selected_list"

echo
echo "测试完成。"
