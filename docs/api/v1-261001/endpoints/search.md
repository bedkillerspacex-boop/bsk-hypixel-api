# `/api/search` —— 昵称 / 真名模糊搜索

> 通用规则见[当前版契约](../README.md)。

| 项 | 值 |
|---|---|
| 方法 | **`GET` 和 `POST`** |
| 路径 | `/api/search`、`/api/search/v1`、`/api/search/v1-261001`、`/api/search/v1-260925` |
| 基础额度 | **1** |
| 体积加权 | **是** |
| 每分钟闸门 | **无全局闸门**（纯本地索引） |
| 缓存 | 无 |

## 请求参数

| ID | 参数 | 位置 | 默认 | 说明 |
| ---: | --- | --- | --- | --- |
| [15](../../parameter-registry.md) | `q` | query/body | —— | **必填**，至少 2 个字符 |
| [16](../../parameter-registry.md) | `query` | query/body | —— | `q` 的别名 |
| [17](../../parameter-registry.md) | `limit` | query/body | **20** | 返回条数，钳制到 **1–100** |

- `q` 少于 2 个字符（含没给）→ `400 missing_param`，
  `message`: `"q must contain at least 2 characters"`。
- `limit` 非数字 → `500 internal`（服务端不做容错，直接抛）。
- `limit` 超出范围会被**钳制**，不是报错。

### 校验顺序

```
鉴权 (401)  →  参数校验 (400)  →  查询
```

先鉴权再校验 `q` —— 实测 **没有 Key 时即使 `q` 只有 1 个字符也回 `401`**，
不会先报 `400`。

## 响应 `data`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `query` | string | 搜索词 |
| `count` | number | 结果条数 |
| `results` | array | 结果列表 |

每条结果：

| 字段 | 说明 |
| --- | --- |
| `nick` | 昵称 |
| `ign` | 真实正版 ID |
| `uuid` | 无横线小写 UUID |
| `seen_at` / `seen_ts` | 该记录最后一次出现 |
| `matched` | 命中方式：`nick` / `ign` |

## 示例

```bash
curl 'https://api.firebounce.today/api/search?q=theo&limit=5' \
  -H 'X-API-Key: bsk_...'
```

```json
{
  "ok": true,
  "api_version": "v1-261001",
  "locale": "en",
  "schema": 1,
  "data": {
    "query": "theo",
    "count": 1,
    "results": [
      {"nick": "theoshadow", "ign": "ExamplePlayer",
       "uuid": "00000000000000000000000000000001",
       "seen_at": "2026-08-28 10:56", "seen_ts": 1787885782,
       "matched": "nick"}
    ]
  }
}
```

> 💡 **匹配到的 `ign` 不等于"和搜索词同一个人"。** 同名 ≠ 同一人是常态，
> 结果里的每条都是索引里的一条记录，**不要**把 `count` 当成"这个人有 N 个号"。

## 错误

| 状态码 | `error` | 场景 |
| ---: | --- | --- |
| `400` | `missing_param` | `q` 缺失或少于 2 字符 |
| `401` | 鉴权系列 | —— |
| `429` | `rate_limited` | 每 Key 配额 |
| `500` | `internal` | `limit` 非数字等 |

## 版本差异

响应字段两版相同；差异只有信封与文案语言。
