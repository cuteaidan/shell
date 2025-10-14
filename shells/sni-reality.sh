(for d in \
  www.cloudflare.com www.apple.com www.microsoft.com www.bing.com www.google.com \
  developer.apple.com www.gstatic.com fonts.gstatic.com fonts.googleapis.com \
  res-1.cdn.office.net res.public.onecdn.static.microsoft static.cloud.coveo.com \
  aws.amazon.com www.aws.com cloudfront.net d1.awsstatic.com \
  cdn.jsdelivr.net cdn.jsdelivr.org polyfill-fastly.io \
  beacon.gtv-pub.com s7mbrstream.scene7.com cdn.bizibly.com \
  www.sony.com www.nytimes.com www.w3.org www.wikipedia.org \
  ajax.cloudflare.com www.mozilla.org www.intel.com \
  api.snapchat.com images.unsplash.com \
  edge-mqtt.facebook.com video.xx.fbcdn.net \
  gstatic.cn \
; do \
  t1=$(date +%s%3N); \
  timeout 1 openssl s_client -connect $d:443 -servername $d </dev/null &>/dev/null && \
  t2=$(date +%s%3N) && echo "$((t2 - t1)) $d"; \
done) | sort -n | head -n 10 | awk '{printf "✔️  %s (%s ms)\n", $2, $1}'
