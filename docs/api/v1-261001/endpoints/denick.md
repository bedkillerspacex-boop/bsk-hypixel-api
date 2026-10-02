# `/api/denick` —— 昵称反查真名 / UUID

> 通用规则（版本、鉴权、信封、额度、闸门）见[当前版契约](../README.md)。

| 项 | 值 |
|---|---|
| 方法 | **`GET` 和 `POST`** |
| 路径 | `/api/denick`、`/api/denick/v1`、`/api/denick/v1-261001`、`/api/denick/v1-260925` |
| 旧别名 | `/denick/api`（同一处理函数，兼容历史客户端） |
| 基础额度 | **1** |
| 体积加权 | **否**（该端点不设置体积计费标记） |
| 每分钟闸门 | **无全局闸门**，只受每 Key 配额约束 |
| 缓存 | 无（直查本地索引） |

## 请求参数

| ID | 参数 | 位置 | 必填 | 说明 |
| ---: | --- | --- | --- | --- |
| [6](../../parameter-registry.md) | `nick` | query/body | 否 | 昵称、当前名、旧名，或 UUID |
| [7](../../parameter-registry.md) | `uuid` | query/body | 否 | 玩家 UUID |
| [8](../../parameter-registry.md) | `prefer` | query/body | 否 | 查询顺序 |
| [23](../../parameter-registry.md) | `name` | **query** | 否 | `nick` 的别名，**只从 query 读** |

- **`nick` / `uuid` 至少要给一个**，都没有 → `400 missing_param`。
- **两个都给时 `uuid` 优先。**
- `prefer` 接受 `uuid`、`nick`、`ign`（逗号分隔），也接受 `auto` / `default`。
  **默认顺序 `uuid,nick,ign`**。非法取值 → `400 bad_prefer`，响应里会带
  `accepted: ["uuid","nick","ign"]`。

### 校验顺序

```
鉴权 (401)  →  参数校验 (400)  →  查询 (404)
```

**这个端点先鉴权、再校验参数** —— 实测既没 Key 又没参数时回的是 `401 missing_key`，
**不是** `400`。

> ⚠️ `/api/bancheck` 恰好相反：它**先校验参数**，所以那种情况回 `400`。
> 别把两个端点的顺序搞混。（`/api/search`、`/api/nick-history` 与本文一致，也是先鉴权。）

当同一串字符既可能是昵称、也可能是真名/旧名时，`prefer` 用来指定先按哪个解释。

## 响应 `data`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `nick` | string | 命中的昵称（原样，大小写按记录） |
| `ign` | string | 真实正版 ID |
| `uuid` | string \| null | 无横线小写 UUID；记录里没有时 `null` |
| `matched_by` | string | 本次靠什么命中：`nick` / `ign` / `uuid` |
| `seen_at` / `seen_ts` | string / number | 该昵称**最后一次**出现的时间（本地时区字符串 + Unix 秒） |
| `first_seen` / `first_ts` | string \| null / number \| null | 该昵称**第一次**出现的时间 |
| `current_name` | string \| null | 该玩家**当前**正版名（按旧名查时与 `ign` 不同） |
| `names` | array | 该玩家已知的正版名 |
| `nicks` | array | 该玩家已知的昵称 |
| `nick_count` | number | 昵称数量 |

`current_name` / `names` / `nicks` / `nick_count` 只在本地有该玩家的聚合记录时才出现。

## 示例

```bash
curl 'https://api.firebounce.today/api/denick?nick=theoshadow' \
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
    "matched_by": "nick",
    "seen_at": "2026-08-28 10:56",
    "seen_ts": 1787885782,
    "first_seen": "2026-08-20 21:52",
    "first_ts": 1787233926,
    "current_name": "ExamplePlayer",
    "names": ["ExamplePlayer"],
    "nicks": ["theoshadow"],
    "nick_count": 1
  }
}
```

## 错误

| 状态码 | `error` | 场景 |
| ---: | --- | --- |
| `400` | `missing_param` | `nick` / `uuid` 都没给 |
| `400` | `bad_prefer` | `prefer` 取值非法（附带 `accepted`） |
| `401` | `missing_key` / `invalid_key` / `key_disabled` | 鉴权失败 |
| `404` | `not_found` | 查不到（附带 `query`，可能附 `tried`） |
| `429` | `rate_limited` | 每 Key 配额 |
| `500` | `internal` | 内部错误 |

## 版本差异

`v1-260925` 与 `v1-261001` 的**请求参数、响应字段、额度完全相同**；
差异只有信封三件套（旧版没有）与文案语言（旧版中文）。
