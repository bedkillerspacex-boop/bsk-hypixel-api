# `/api/tags` —— 只要反作弊标签

> 通用规则见[当前版契约](../README.md)。

| 项 | 值 |
|---|---|
| 方法 | **`GET` 和 `POST`** |
| 路径 | `/api/tags`、`/api/tags/v1`、`/api/tags/v1-261001`、`/api/tags/v1-260925` |
| 基础额度 | **1.5** |
| 体积加权 | **是** |
| 每分钟闸门 | **全局玩家闸门 90/分钟** |
| 缓存 | 无 |

比 [`/api/player`](./player.md) 轻（只打 Urchin，不拉战绩），**但额度一样是 1.5**。

## 请求参数

| ID | 参数 | 位置 | 必填 |
| ---: | --- | --- | --- |
| [9](../../parameter-registry.md) | `name` | query/body | 否 |
| [10](../../parameter-registry.md) | `uuid` | query/body | 否 |
| [11](../../parameter-registry.md) | `nick` | **query** | 否 |

## ⚠️ 处理顺序：`400` 也会扣 1.5

1. 鉴权 + 扣 **1.5**
2. 目标校验 → 可能 `400 missing_param`
3. 全局玩家闸门 → 可能 `429`

**扣费在校验之前**，所以参数没给全时你**已经付了 1.5**。
（对比：`/api/bancheck` 的缺参检查在鉴权**之前**，所以不扣。）

## 响应 `data`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `query` | string | 你查的值 |
| `uuid` | string | 带横线 UUID |
| `name` | string | 正版 ID |
| `tags` | array | 标签对象列表 |
| `tag_types` | array<string> | 只取 `tag_type` 的字符串列表 |
| `suspicion` | object \| null | `{score, legit, tag_adjust}` |
| `sources` | object | `{tags, hypixel, suspicion?}` —— 各上游 `"ok"` 或错误字符串 |

## 示例

```bash
curl 'https://api.firebounce.today/api/tags?name=ExamplePlayer' \
  -H 'X-API-Key: bsk_...'
```

```json
{
  "ok": true,
  "api_version": "v1-261001",
  "locale": "en",
  "schema": 1,
  "data": {
    "query": "ExamplePlayer",
    "uuid": "00000000-0000-0000-0000-000000000001",
    "name": "ExamplePlayer",
    "tags": [{"tag_type": "confirmed_cheater", "reason": "Killaura",
              "added_on": 1787885782, "expires_at": null}],
    "tag_types": ["confirmed_cheater"],
    "suspicion": {"score": 42, "legit": 58, "tag_adjust": 0},
    "sources": {"tags": "ok", "hypixel": "ok", "suspicion": "ok"}
  }
}
```

## 错误

| 状态码 | `error` | 场景 |
| ---: | --- | --- |
| `400` | `missing_param` | 三个参数都没给（**已扣 1.5**） |
| `401` | 鉴权系列 | —— |
| `404` | `not_found` | 查不到（附带 `query`） |
| `429` | `rate_limited` | 每 Key 配额或玩家闸门 |
| `502` | `upstream_failed` | 上游失败 |

## 版本差异

响应字段两版相同；差异只有信封与文案语言（本接口的展示文案很少）。
