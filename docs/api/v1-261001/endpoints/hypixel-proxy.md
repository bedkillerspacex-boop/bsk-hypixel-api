# Hypixel transparent proxy

Base: `https://hyp-api.firebounce.today/v2/*`. The `/api/hypixel/*` alias is GET-only and forwards its subpath; a GET version-looking suffix is treated as an upstream path, not a site API version. A bare `/api/hypixel` discovery response is HTTP 200 and does not authenticate or call upstream.

| Item | Value |
|---|---|
| Auth | BSK `bsk_` key, not a real Hypixel key |
| Upstream timeout | 12 seconds per key |
| Retry | Up to 3 different keys, 30 second total upstream budget |
| Rate gate | `QQBOT_PROXY_RATE`, default 600/minute; `/apikey rate proxy` changes it at runtime |
| Cache | HTTP 200 and non-empty only, fixed 300 seconds, max 512; expired then oldest eviction |
| Quota | Success after writeback: full base plus size fee; failure/writeback failure: base 50%, no size fee |

```bash
curl 'https://hyp-api.firebounce.today/v2/player?uuid=00000000000000000000000000000001' \
  -H 'X-API-Key: bsk_...'
```

The upstream status and body are forwarded unchanged. Only selected headers are forwarded (`Content-Type`, `RateLimit-*`, `Retry-After`, `Cache-Control`); `Content-Length` is recalculated and CORS/`X-Quota-Cost` are added. `/v2/*` POST is not proxied.
