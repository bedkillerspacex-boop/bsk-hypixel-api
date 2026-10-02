# `/api/recent` —— 最近记录到的昵称

> 通用规则见[当前版契约](../README.md)。

| 项 | 值 |
|---|---|
| 方法 | **`GET` 和 `POST`** |
| 路径 | `/api/recent`、`/api/recent/v1`、`/api/recent/v1-261001`、`/api/recent/v1-260925` |
| 基础额度 | **1** |
| 体积加权 | **是** |
| 每分钟闸门 | **无全局闸门**（纯本地索引） |
| 缓存 | 无 |

适合做**轮询监控流**：传上次拿到的最大时间戳，只取增量。

## 请求参数

| ID | 参数 | 位置 | 默认 | 说明 |
| ---: | --- | --- | --- | --- |
| [18](../../parameter-registry.md) | `limit` | query/body | **50** | 条数，钳制到 **1–200** |
| [19](../../parameter-registry.md) | `since` | query/body | **0** | 只返回此 Unix 秒之后的记录 |

- **没有必填参数。**
- `limit` 非数字 → `500 internal`；超范围被**钳制**。
- `since` 非数字同样会 `500 internal`。

## 响应 `data`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `count` | number | 本次返回条数 |
| `since` | number | 回显你传的 `since` |
| `max_seen_ts` | number | 本批里最大的 `seen_ts`；**本批为空时等于 `since`** |
| `records` | array | 记录列表，按 `seen_ts` 倒序 |

每条记录：`{nick, ign, uuid, seen_at, seen_ts, first_seen}`。

## 轮询写法

```bash
# 第一次
curl 'https://api.firebounce.today/api/recent?limit=200' -H 'X-API-Key: bsk_...'
# 之后用上一批的 max_seen_ts 当 since
curl 'https://api.firebounce.today/api/recent?since=1787885782&limit=200' -H 'X-API-Key: bsk_...'
```

`max_seen_ts` 在空批次时等于 `since`，所以**可以无条件把它回填给下一次请求** —— 不会卡住。

## 示例

```json
{
  "ok": true,
  "api_version": "v1-261001",
  "locale": "en",
  "schema": 1,
  "data": {
    "count": 1,
    "since": 0,
    "max_seen_ts": 1787885782,
    "records": [
      {"nick": "theoshadow", "ign": "ExamplePlayer",
       "uuid": "00000000000000000000000000000001",
       "seen_at": "2026-08-28 10:56", "seen_ts": 1787885782,
       "first_seen": "2026-08-20 21:52"}
    ]
  }
}
```

> ⚠️ **`since` 是"记录的 `seen_ts` 下限"，不是服务端游标。** 它按记录时间过滤，
> 所以同一秒内的多条记录有可能在两次轮询里都出现，去重要靠 `(uuid, seen_ts)`。

## 错误

| 状态码 | `error` | 场景 |
| ---: | --- | --- |
| `401` | 鉴权系列 | —— |
| `429` | `rate_limited` | 每 Key 配额 |
| `500` | `internal` | `limit` / `since` 非数字 |

## 版本差异

响应字段两版相同；差异只有信封与文案语言。
