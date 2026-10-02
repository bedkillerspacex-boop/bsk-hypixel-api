# `/api/bancheck` / `/api/checkban`

查询本地 tracking 索引中的封禁事件；`/api/checkban` 是完全别名。它不调用 Mojang、Hypixel 或 Discord，不能代替官方实时封禁验证。

| 项 | 值 |
|---|---|
| 方法 | GET / POST |
| 参数 | [13 `name`](../../parameter-registry.md)、[14 `uuid`](../../parameter-registry.md)、[24 `nick`](../../parameter-registry.md) |
| 鉴权 | API Key；缺参数检查先于鉴权 |
| 额度 | UUID 0.7；name/nick 1.0；再按响应体积加权 |
| 大小写 | 名字使用 casefold，不区分大小写 |
| 数据 | tracking 的 bans/unbans 与 hyp_dc 辅助来源 |

参数至少提供一个，默认无目标；POST 支持 body.name/body.uuid，body.nick 被忽略（query.nick 有效）。没有严格的请求 UUID 格式校验；未命中按无记录处理。UUID 和名字一起给时先尝试 UUID，未命中再尝试名字，计费仍为 0.7。已授权但无记录也扣基础费，无 HTTP 响应缓存。

```bash
curl 'https://api.firebounce.today/api/bancheck/v1-261001?uuid=00000000000000000000000000000001' \
  -H 'X-API-Key: bsk_...'
```

```json
{"ok":true,"api_version":"v1-261001","locale":"en","schema":1,
 "data":{"known":true,"banned":true,"state":"banned","data_quality":"complete",
 "source":"tracker","sources":[{"source":"tracker","at":1790473417,"banned":true}],
 "banned_at":1790473417,"name":"ExamplePlayer","uuid":"00000000000000000000000000000001",
 "query":"ExamplePlayer","cost":0.7}}
```

`banned_at` 是主来源最近事件时间；若主事件是解封，不能把它当成封禁时间。无记录返回 HTTP 200、`known:false`、`banned:null`、`state:"unknown"`、`data_quality:"no_record"`；缺少 `name`/`uuid` 返回 400。没有记录不能证明未封禁。

新版增加 `state`、`data_quality`；旧版没有这两个字段。程序必须使用机器字段，不解析展示文案。

字段全表和错误见[完整契约](../README.md#10-apibancheck)。`complete` 只表示索引有明确结论，不保证全部历史数据或官方状态已覆盖。此接口不返回“距今天数”，只有卡片 `ban_status.banned_days_ago` 提供它。
