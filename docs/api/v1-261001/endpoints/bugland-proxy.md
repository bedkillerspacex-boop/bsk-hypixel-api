# Bugland transparent proxy

Base: `https://api.firebounce.today/bjd/v2/*`, upstream `https://api.mcbjd.net/v2/`. It uses an independent `bsk_bjd_` key, upstream token pool, quota files, rate limits and health policy.

| Item | Value |
|---|---|
| Methods | GET and POST |
| Auth | `bsk_bjd_...` via query or supported API-key headers |
| Key quota | 1 integer unit per authorized request |
| Rate | Default 30/minute per Bugland key |
| Concurrency | Default 20 shared process gate |
| Body limit | 4 MiB |
| Cache | None |
| Failure billing | Full base is reserved before upstream; no Hypixel 50% rule |

```bash
curl 'https://api.firebounce.today/bjd/v2/player?uuid=00000000000000000000000000000001' \
  -H 'X-API-Key: bsk_bjd_...'
```

Upstream status/body use the transparent proxy response path; errors use `{ "success": false, "cause": "..." }`. Token health checks run on the configured three-hour schedule and only definite 401/403 failures enter the 10-second/15-second recheck sequence.
