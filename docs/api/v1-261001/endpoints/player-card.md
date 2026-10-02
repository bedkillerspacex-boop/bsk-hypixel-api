# `/api/player/card` —— 整张卡片的 JSON

> 通用规则见[当前版契约](../README.md)。

| 项 | 值 |
|---|---|
| 方法 | **`GET` 和 `POST`** |
| 路径 | `/api/player/card`、`/api/player/card/v1`、`/api/player/card/v1-261001`、`/api/player/card/v1-260925` |
| 基础额度 | **1.5** |
| 体积加权 | **是** |
| 每分钟闸门 | **全局玩家闸门 90/分钟** |
| 缓存 | **90 秒新鲜 / 1800 秒 stale-while-revalidate / 最多 64 条** |

返回**卡片的全部数据**（两列所有块 + 皮肤/披风），但**不渲染图片** ——
图片端点是已下线的 `/api/card.png`。

## 请求参数

| ID | 参数 | 位置 | 必填 |
| ---: | --- | --- | --- |
| [9](../../parameter-registry.md) | `name` | query/body | 否 |
| [10](../../parameter-registry.md) | `uuid` | query/body | 否 |
| [11](../../parameter-registry.md) | `nick` | **query** | 否 |
| [12](../../parameter-registry.md) | `q` | **query** | 否 |

至少要给一个，都没有 → `400 missing_param`。
解析顺序同 [`/api/player`](./player.md)。

## 缓存行为

- 缓存键是 `"<legacy:|modern:|>" + 小写化 UUID` —— **两个版本的缓存分开**，
  不会互相污染。
- 新鲜期 **90 秒**；过期后在 **1800 秒**内仍可直接返回并**后台刷新**。
- 最多 **64** 条。
- **只有"健康"的卡片入缓存**：定义是**没有 `warn` 且 `hyp_ok` 不为 `false`**。
  不健康的条目会被丢弃重新查；**失败的响应永不入缓存**。
- 响应里带 `cached`（bool）、`cache_age`（秒），**仅当处于 stale 时**才有 `stale: true`。
- **命中缓存仍然照常扣 1.5**（对直连 API 的调用而言）。缓存省的是上游时间，不是额度。

## 响应 `data`

顶层：

| 字段 | 说明 |
| --- | --- |
| `name` / `uuid` / `model` | 玩家名、UUID、皮肤模型（`classic` / `slim`） |
| `skin_px` | 皮肤像素尺寸 |
| `avatar` | 头像 data URL |
| `stamp` / `generated_at` | 数据时间戳 / 生成时间 |
| `footer` | 页脚文案（**服务端生成，英文**） |
| `status` | `{online, text, note}` 或 `null` |
| `rename` | `{ok, text}` 或 `null` |
| `warn` | 警告文案（**存在即表示卡片不健康，不会被缓存**） |
| `suspicion` / `legit` / `tags` | 可疑度与标签 |
| `left[]` / `right[]` | 两列的块 |
| `ban_status` | 封禁状态快照，**见下** |

- `left[]`：皮肤、披风、账号 / 改名 / 统计 / 活动 / 社交 / 昵称等块。
- `right[]`：可疑度环、账号、起床战争、空岛战争、决斗、反作弊、公会、最近对局、名称历史等块。

### 块的形状

```json
{
  "kind": "info",
  "title": "Ban status",
  "accent": "#c0392b",
  "key": "ban_status",
  "badge": null,
  "note": null,
  "cells": [{"label": "Status", "value": "Banned", "kind": "text",
             "spans": null, "plain": null, "color": null}],
  "rows": [{"label": "...", "right": "..."}]
}
```

可疑度环是另一种 `kind`：

```json
{"kind": "score", "suspicion": 42, "legit": 58, "color": "#e67e22",
 "caption": "...", "tag_adj": 0, "note": null,
 "parts": [{"label": "...", "value": 12, "level": "high",
            "points": 12, "points_text": "+12", "color": "#e74c3c"}]}
```

### `ban_status`

| 字段 | 说明 |
| --- | --- |
| `state` | `banned` / `not_banned` / `unknown` |
| `known` | 索引里有没有记录 |
| `source` | 主来源：`tracker` / `hyp_dc` |
| `banned_at` | 封禁时刻（Unix 秒） |
| `banned_days_ago` | **距今天数** —— 这个字段**只在这里有**，`/api/bancheck` 没有 |
| `data_quality` | `complete` / `partial` / `no_record` |

> ⚠️ **`ban_status` 在 `v1-260925` 下不返回** —— 旧版卡片没有这一块。
> 判断封禁请优先用 [`/api/bancheck`](../README.md#10-apibancheck) 的机器字段。

## 尺寸与限制

- `left[]` / `right[]` 的**块数量不固定** —— 数据缺失的块会被省略。
- 文案字段（`title` / `label` / `note` / `footer` / `caption`）是**服务端生成的英文**；
  玩家名、公会名、披风名、反作弊标签内容是**原样数据**。
  客户端本地化请依据 `kind` / `key` / `state` 等稳定字段，**不要解析文案**。

## 示例

```bash
curl 'https://api.firebounce.today/api/player/card?name=ExamplePlayer' \
  -H 'X-API-Key: bsk_...'
```

```json
{
  "ok": true,
  "api_version": "v1-261001",
  "locale": "en",
  "schema": 1,
  "data": {
    "name": "ExamplePlayer",
    "uuid": "00000000000000000000000000000001",
    "model": "slim",
    "cached": false,
    "cache_age": 0.0,
    "footer": "BSK Player profile · Hypixel / Urchin / NameMC / Mojang",
    "ban_status": {"state": "banned", "known": true, "source": "tracker",
                   "banned_at": 1790473417, "banned_days_ago": 3,
                   "data_quality": "complete"},
    "left": [{"kind": "info", "key": "ban_status", "title": "Ban status",
              "cells": [{"label": "Status", "value": "Banned"},
                        {"label": "Age", "value": "3 days ago"}]}],
    "right": []
  }
}
```

## 错误

| 状态码 | `error` | 场景 |
| ---: | --- | --- |
| `400` | `missing_param` | 四个参数都没给 |
| `401` | 鉴权系列 | —— |
| `404` | `not_found` | 查不到（附带 `query`） |
| `429` | `rate_limited` | 每 Key 配额或玩家闸门 |
| `500` | `internal` | 内部错误 |
| `502` | `upstream_failed` | 上游失败（附带 `query`） |

## 版本差异

| | `v1-261001` | `v1-260925` |
|---|---|---|
| `ban_status` 块 | **有** | **无** |
| 文案语言 | 英文 | 中文 |
| 信封三件套 | 有 | 无 |
| 缓存 | 两版**分开缓存** | 同上 |
