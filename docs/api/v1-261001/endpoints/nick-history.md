# `/api/nick-history` —— 某个昵称的完整出现历史

> 通用规则见[当前版契约](../README.md)。

| 项 | 值 |
|---|---|
| 方法 | **`GET` 和 `POST`** |
| 路径 | `/api/nick-history`、`/api/nick-history/v1`、`/api/nick-history/v1-261001`、`/api/nick-history/v1-260925` |
| 基础额度 | **1** |
| 体积加权 | **是** |
| 每分钟闸门 | **无全局闸门**（纯本地索引） |
| 缓存 | 无 |

## 请求参数

| ID | 参数 | 位置 | 默认 | 说明 |
| ---: | --- | --- | --- | --- |
| [20](../../parameter-registry.md) | `nick` | query/body | —— | **必填** |
| [21](../../parameter-registry.md) | `limit` | query/body | **200** | **只限制 `recent[]` 的条数，不影响 `count`** |

- `nick` 缺失 → `400 missing_param`。
- **索引里没有任何命中 → `404 not_found`**（附带 `query`），不是空数组。
- `limit` **没有上下限钳制**；非数字 → `500 internal`。

## 响应 `data`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `nick` | string | 昵称 |
| `ign` | string | 关联的正版 ID |
| `uuid` | string | UUID |
| `count` | number | 该昵称的**总**出现次数（不受 `limit` 影响） |
| `first_seen` / `first_ts` | —— | 首次出现 |
| `last_seen` / `last_ts` | —— | 最后出现 |
| `index_seen_at` / `index_seen_ts` | —— | **索引本身**最后一次更新涉及该昵称的时间 |
| `channels` | array | `[{channel, count}]`，按频道统计出现次数 |
| `recent` | array | `[{ts, at, channel, message_id}]`，最近的记录明细（受 `limit` 限制） |

> 💡 `index_seen_ts` 与 `last_ts` 不同：前者是**索引维护**看到它的时间，
> 后者是**消息本身**的时间。跨天补录时两者会分叉。

## 示例

```bash
curl 'https://api.firebounce.today/api/nick-history?nick=theoshadow&limit=10' \
  -H 'X-API-Key: bsk_...'
```

```json
{
  "ok": true,
  "api_version": "v1-261001",
  "locale": "en",
  "schema": 1,
  "data": {
    "nick": "theoshadow",
    "ign": "ExamplePlayer",
    "uuid": "00000000000000000000000000000001",
    "count": 128,
    "first_seen": "2026-08-20 21:52",
    "first_ts": 1787233926,
    "last_seen": "2026-08-28 10:56",
    "last_ts": 1787885782,
    "index_seen_at": "2026-10-02 13:41",
    "index_seen_ts": 1790950867,
    "channels": [{"channel": "1234567890", "count": 128}],
    "recent": [{"ts": 1787885782, "at": "2026-08-28 10:56",
                "channel": "1234567890", "message_id": "9876543210"}]
  }
}
```

## 错误

| 状态码 | `error` | 场景 |
| ---: | --- | --- |
| `400` | `missing_param` | `nick` 没给 |
| `401` | 鉴权系列 | —— |
| `404` | `not_found` | 索引里没有该昵称（附带 `query`） |
| `429` | `rate_limited` | 每 Key 配额 |
| `500` | `internal` | `limit` 非数字 |

## 版本差异

响应字段两版相同；差异只有信封与文案语言。
