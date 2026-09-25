#!/usr/bin/env bash
# Hypixel 官方 API 反代的 curl 示例。
#
# ★ 要写调用代码请以 Hypixel **官方**文档为准:
#     https://api.hypixel.net/
#     https://github.com/HypixelDev/PublicAPI
#   我们只是把 base url 换掉, 端点和返回的 JSON 与官方完全一致。
#
# 认证用本站的 bsk_ Key (QQ 群里发 /apikey 申请), 不是 Hypixel 的 Key。
#
#   export BSK_KEY=bsk_你的key
#   bash hypixel_proxy_curl.sh

set -u
: "${BSK_KEY:?请先 export BSK_KEY=bsk_你的key}"
BASE="https://hyp-api.firebounce.today"
UUID="${1:-654e39a1599c4da7b711b0ebf4e73738}"     # lovelycatuwu

echo "Base: $BASE   (官方是 https://api.hypixel.net)"
echo

echo "== ① /v2/player  (官方文档: Get Player) =="
# 认证头就叫 API-Key —— 和 Hypixel 官方完全一样
curl -s -H "API-Key: $BSK_KEY" "$BASE/v2/player?uuid=$UUID" \
  | head -c 220
echo; echo

echo "== ② /v2/status =="
curl -s -H "API-Key: $BSK_KEY" "$BASE/v2/status?uuid=$UUID"
echo; echo

echo "== ③ /v2/guild =="
curl -s -H "API-Key: $BSK_KEY" "$BASE/v2/guild?player=$UUID" | head -c 200
echo; echo

echo "== ④ 看限流头 (原样透传, 可据此自己限速) =="
curl -s -D - -o /dev/null -H "API-Key: $BSK_KEY" "$BASE/v2/status?uuid=$UUID" \
  | grep -i 'ratelimit'
echo

echo "== ⑤ 看 X-Quota-Cost (本站按**响应体积**加权扣额度) =="
echo "   普通响应扣 1; >1MB 扣 4; >5MB 扣 8"
printf "   /v2/status              -> "
curl -s -D - -o /dev/null -H "API-Key: $BSK_KEY" "$BASE/v2/status?uuid=$UUID" \
  | grep -i 'x-quota-cost' | tr -d '\r'
printf "   skyblock/collections    -> "
curl -s -D - -o /dev/null -H "API-Key: $BSK_KEY" "$BASE/v2/resources/skyblock/collections" \
  | grep -i 'x-quota-cost' | tr -d '\r'
echo "   (skyblock/items 有 5MB, 扣 8 —— 这类静态资源请本地缓存)"
echo

echo "== ⑥ Authorization 传法也能用 =="
curl -s -o /dev/null -w 'HTTP %{http_code}\n' \
  -H "Authorization: Bearer $BSK_KEY" "$BASE/v2/status?uuid=$UUID"

echo
echo "注: PowerShell 里要用 curl.exe (curl 是 Invoke-WebRequest 的别名)。"
