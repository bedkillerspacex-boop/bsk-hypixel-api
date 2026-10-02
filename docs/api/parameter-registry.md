# 永久参数注册表

**每个已注册请求参数有一个永久的数字 ID，它是公开契约的一部分。** 上游透传参数不由本站重新编号。

规则（服务端 `GET /api` 的 `parameter_id_policy` 字段同样声明）：

- ID 按**全局顺序**分配，新参数**只追加**在末尾。
- 已发布的 ID **永不**重新编号、**永不**改含义、**永不**在参数删除后回收给别的参数。
- 删除参数时把它的行标注为已废弃，ID 空缺也不复用。

> ⚠️ **不要自己发明 ID，也不要用 `op1` 这类临时名字。** 表格以服务端
> `bot_core/runtime/api_parameters.py` 为唯一来源；`GET /api` 的 `data.parameters`
> 会回**同一份**注册表（机器可读）。两者不一致属文档缺陷。
>
> **还没注册的参数就是缺口**：如果服务端读取了某个参数但它不在本表里，这是需要修
> 服务端注册表的 bug，**不要**在文档里给它编一个 ID。

## 参数 ID 与响应字段不是一回事

- **参数 ID** 描述"你发过来的那个请求参数"，例如 `14` = 封禁查询用的 `uuid`。
- 响应里的 `id` / `code` / `state` / `source` / `key` 是**业务数据**，各自有独立语义。
- **不要**把响应里的 `state: "unknown"` 跟某个参数 ID 挂钩，也**不要**把
  `data.key`（打码后的 Key）当成参数 ID。

同一个语义参数无论出现在 query string 还是 JSON body，**ID 都是同一个**。
例如封禁查询的 UUID 永远是 `14`，不管你写在 `?uuid=` 还是 POST body 里。
而鉴权的几种写法**各有各的 ID**（1–5），这样客户端能说明自己用的是哪种 wire 形式。

## 注册表

| ID | 注册键 | 线上参数名 | 位置 | 类型 | 必填 | 含义 |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | `auth.key` | `key` | query/body | string | 否 | API Key，写在 query 或 JSON body。 |
| 2 | `auth.apikey` | `apikey` | query | string | 否 | API Key 的旧别名。 |
| 3 | `auth.authorization` | `Authorization` | header | string | 否 | `Bearer` API Key 或网站短期令牌。 |
| 4 | `auth.api_key` | `API-Key` | header | string | 否 | API Key 请求头。 |
| 5 | `auth.x_api_key` | `X-API-Key` | header | string | 否 | API Key 请求头别名。 |
| 6 | `denick.nick` | `nick` | query/body | string | 否 | 昵称、当前名、旧名，或 UUID。 |
| 7 | `denick.uuid` | `uuid` | query/body | string | 否 | 玩家 UUID。 |
| 8 | `denick.prefer` | `prefer` | query/body | string | 否 | 查询顺序：`uuid`、`nick`、`ign`，逗号分隔。 |
| 9 | `player.name` | `name` | query/body | string | 否 | 玩家名、UUID 或昵称。 |
| 10 | `player.uuid` | `uuid` | query/body | string | 否 | 玩家 UUID。 |
| 11 | `player.nick` | `nick` | query/body | string | 否 | 历史昵称。 |
| 12 | `card.q` | `q` | query/body | string | 否 | `/api/player/card` 的 name/UUID/昵称别名。 |
| 13 | `bancheck.name` | `name` | query/body | string | 否 | 玩家名或昵称。 |
| 14 | `bancheck.uuid` | `uuid` | query/body | string | 否 | 玩家 UUID；**扣费更低**。 |
| 15 | `search.q` | `q` | query/body | string | **是** | 搜索词，**至少 2 个字符**。 |
| 16 | `search.query` | `query` | query/body | string | 否 | `q` 的别名。 |
| 17 | `search.limit` | `limit` | query/body | integer | 否 | 返回条数上限。 |
| 18 | `recent.limit` | `limit` | query/body | integer | 否 | 返回条数上限。 |
| 19 | `recent.since` | `since` | query/body | integer | 否 | 只返回此时间戳之后的记录。 |
| 20 | `nick_history.nick` | `nick` | query/body | string | **是** | 要查的昵称。 |
| 21 | `nick_history.limit` | `limit` | query/body | integer | 否 | 历史记录条数上限。 |
| 22 | `proxy.path` | `path` | path | string | **是** | 透传的上游 Hypixel / Bugland 路径。 |
| 23 | `denick.name` | `name` | query/body | string | 否 | `nick` 的别名。 |
| 24 | `bancheck.nick` | `nick` | query/body | string | 否 | `name` 的别名。 |

**24 个 ID，1–24 连续。** 其中 1–5 是鉴权写法，**所有端点共用**。

## 适用版本

参数 ID 本身**跨版本不变** —— `v1-260925` 和 `v1-261001` 用的是同一套 ID，
新增参数时也不会因为版本不同而换号。版本差异只体现在**响应字段**上，
不在请求参数上（例如 `/api/bancheck` 的响应在 `v1-261001` 多了
`state` / `data_quality`，但请求参数完全相同）。

## 各端点使用的 ID

以服务端 `ENDPOINT_PARAMETER_KEYS` 为准，`GET /api` 的 `endpoints[].parameter_ids` 会回同一份：

| 端点 | 参数 ID | 额外参数 |
| --- | --- | --- |
| `/api/denick` | 1–5, 6, 7, 8, 23 | `nick` / `uuid` / `prefer` / `name` |
| `/api/player` | 1–5, 9, 10, 11 | `name` / `uuid` / `nick` |
| `/api/player/card` | 1–5, 9, 10, 11, 12 | 同上 + `q` |
| `/api/tags` | 1–5, 9, 10, 11 | `name` / `uuid` / `nick` |
| `/api/bancheck` · `/api/checkban` | 1–5, 13, 14, 24 | `name` / `uuid` / `nick` |
| `/api/search` | 1–5, 15, 16, 17 | `q` / `query` / `limit` |
| `/api/recent` | 1–5, 18, 19 | `limit` / `since` |
| `/api/nick-history` | 1–5, 20, 21 | `nick` / `limit` |
| `/api/quota` | 1–5 | 无业务参数 |
| `/api/hypixel` · `/bjd/v2/*` | 1–5, 22 | `path`（路径本身） |

> 💡 **注意 `name` 和 `nick` 在不同端点是不同的 ID。** `9` 是 `/api/player` 的 `name`，
> `13` 是 `/api/bancheck` 的 `name`，`23` 是 `/api/denick` 的 `name`（`nick` 的别名）。
> 这**不是**重复：ID 标识的是"哪个端点的哪个语义参数"，同名字段在不同端点上语义不同
> （例如 `/api/bancheck` 的 `name` 会走名字分支、扣 1.0，而不是 0.7）。

## 已知缺口

服务端映射覆盖 `_API_ROUTES` 的 12 项（含别名、下线及说明入口），没有独立 Bugland 映射；发现说明借用了 Hypixel 参数定义。上游的任意 query/body 参数由上游文档定义，不具有本站数字 ID。

注册表 location 不等于处理函数全部支持：ID 23 的 denick.name 只读 query；ID 11 在 player/tags 只读 query，但 card 支持 query/body；ID 12 的 card.q 只读 query；ID 24 的 bancheck.nick 只读 query。文档按处理函数标注实际位置，不修改已发布 ID。

如果后来注册缺失参数，必须先追加服务端注册表，再同步文档，禁止在文档中编造 ID。下面的覆盖声明只针对本站注册路由，不包含任意上游透传字段。

- **`/api/search` 与 `/api/recent` 的 `limit`** 共用参数名但不共用 ID（17 / 18），
  这是有意的：两个端点的钳制范围不同（1–100 vs 1–200）。
- 服务端 `ENDPOINT_PARAMETER_KEYS` 目前覆盖全部 12 个公开端点；
  未发现"代码读了参数但注册表没有"的情况。若将来出现，按上文规则**先补注册表**，
  再同步本文档与 `GET /api`。
