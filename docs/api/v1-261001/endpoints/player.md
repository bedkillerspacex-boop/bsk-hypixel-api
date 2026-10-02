# `/api/player` —— 玩家资料聚合

> 通用规则见[当前版契约](../README.md)。

| 项 | 值 |
|---|---|
| 方法 | **`GET` 和 `POST`** |
| 路径 | `/api/player`、`/api/player/v1`、`/api/player/v1-261001`、`/api/player/v1-260925` |
| 基础额度 | **1.5**（= 基础 1.0 + 上游附加 0.5） |
| 体积加权 | **是** |
| 每分钟闸门 | **全局玩家闸门 90/分钟**（`QQBOT_PLAYER_RATE`，不可热改） |
| 缓存 | 无 |

**这个接口真的会出网**打 Hypixel、Urchin、Mojang，所以是 1.5。

当前 `region_guess[]` 未递归翻译，region 仍可能为中文 `亚洲`；客户端可自行显示为 `Asia 10%`。不能依赖 `locale: en` 推断该数组的语言。

## 请求参数

| ID | 参数 | 位置 | 必填 |
| ---: | --- | --- | --- |
| [9](../../parameter-registry.md) | `name` | query/body | 否 |
| [10](../../parameter-registry.md) | `uuid` | query/body | 否 |
| [11](../../parameter-registry.md) | `nick` | **query** | 否 |

三者至少要给一个，都没有 → `400 missing_param`。

解析顺序：**UUID → Mojang 正版 ID → denick 索引里的昵称**。

## 处理顺序（影响你看到的错误）

1. 鉴权 + 扣 **1.5**（先扣）
2. 全局玩家闸门 → 可能 `429 rate_limited`
3. 目标校验 → 可能 `400 missing_param`
4. 出网查询 → 可能 `404 not_found` / `502 upstream_failed`

**所以 `429` 闸门是在扣费之后判的** —— 撞闸门时基础额度已经扣掉。

## 响应 `data`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `query` | string | 你查的那个值 |
| `uuid` | string | 带横线 UUID |
| `uuid_raw` | string | 无横线小写 UUID |
| `name` | string | 解析出的正版 ID |
| `name_source` | string | 名字是怎么来的：`uuid` / `mojang` / `denick` / `none` |
| `rank` | string \| null | 服务器 Rank（如 `MVP++`） |
| `network_level` | number \| null | 服务器等级 |
| `online` | bool \| null | 是否在线（拿不到时 `null`） |
| `game` / `mode` | string \| null | 当前游戏 / 模式 |
| `guild` | object \| null | `{name, tag, members}` |
| `tags` | array | 反作弊标签 |
| `country` / `ping_ms` / `ping_region` | —— | 地区与延迟（拿不到时缺省或 `null`） |
| `region_guess` | array \| null | `[{region, pct}]`，例如 `{"region": "亚洲", "pct": 10}` |
| `names` | array | 已知正版名 |
| `name_history` | array \| null | `[{name, ts}]` |
| `bedwars` | object \| null | 见下 |
| `suspicion` | object \| null | `{score, legit, tag_adjust, parts}` |
| `nicks` / `nick_details` / `nick_count` | —— | 昵称相关 |
| `denick` | object \| null | `{first_seen, first_ts, last_seen, last_ts, records}` |
| `sources` | object | 每个上游的 `"ok"` 或错误字符串 |

`bedwars`：`{level, wins, losses, games, fkdr, wlr, bblr, final_kills, final_deaths,
beds_broken, beds_lost, clutch_rate, winstreak}`。

> 💡 **`online` / `bedwars` / `suspicion` 等字段可能是 `null`** —— 表示"这次没拿到"，
> **不等于 0 或否**。`sources` 会告诉你哪个上游出了问题。
> 服务端明确不做"空结果推断"：Hypixel 对有数据的号也会偶发返空。

## 示例

```bash
curl 'https://api.firebounce.today/api/player?name=ExamplePlayer' \
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
    "uuid_raw": "00000000000000000000000000000001",
    "name": "ExamplePlayer",
    "name_source": "mojang",
    "rank": "MVP++",
    "network_level": 233.08,
    "online": true,
    "game": "Bed Wars",
    "mode": "Solo",
    "guild": {"name": "Example Guild", "tag": "EX", "members": 42},
    "tags": [],
    "region_guess": [{"region": "亚洲", "pct": 10}],
    "bedwars": {"level": 145, "wins": 1200, "losses": 900, "games": 2100,
                "fkdr": 5.43, "wlr": 1.33, "bblr": 2.1, "final_kills": 12189,
                "final_deaths": 2244, "beds_broken": 6732, "beds_lost": 4392,
                "clutch_rate": 0.12, "winstreak": 1},
    "sources": {"hypixel": "ok", "urchin": "ok", "mojang": "ok"}
  }
}
```

## 错误

| 状态码 | `error` | 场景 |
| ---: | --- | --- |
| `400` | `missing_param` | 三个参数都没给 |
| `401` | 鉴权系列 | 见[契约](../README.md#2-鉴权) |
| `404` | `not_found` | 查不到（附带 `query`） |
| `429` | `rate_limited` | 每 Key 配额，或全局玩家闸门 |
| `500` | `internal` | 内部错误（含模块导入失败） |
| `502` | `upstream_failed` | 上游失败（附带 `query`） |

## 版本差异

两版**响应字段相同**（本接口没有 `v1-261001` 专属字段），差异只有信封与文案语言。

## 想只要标签？

用 [`/api/tags`](./tags.md) —— 更轻，但**同样扣 1.5**。想要昵称映射用
[`/api/denick`](./denick.md)（只扣 1）。
