# `/api/quota`

查询当前 API Key 的额度和水位，免费但自身默认限速 10 次/分钟。

| 项 | 值 |
|---|---|
| 方法 | GET / POST |
| 参数 | 鉴权参数 [1–5](../../parameter-registry.md)，无业务参数 |
| 额度 | 0；所有状态的 `X-Quota-Cost` 都是 `0` |
| 缓存 | `no-store` |

```bash
curl 'https://api.firebounce.today/api/quota/v1-261001' \
  -H 'Authorization: Bearer bsk_...'
```

响应的 `data` 包含 `key`（掩码）、`per_min`、`used`、`remaining`、`charged`、`reserved`、`reset_at`、`unlimited`、`concurrency`、`prices`、`self`，以及可用时的 `global_gate` / `proxy_gate`。`used` 包含已经结算和在途预留。
下面是结构节选；完整字段表见[额度契约](../README.md#9-apiquota)。

```json
{"ok":true,"api_version":"v1-261001","locale":"en","schema":1,
 "data":{"key":"bsk_0000…0000","used":1.5,"reserved":0,
 "remaining":118.5,"unlimited":false,"self":{"per_min":10,"used":1,"remaining":9}},"cost":0}
```

缺少或无效 Key 返回 401；自身限速返回 429 和 `Retry-After`。内部并发仍可能影响该请求。
若提前被并发闸门拒绝，未进入 quota 函数，其原始响应的理论 `X-Quota-Cost` 可能为 `1`；实际仍然不扣费，且没有版本信封。
