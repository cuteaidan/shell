#!/usr/bin/env bash
# check_domains_v3_color_fixed.sh
# 交互式域名延迟测速工具 v3 — 彩色表格修正版

set -o errexit
set -o pipefail
set -o nounset

# ======= ANSI 颜色定义 =======
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
RESET="\033[0m"

# ======= 域名列表 =======
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
"d0.m.awsstatic.com" "t0.m.awsstatic.com" "ts2.tc.mm.bing.net" "tag.demandbase.com"
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
"gray-config-prod.api.arc-cdn.net" "img-prod-cms-rt-microsoft-com.akamaized.net"
"downloaddispatch.itunes.apple.com"
)

# ======= 工具函数 =======
now_ms() {
    if date +%s%3N >/dev/null 2>&1; then
        date +%s%3N
    else
        python3 - <<'PY'
import time;print(int(time.time()*1000))
PY
    fi
}

render_progress() {
    local done=$1 total=$2
    local cols=40
    local perc=$(( done * 100 / total ))
    local filled=$(( perc * cols / 100 ))
    local empty=$(( cols - filled ))
    printf "\r${YELLOW}Progress: |"
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s-" $(seq 1 $empty)
    printf "| %3d%% (%d/%d attempts)${RESET}" "$perc" "$done" "$total"
}

run_test() {
    local n="$1" ATTEMPTS_PER_DOMAIN="$2"
    local unique_list=$(printf "%s\n" "${domains[@]}" | awk '!seen[$0]++')
    local total_unique=$(printf "%s\n" "$unique_list" | wc -l | tr -d ' ')
    local selected_list

    if [ "$n" -eq 0 ]; then
        selected_list="$unique_list"
    else
        if [ "$n" -ge "$total_unique" ]; then
            selected_list="$unique_list"
        else
            selected_list=$(printf "%s\n" "$unique_list" | shuf -n "$n")
        fi
    fi

    mapfile -t domains_to_test < <(printf "%s\n" "$selected_list")
    local num_domains=${#domains_to_test[@]}
    local total_attempts=$(( num_domains * ATTEMPTS_PER_DOMAIN ))
    local completed=0
    tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' RETURN

    echo
    echo "开始测试，每个域名测试 ${ATTEMPTS_PER_DOMAIN} 次..."
    echo

    for d in "${domains_to_test[@]}"; do
        sum=0; min=0; max=0; succ=0
        for i in $(seq 1 $ATTEMPTS_PER_DOMAIN); do
            t1=$(now_ms)
            if timeout 1 openssl s_client -connect "${d}:443" -servername "$d" </dev/null &>/dev/null; then
                t2=$(now_ms)
                diff=$(( t2 - t1 ))
                sum=$(( sum + diff ))
                if [ "$succ" -eq 0 ] || [ "$diff" -lt "$min" ]; then min=$diff; fi
                if [ "$succ" -eq 0 ] || [ "$diff" -gt "$max" ]; then max=$diff; fi
                succ=$(( succ + 1 ))
            fi
            completed=$(( completed + 1 ))
            render_progress "$completed" "$total_attempts"
            sleep 0.05
        done
        if [ "$succ" -gt 0 ]; then
            avg=$(( sum / succ ))
            printf "%d|%d|%d|%d|%s\n" "$avg" "$min" "$max" "$succ" "$d" >>"$tmpfile"
        else
            printf "9999999|0|0|0|%s\n" "$d" >>"$tmpfile"
        fi
    done
    render_progress "$total_attempts" "$total_attempts"; echo; echo

    sorted=$(mktemp)
    sort -t'|' -n -k1 "$tmpfile" >"$sorted"

    display_limit=$(( num_domains ))
    if [ "$num_domains" -ge 20 ] || [ "$n" -eq 0 ]; then display_limit=10; fi

    # ======= 打印表格 =======
    printf "%-4s %-45s %10s %8s %8s %10s\n" "Rank" "Domain" "Avg(ms)" "Min" "Max" "Succ/${ATTEMPTS_PER_DOMAIN}"
    printf "%-4s %-45s %10s %8s %8s %10s\n" "----" "---------------------------------------------" "--------" "----" "----" "--------"

    rank=0
    while IFS='|' read -r avg min max succ dom; do
        rank=$((rank+1))
        [ "$rank" -gt "$display_limit" ] && break

        if [ "$avg" -ge 9999999 ]; then
            avg_disp="TIMEOUT"
            succ_disp="0/${ATTEMPTS_PER_DOMAIN}"
        else
            avg_disp="${GREEN}${avg}${RESET}"
            if [ "$succ" -lt "$ATTEMPTS_PER_DOMAIN" ]; then
                succ_disp="${RED}${succ}/${ATTEMPTS_PER_DOMAIN}${RESET}"
            else
                succ_disp="${GREEN}${succ}/${ATTEMPTS_PER_DOMAIN}${RESET}"
            fi
        fi

        printf "%-4d %-45s %10b %8d %8d %10b\n" "$rank" "$dom" "$avg_disp" "$min" "$max" "$succ_disp"
    done <"$sorted"

    if [ "$display_limit" -lt "$num_domains" ]; then
        echo
        echo "（仅显示前 $display_limit 项，共测试 $num_domains 个）"
    fi
    echo
}

# ======= 主循环 =======
while true; do
    echo
    echo "=============================="
    echo "   域名延迟测试工具 v3 (by Moreanp)"
    echo "=============================="
    echo "选择测试模式："
    echo "  1 = 随机 10 个域名（默认尝试 5 次）"
    echo "  2 = 随机 20 个域名（默认尝试 3 次）"
    echo "  a / all = 测试全部域名（默认尝试 1 次）"
    echo "  q / quit = 退出"
    echo
    read -rp "请输入选择 (回车默认 10): " choice

    case "$choice" in
        ""|1)
            n=10
            default_attempts=5
            ;;
        2)
            n=20
            default_attempts=3
            ;;
        a|A|all|ALL)
            n=0
            default_attempts=1
            ;;
        q|Q|quit|QUIT)
            echo "退出程序 👋"; exit 0
            ;;
        *)
            echo "输入无效，默认随机 10 个"
            n=10
            default_attempts=5
            ;;
    esac

    read -rp "请输入每个域名的测试次数 (默认 ${default_attempts}): " input_attempts
    if [[ "$input_attempts" =~ ^[1-9][0-9]*$ ]]; then
        ATTEMPTS_PER_DOMAIN=$input_attempts
    else
        ATTEMPTS_PER_DOMAIN=$default_attempts
    fi

    run_test "$n" "$ATTEMPTS_PER_DOMAIN"

    while true; do
        read -rp "是否继续？(r=重新随机, 1/2/a=改模式, q=退出): " next
        case "$next" in
            r|R)
                echo "重新随机测试..."
                run_test "$n" "$ATTEMPTS_PER_DOMAIN"
                ;;
            1|2|a|A|all|ALL)
                choice="$next"
                break
                ;;
            q|Q|quit|QUIT)
                echo "退出程序 👋"
                exit 0
                ;;
            *)
                echo "输入无效，请重新输入。"
                ;;
        esac
    done
done
