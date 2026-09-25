#!/usr/bin/env bash
# BSK denick 查询 API —— curl 示例
#
# 用法:
#   export BSK_KEY="bsk_你的key"
#   ./denick_curl.sh theoshadow      # 昵称
#   ./denick_curl.sh bsk10ww         # 真名 / 旧名 也能查
#   ./denick_curl.sh --uuid 694cd52b-8197-45f0-b28d-ad73eb299699
#
# 文档: https://github.com/bedkillerspacex-boop/bsk-hypixel-api
# 申请 Key: 在 QQ 群里发  /apikey 你的QQ号  (机器人发不出私聊, Key 走你的 QQ 邮箱)

set -euo pipefail

API="https://api.firebounce.today/api/denick"
: "${BSK_KEY:?请先 export BSK_KEY=\"bsk_你的key\"}"

if [ "${1:-}" = "--uuid" ]; then
  PARAM="uuid=${2:?用法: $0 --uuid <UUID>}"
else
  PARAM="nick=${1:?用法: $0 <昵称>}"
fi

echo "== 查询: $PARAM"
echo

echo "-- ① Authorization: Bearer (推荐)"
curl -s -H "Authorization: Bearer $BSK_KEY" "$API?$PARAM"
echo; echo

echo "-- ② X-API-Key"
curl -s -H "X-API-Key: $BSK_KEY" "$API?$PARAM"
echo; echo

echo "-- ③ POST + JSON"
curl -s -X POST -H "Authorization: Bearer $BSK_KEY" \
     -H "Content-Type: application/json" \
     -d "{\"$( [ "${1:-}" = "--uuid" ] && echo uuid || echo nick )\":\"${2:-${1:-}}\"}" \
     "$API"
echo; echo

echo "-- ④ 只看关键字段 (需要 jq)"
if command -v jq >/dev/null 2>&1; then
  curl -s -H "Authorization: Bearer $BSK_KEY" "$API?$PARAM" \
    | jq -r '.data | "\(.nick) -> \(.ign)  uuid=\(.uuid)\n  名字 \(.names|length) 个: \(.names|join(", "))\n  昵称 \(.nick_count) 个: \(.nicks[:5]|join(", "))"'
else
  echo "  (没装 jq, 跳过)"
fi
echo

echo "-- ⑤ 带 HTTP 状态码"
curl -s -o /dev/null -w "HTTP %{http_code}  用时 %{time_total}s\n" \
     -H "Authorization: Bearer $BSK_KEY" "$API?$PARAM"
