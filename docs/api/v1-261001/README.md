# API `v1-261001` —— 当前版

**状态：当前最新版。** 不带版本号的路径和 `/v1` 都指向它。

| 项 | 值 |
|---|---|
| 版本号 | `v1-261001`（`YYMMDD` = 2026-10-01 发布） |
| 服务端生成文案 | **英文** |
| 响应信封 | 有 `api_version` / `locale` / `schema` 三个顶层字段 |
| 请求参数 | 与 `v1-260925` **完全相同**，共用同一套[永久参数 ID](../parameter-registry.md) |
| 状态 | 活跃维护 |

> 上一版（中文契约）见 [`v1-260925`](../v1-260925/README.md)。
> 版本总览与维护规则见 [`docs/api/README.md`](../README.md)。

---

## 1. 路径与版本

| 写法 | 实际走的版本 |
|---|---|
| `/api/<端点>` | `v1-261001`（最新） |
| `/api/<端点>/v1` | `v1-261001`（`v1` 是"最新版"的别名，会跟着发版走） |
| `/api/<端点>/v1-261001` | 钉死 `v1-261001` |
| `/api/<端点>/v1-260925` | 钉死旧版（**返回中文契约**，见[差异](../v1-260925/README.md#与-v1-261001-的差异)） |

版本号是路径**最后一段**，所以 `/api/player/card/v1-261001` 解析成端点 `player/card` + 版本 `v1-261001`。
路径末尾多余的 `/` 会被剥掉。

**不认识的版本**（拼错的日期、未发布的未来日期、`/v2` 之类）→

```json
{"ok": false, "error": "unknown_version", "message": "...", "endpoints": ["v1", "v1-261001", "v1-260925"]}
```

HTTP `404`。

> ⚠️ **只有字符串 `v1-260925` 会被当成旧版**（服务端是一次精确字符串比较）。
> 写别的日期（如 `v1-250101`）会被路由接受，但拿到的是**当前版本的行为**，
> 不是那一天的行为。要长期稳定请钉 `v1-261001`。

### 请求方法

- **每个 `/api/<端点>` 都同时接受 `GET` 和 `POST`。**
- `OPTIONS` → `204` 预检（带 CORS 头，不鉴权、不计额度）。
- 其它方法（`HEAD` / `PUT` / `DELETE` / `PATCH`）→ 标准库的 `501` HTML。

### POST + JSON

POST 时请求体按 JSON 解析成一个字典，交给处理函数；**处理函数先看 body 再看 query**。
请求体为空或不是合法 JSON 时按空字典处理，于是自动回退到 query string。

**没有 Content-Type 校验。** body 里的 `key` 也是合法的鉴权写法。

## 2. 鉴权

按以下顺序取第一个非空值（**不合并、不叠加**）：

| 顺序 | 位置 | 参数 ID |
| ---: | --- | ---: |
| 1 | POST body 的 `key` | [1](../parameter-registry.md) |
| 2 | query `?key=` | 1 |
| 3 | query `?apikey=` | [2](../parameter-registry.md) |
| 4 | header `Authorization: Bearer <key>` | [3](../parameter-registry.md) |
| 5 | header `API-Key: <key>` | [4](../parameter-registry.md) |
| 6 | header `X-API-Key: <key>` | [5](../parameter-registry.md) |

- 推荐**请求头**写法，Key 不会进 URL 日志。
- `Bearer` 前缀大小写不敏感。
- 网站短期令牌 `wt1_…` 也能用（绑 IP、TTL 900 秒、自带 60/分钟限额）。

鉴权失败一律 `401`，`error` 取值：`missing_key`、`invalid_key`、`key_disabled`、
`token_expired`、`token_ip_mismatch`、`invalid_token`。

## 3. 响应信封

成功：

```json
{"ok": true, "data": { }, "api_version": "v1-261001", "locale": "en", "schema": 1}
```

失败：

```json
{"ok": false, "error": "missing_param", "message": "..."}
```

个别错误会附带 `query` / `retry_after` / `why` / `endpoints`。
所有响应带 `Access-Control-Allow-Origin: *`。

| 响应头 | 含义 |
|---|---|
| `X-API-Version` | **回显你请求的那一段**（写 `/v1` 就回 `v1`），不是解析后的完整版本号 |
| `X-API-Latest` | 当前最新完整版本号 |
| `X-Quota-Cost` | 见下方[额度](#4-额度与计费) —— **这是理论价，不等于实际扣费** |
| `Retry-After` | 撞限速时的建议等待秒数 |

> 这两个版本头在**正常路由的响应**上都有（含 `401` / `404` / `410` / `429`）。
> **例外**：版本解析失败（`unknown_version`）和裸 `GET /api/hypixel` 的信息响应
> **不带**它们（实测 `X-API-Version` 缺席）。

> 💡 注意 `X-API-Version`（回显请求段）和 body 里的 `api_version`（写死 `v1-261001`）
> **语义不同**，别把两者当成同一个值。

## 4. 额度与计费

### 每把 Key 的配额

- 默认 **120 次/分钟**（滑动 60 秒窗口，`QQBOT_DENICK_RATE`）。
- 管理员可用 `/apikey rate` 按 **Key / QQ 号 / 全局默认**三档调整，**改完立即生效**。
- `0` 表示不限速（此时 `/api/quota` 的 `unlimited: true`、`remaining: null`）。
- 窗口按**加权总量**算，不是简单计数 —— 所以 225 额度能放 150 次 1.5 的请求，
  而不是凑整成 2、只能放 112 次。

### 基础额度

| 端点 | 基础额度 | 体积加权 |
| --- | ---: | --- |
| `/api/denick` | **1** | **否** |
| `/api/search` · `/api/recent` · `/api/nick-history` | **1** | 是 |
| `/api/player` · `/api/tags` · `/api/player/card` | **1.5** | 是 |
| `/api/bancheck` · `/api/checkban` | **UUID 0.7 / 名字 1.0** | 是 |
| `/api/quota` | **0**（免费） | 否 |
| `/api/hypixel` · `/v2/*`（Hypixel 反代） | **1** | 是 |
| `/bjd/v2/*`（Bugland 反代） | **1** | 是 |
| `/api/card.png` | 不扣（已下线） | —— |

> ⚠️ **1.5 只适用于 `/api/player`、`/api/tags`、`/api/player/card` 这三个"本站加工"的接口**，
> 因为它们真的出网打 Hypixel / Urchin / Mojang。**两个反代都是 1。**
> 1.5 = 基础 1.0 + 上游附加 0.5。

### 体积加权

按响应体字节数，**十进制 MB**、严格大于：

| 响应体大小 | 额度 |
| --- | ---: |
| ≤ 3 MB | 1 |
| > 3 MB 且 ≤ 5 MB | 7 |
| > 5 MB | 15 |

**成功响应**（HTTP < 400 且响应体已完整写出）才算体积，失败不追加体积费用。

### `X-Quota-Cost` 的真相（重要）

`X-Quota-Cost` 报的是 **`size_cost(len(body))` 这个理论价**，在**每一个**响应上都会算，
包括 `401` / `404` / `410` / `429`。它**不等于实际扣掉的额度**：

| 情况 | 实际扣费 |
| --- | ---: |
| `401` 鉴权失败 | **0**（Key 校验还没记账就失败了） |
| 每 Key 配额 `429` | **0** |
| 过并发闸门被拒（`busy`） | **0** |
| 全局玩家闸门 `429`（在鉴权之后） | 已扣基础额度 |
| 带合法 Key 的 `404` | 已扣基础额度 |
| `502` 上游失败 | 已扣基础额度，**不追加体积费** |
| `/api/quota` 的任何响应 | **0**（强制） |

也就是说：**别用 `X-Quota-Cost` 当账本**。要准确的额度就调
[`/api/quota`](#9-apiquota)（免费、随时可查）。

> 已知瑕疵：`commands_apikey.py` 里管理员命令的帮助文案还写着旧阈值
> （">1 MB 扣 4 / >5 MB 扣 8"），与实际实现不符 —— 实际是 3 MB / 5 MB → 7 / 15。
> 这是**服务端文案缺陷**，以本文档为准。

## 5. 限速与闸门

三层，互相独立：

| 层 | 默认 | 作用范围 | 能否热改 |
| --- | ---: | --- | --- |
| 每 Key 每分钟配额 | **120/min** | 单把 Key | ✅ `/apikey rate` |
| 全局玩家闸门 `QQBOT_PLAYER_RATE` | **90/min** | 全站，管 `/api/player`、`/api/tags`、`/api/player/card`、`/web/api/player` | ❌ 改环境变量 + 重启 |
| 全局并发闸门 `QQBOT_MAX_CONCURRENCY` | **20** | 全站所有 `/api/*` | ✅ `/apikey rate concurrency` |

另有各反代自己的每分钟闸门（见对应章节）。

- 玩家闸门撞限 → `429` `rate_limited`。
- 并发闸门撞限 → `429` `{"ok": false, "error": "busy", "retry_after": 1}`。
- 两条闸门在**每个** `GET` / `POST` 上都生效。
- 撞限时响应带 `Retry-After` 头，不用自己算退避。

## 6. 端点总表

12 个公开端点，全部同时支持 `GET` 和 `POST`：

| 端点 | 说明 | 基础额度 | 参数 ID |
| --- | --- | ---: | --- |
| [`/api/denick`](./endpoints/denick.md) | 昵称 → 真名 / UUID | 1 | 1–8, 23 |
| [`/api/player`](./endpoints/player.md) | 身份 + 战绩 + 可疑度 + 标签 | 1.5 | 1–5, 9–11 |
| [`/api/player/card`](./endpoints/player-card.md) | 整张卡片的 JSON | 1.5 | 1–5, 9–12 |
| [`/api/tags`](./endpoints/tags.md) | 只要反作弊标签（最轻量） | 1.5 | 1–5, 9–11 |
| [`/api/bancheck`](#10-apibancheck) | 封禁索引查询 | 0.7 / 1.0 | 1–5, 13, 14, 24 |
| `/api/checkban` | **`/api/bancheck` 的别名**，行为完全相同 | 0.7 / 1.0 | 同上 |
| [`/api/search`](./endpoints/search.md) | 昵称 / 真名模糊搜索 | 1 | 1–5, 15–17 |
| [`/api/recent`](./endpoints/recent.md) | 最近记录到的昵称 | 1 | 1–5, 18, 19 |
| [`/api/nick-history`](./endpoints/nick-history.md) | 某昵称的完整出现历史 | 1 | 1–5, 20, 21 |
| [`/api/quota`](#9-apiquota) | 查自己的额度 / 并发 / 限流 | 0 | 1–5 |
| [`/api/hypixel`](#7-hypixel-透明反代) | Hypixel 官方 API 透明反代 | 1 | 1–5, 22 |
| `/api/card.png` | **已下线**，恒回 `410 gone` | —— | 1–5, 12 |

**发现文档**：`GET /api`（不带端点）回端点清单、**全部 24 个参数定义**、
`hypixel_proxy` / `bugland_proxy` 的 base 与鉴权方式。用它做客户端自动发现。

### `/api/card.png`（已下线）

2026-09-25 下线。现在**恒回 `410`**：

```json
{"ok": false, "error": "gone", "message": "…已下线…改用 /api/player/card…"}
```

不读鉴权、不扣额度。想拿卡片数据请用 [`/api/player/card`](./endpoints/player-card.md)。

## 7. Hypixel 透明反代

**Base：`https://hyp-api.firebounce.today`** —— 只换 base URL 就能替换官方 API。

```bash
curl 'https://hyp-api.firebounce.today/v2/player?uuid=<uuid>&key=<你的 bsk_ key>'
```

别名入口 `/api/hypixel/v2/...` 等价（少写 `/v2` 会自动补上）。
**推荐直接用 `hyp-api.firebounce.today`**，少一层跳转。

鉴权用**本站的 bsk_ Key**，不是 Hypixel 的 Key。

| 项 | 值 |
|---|---|
| 单 Key 上游超时 | **12 秒**（每次尝试还会被剩余总预算截断） |
| 最多尝试不同 Key | **3 把** |
| 总预算 | **30 秒**（只覆盖上游尝试，不含写回客户端） |
| 成功缓存 | **固定 300 秒**，最多 **512** 条，先淘汰过期再淘汰最旧 |
| 基础额度 | **1** + 体积加权 |
| 每分钟闸门 | **600/分钟**（全局 `QQBOT_PROXY_RATE`，可热改） |
| POST | **不支持**（只有 GET 被代理） |

### 计费

- **先把响应写好再结算**：等响应体完整写回客户端、且状态码 < 400 之后才按完整额度扣。
- **失败按基础额度的 50%（0.5）计费**，覆盖上游错误、超时、连接失败、客户端写回失败。
- 失败**不追加**体积费用。
- **例外**：鉴权失败（`401` / 配额 `429`）**一分不扣** —— 那时候还没记账。
- **例外**：反代自己的全局闸门 `429` 会按 0.5 结算（预留已经存在）。
- 预留超过 60 秒才结算的话，那条预留已被清掉，结算按 0 处理。

### 缓存规则（哪些能缓存）

**只有**「上游状态码 `200` **且**响应体非空」才进缓存。以下**都不缓存**：

- 任何非 `200`（含 `429` / `401` / `403` / `5xx`）
- 名字冷却期的 `429`（在写缓存之前就返回了）
- `200` 但响应体为空
- 所有网络错误
- **所有 Bugland 响应**（BJD 侧没有缓存）

缓存键是 `name→uuid` 改写、剥掉 `key`/`apikey` 之后的**最终上游 URL**，跨调用方共享。
**命中缓存仍然照常扣 1/7/15** —— 缓存省的是上游时间，不是额度。

### 透传边界（重要）

- **状态码与响应体：逐字节原样转发。**
- **响应头：不是全部转发。** 只带走白名单里的几个：
  `content-type`（缺失时补 `application/json; charset=utf-8`）、
  `ratelimit-limit` / `ratelimit-remaining` / `ratelimit-reset` / `retry-after` / `cache-control`
  （统一改成 `CamelCase`）。
- `Content-Length` 重新计算；额外加上 `Access-Control-Allow-Origin: *` 和 `X-Quota-Cost`。
- **`Set-Cookie`、`Date`、`Server`、`Connection` 以及其余上游响应头全部丢弃。**

> ⚠️ 服务端代码注释里有一句"Hypixel 自己的**所有**响应头都照原样带走"，**这句是错的**。
> 以本节为准。
>
> 另一个已知瑕疵：上游返回 HTTP 错误时，转发出去的 `ratelimit-*` 取自内部
> `_last_headers`，而该变量**只在上游成功时才填** —— 所以错误响应上的
> `ratelimit-*` 可能是空的或上一次的陈旧值。别依赖它判断错误响应的限流状态。

### 错误形状

反代路径上的拒绝与上游失败回 **Hypixel 的形状**：

```json
{"success": false, "cause": "..."}
```

**例外**：裸调 `GET /api/hypixel`（没有子路径可转发）→ HTTP `200`：

```json
{"ok": false, "message": "...", "use": "...", "aliases": ["..."]}
```

### 已知问题

- **`POST /api/hypixel`（裸路径或 `/v1`）会抛 `AttributeError`**（子路径是空字典），
  没有被兜住 —— 客户端拿到的是连接异常而不是文档化的错误响应（服务端会记录一条事故）。
  走 `/api/hypixel/v2/...` 就不受影响。
- `POST /v2/...` 不被代理 → 落到插件路由后回 `404 {"error":"not found","path":...}`，不鉴权不扣额度。
- `POST /api/hypixel/v2/player` → `404 {"ok":false,"error":"not_found"}`。

### 覆盖范围

上游端点与字段**以 [Hypixel 官方文档](https://github.com/HypixelDev/PublicAPI) 为准**。
本站转发所有 `/v2/*`，不维护自己的端点清单 —— 官方新增端点不需要本站改代码。

### `/apikey rate proxy`（管理员）

| 命令 | 效果 |
| --- | --- |
| `/apikey rate proxy` | 查看当前值、来源（环境变量 / 群内设定）与水位 |
| `/apikey rate proxy <N>` | 设为 N/分钟，**立即生效**并落盘（重启仍在） |
| `/apikey rate proxy 0` | 不限速（持久化的"无限"，不是删除设定） |
| `/apikey rate proxy off` | **删除**群内设定，回落到环境变量 `QQBOT_PROXY_RATE` |

优先级：**群内设定 > 环境变量 > 默认 600**。
这个闸门只管反代，**不影响**每 Key 额度、并发闸门，也不影响 Bugland。

## 8. Bugland 透明反代

**Base：`/bjd/v2`** → 上游 `https://api.mcbjd.net/v2/`。

```bash
curl 'https://api.firebounce.today/bjd/v2/player?uuid=<uuid>&key=<你的 bsk_bjd_ key>'
```

| 项 | 值 |
|---|---|
| 对外 Key 前缀 | **`bsk_bjd_`** + 32 位十六进制 |
| 鉴权 | 同[鉴权](#2-鉴权)：`?key=` / `?apikey=` / `Authorization: Bearer` / `API-Key` / `X-API-Key` |
| 方法 | **GET 和 POST 都支持** |
| 基础额度 | **1 次/请求** + 体积加权 |
| 每 Key 限速 | 默认 **30/分钟**（`QQBOT_BJD_RATE`） |
| 每 Key 并发 | 默认 **20**（`QQBOT_BJD_MAX_CONCURRENCY`） |
| 请求体上限 | **4 MiB**，超出回 `413` |
| 缓存 | **无** |

### 与 Hypixel 的独立程度

**Key 体系、上游凭据、配额、限速、状态文件全部独立：**

| | Hypixel | Bugland |
|---|---|---|
| 对外 Key 存哪 | `denick_keys.json` | `bjd_api_keys.json` |
| 上游凭据 | Hypixel Key 池 | `bjd_keys.txt` / `QQBOT_BJD_TOKEN` |
| 限速状态 | `rate_limits.json` | `bjd_rate_limits.json` |
| 每分钟闸门 | 600/分钟（反代闸门） | **不受该闸门管辖**，只有自己的 30/分钟 |
| UUID 查询扣 0.7 | 是（bancheck） | 无关 |

**共用**的只有：进程级**并发闸门**（默认 20，与 Hypixel 共享同一个计数器）、
以及响应写出与扣费通道。

### 计费差异（重要）

Bugland **不是** Hypixel 那套：

- **每笔授权请求先扣满 1 次**，即使随后上游失败 —— **没有 50% 失败折扣**。
- 配额是**整数计**，不是加权小数。
- 体积附加费在**每一个**响应上都会加，**包括 `4xx` / `5xx`**（Hypixel 侧只在成功时加）。
- 体积档位同样是 3 MB / 5 MB → +6 / +14（合计 7 / 15）。

### 错误形状

```json
{"success": false, "cause": "..."}
```

| 状态码 | 场景 |
| ---: | --- |
| `401` | Key 缺失 / 非法（不以 `bsk_bjd_` 开头）/ 已停用 |
| `413` | 请求体超过 4 MiB |
| `429` | 该 Key 额度用完 |
| `502` | 上游失败 |
| `503` | 反代模块或配额存储不可用 |

### 上游 Token 体检（背景）

Bugland 的上游 Token 池会定期体检：

- 目标周期 **3 小时**（`QQBOT_BJD_PROBE_PERIOD`），按 Token 数均匀错开，
  单个间隔不小于 30 秒；首次探测延后 `min(60 秒, 周期)`。
- 探测打 `GET /v2/player?uuid=069a79f4-44e9-4726-a5be-fca90e38aaf5`，超时 15 秒。
- **只有 `401` / `403` 算失败**；`429`、上游错误、网络异常都算"不确定"，**保留** Token。
- 退场要求：初次 `401`/`403` **加上**两次复检（默认等 10 秒、15 秒）**都**失败。
- 退场前备份到 `bjd_tokens_dead.txt` 再移出池子；**环境变量 `QQBOT_BJD_TOKEN` 永不退场**。
- 退场会私聊管理员并记一条事故。

> 注意：上游重试只用**文件里前 3 个** Token（按顺序），不是"最闲的 3 个"。

## 9. `/api/quota`

免费、随时可查，**不进任何每分钟全局闸门**（但**仍然要过进程级并发闸门**）。

```
GET /api/quota
```

响应 `data`：

| 字段 | 含义 |
| --- | --- |
| `key` | 打码后的 Key |
| `window_seconds` | 窗口长度，`60` |
| `per_min` / `per_min_src` | 每分钟配额及其来源（Key / QQ / 全局 / 环境变量） |
| `used` | **`charged + reserved`** —— 已结算 + 在飞预留 |
| `remaining` | 剩余（`per_min - used`）；不限速时为 `null` |
| `weighted` | 是否按体积加权计费，`true` |
| `reset_at` | 窗口重置时间 |
| `unlimited` | 是否不限速 |
| `charged` / `reserved` | 已结算总量 / 在飞预留量 |
| `concurrency` | `{limit, in_flight, src}` |
| `prices` | 各档价格：`base_local` 1、`base_proxy` 1、`base_upstream` 1.5、`size_gt_3mb`、`size_gt_5mb` |
| `self` | `{per_min, used, remaining}` —— 本接口自己的 10/分钟限额 |
| `global_gate` / `proxy_gate` | 两条每分钟闸门的 `{per_min, used}` 水位（**只读报告**，不是本请求消耗的） |

> **为什么 `used` 要把"在飞预留"算进去**：服务端判定超限用的是"已结算 + 预留"。
> 只报已结算会出现"显示还剩 50，但下一个请求立刻 429"。
>
> `global_gate` / `proxy_gate` 两个键在对应水位钩子抛异常时**会缺失** —— 客户端要能容忍。

### 它自己的限速

**10 次/分钟**（`QQBOT_QUOTA_RATE`），按**完整 API Key** 计。
超了回 `429`：

```json
{"ok": false, "error": "rate_limited", "message": "...", "retry_after": 7}
```

带 `Retry-After` 头。**鉴权失败不消耗这个限额**（先鉴权再计数）。
`X-Quota-Cost` 在它的**任何**响应上（`200`/`401`/`429`/`500`）都是 `0`。
`200` 响应还有 `Cache-Control: no-store`。

## 10. `/api/bancheck`

**`/api/checkban` 是它的完整别名**，行为一模一样。

### 数据来源：本地索引，不是官方实时验证

服务端查的是**磁盘上的本地封禁索引**（`bantrack_index.json`），
查询时不打 Discord、也不打 Hypixel。**这不是"官方封禁验证"**。

索引有两个来源，**可信度不同**：

| `source` | 来源 | 可信度 |
| --- | --- | --- |
| `tracker` | tracking 服务器的 `#bans` 消息，带精确的封禁时间戳 | **权威** |
| `hyp_dc` | Hypixel 官方 Discord 的成员昵称解绑启发式（判定条件：`0 < 最后在线 - 解绑时刻 < 60 秒`） | **较低**，是推断 |

`source` 报的是**主来源**（有 tracker 就用 tracker，否则用 hyp_dc），
而 `banned` 字段**只取主来源的结论**。要看全部证据请读 `sources[]`。

### 参数

| 参数 | 说明 |
| --- | --- |
| `uuid` | 玩家 UUID。**扣 0.7** |
| `name` | 玩家名或昵称。**扣 1.0** |
| `nick` | `name` 的别名 |

- **`uuid` 和 `name` 同时给时按 `uuid` 计费（0.7）。** 实际的查找顺序是：
  先看本地索引里有没有这个 UUID，没有才回退用名字。
- **大小写不敏感**：索引按小写存、按 `casefold()` 查。
- GET 只认 query string；POST 认 body 的 `name` / `uuid`，但 **body 里的 `nick` 会被忽略**
  （`nick` 只从 query 读）。
- **不支持 `prefer`**（那是 `/api/denick` 的）。

### 响应字段（`v1-261001`）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `known` | bool | 索引里有没有这个人的记录 |
| `banned` | bool \| null | **仅取主来源结论**；没有记录时是 `null` |
| `state` | string | **机器字段**：`banned` / `not_banned` / `unknown`（**本版新增**） |
| `data_quality` | string | `complete` / `partial` / `no_record`（**本版新增**） |
| `source` | string \| null | 主来源：`tracker` / `hyp_dc` / `null` |
| `sources` | array | 全部证据，每项 `{source, at, banned, gamemode, star, delta}` |
| `banned_at` | number \| null | 主来源的封禁时刻（Unix 秒） |
| `name` / `uuid` / `query` | string | 回显 |
| `cost` | number | 本次扣除的额度 |

> ⚠️ **`banned_days_ago` 不是 `/api/bancheck` 的字段**（老文档没提，别以为有）。
> 它只出现在 [`/api/player/card`](./endpoints/player-card.md) 的 `ban_status` 块里。

### 语义（重要）

- **没有记录 ≠ 没被封。** `banned` 为 `null`、`state` 为 `unknown`、`data_quality` 为
  `no_record`，HTTP 仍然是 `200`。这时响应里**根本没有 `name` / `uuid` / `banned_at` 这几个键**
  （是**缺席**，不是 `null`）。
- **`unknown` 不能被当成"安全"**。客户端应当把 `unknown` 与 `not_banned` 区别显示。
- **机器字段与展示文案不一致（已知瑕疵）**：卡片渲染把**所有非 banned 的状态**都显示成
  `Not banned` / `未封禁`，"数据可能不完整"只写在 Age 那一格。所以**卡片上的
  "Not banned" 可能是 `unknown`** —— 程序判断请一律用 `state` / `data_quality`，
  不要解析展示文案。`/api/bancheck` 本身不产生这段文案，它在
  `/api/player/card` 的 `left[]` 块里。

```json
{
  "ok": true,
  "api_version": "v1-261001",
  "locale": "en",
  "schema": 1,
  "data": {
    "known": true,
    "banned": true,
    "state": "banned",
    "data_quality": "complete",
    "source": "tracker",
    "sources": [{"source": "tracker", "at": 1790473417, "banned": true,
                 "gamemode": "bedwars", "star": null, "delta": null}],
    "banned_at": 1790473417,
    "query": "theoshadow",
    "cost": 0.7
  }
}
```

### 与旧版的差异

`v1-260925` 的响应**没有** `state` 和 `data_quality`（其余字段相同，也没有信封三件套）。

### 额度

基础 **UUID 0.7 / 名字 1.0**，再加体积加权。**没有记录也照扣**（不退费）。

### 错误

| 状态码 | `error` | 场景 |
| ---: | --- | --- |
| `400` | `missing_param` | `name` / `uuid` 都没给。**这个检查在鉴权之前**，所以既没 Key 又没参数时回 `400` 而不是 `401` |
| `401` | `missing_key` / `invalid_key` / `key_disabled` | 鉴权失败 |
| `429` | `rate_limited` | 配额或闸门 |
| `500` | `internal` | 内部错误 |

## 11. 英文与本地化规则

`v1-261001` 的**服务端生成文案是英文**。具体边界：

**会被翻译**（服务端自己产生的文本）：

- 错误 `message`（例如"name or uuid is required"）
- `/api/player/card` 里各块的 `title` / `note` / 单元格 `label` / 说明行
- 封禁块、反作弊结论、页脚、状态文案
- 对局结果的展示词（`今天` / `昨天` 之类）
- 披风来源标签（`OptiFine 披风` → `OptiFine cape`）

**不会被翻译**（原样透传）：

- **玩家名、历史昵称、UUID**
- **公会名与公会 tag**
- **披风名**（来自 NameMC 目录的原始名）
- **反作弊标签的内容**（Urchin 返回的原始标签名与备注）
- **上游第三方字段**（Hypixel / Bugland / Urchin 的原始字段与值）
- 社交账号、昵称列表等原样数据

> ⚠️ **已知瑕疵：不是所有错误 `message` 都被翻译。** 实测（无凭据探测）：
>
> | `error` | `message` 实际语言 |
> | --- | --- |
> | `missing_param`（bancheck） | **英文** ✔ |
> | `missing_key`（`401` 系列） | **中文** ✘ |
> | `gone`（`410`） | **中文** ✘ |
>
> 也就是说 `locale: "en"` 之下**仍会出现中文 `message`**。
> 客户端**不要**按文案语言分支，一律按 `error` 代码判断。
> 这与"服务端生成文案是英文"的总体承诺有出入，属服务端待修项。

### 客户端怎么自己翻译

拿**稳定的机器字段**做本地化，不要解析英文/中文文案：

| 用途 | 用哪个字段 |
| --- | --- |
| 封禁状态 | `data.state`（`banned` / `not_banned` / `unknown`） |
| 数据完整度 | `data.data_quality` |
| 封禁来源 | `data.source` 与 `data.sources[].source` |
| 错误分类 | 顶层 `error`（`missing_param` / `not_found` / `rate_limited` / …） |
| 与"未知"区分 | `data.known` + `data.banned`（`null` 表示无结论） |
| 展示用文本 | `data.message`、块里的 `title` / `label` —— **仅供显示** |

地区示例也是英文，例如 `region_guess: [{"region": "Asia", "pct": 10}]`。

## 12. 内部端点（不属于公开 API）

以下路由**存在但不是公开 API**，不要写进客户端，也不在 `GET /api` 的端点清单里：

- **网站后端**：`/web/api/token`、`/web/api/player`、`/web/api/card`、`/web/api/search`
  （同源调用，各有自己的 IP 级限速）
- **网关回调**：`/internal/*`、`/qqbot/internal/*`（需要内部令牌）
- **管理运维**：`/groups`、`/panel`、`/card`、`/report`、`/broadcast`、`/health`、`/healthz`
  （令牌保护，可能随时变更）

**旧别名** `/denick/api` 等价于 `/api/denick`（`GET` + `POST`），为兼容历史客户端保留。

## 13. 错误码总表

| `error` | 状态码 | 含义 |
| --- | ---: | --- |
| `missing_param` | 400 | 缺必填参数 |
| `bad_prefer` | 400 | `prefer` 取值非法（会附带 `accepted`） |
| `missing_key` | 401 | 没提供 Key |
| `invalid_key` | 401 | Key 非法 |
| `key_disabled` | 401 | Key 被停用 |
| `token_expired` | 401 | 网站短期令牌过期 |
| `token_ip_mismatch` | 401 | 令牌绑的不是你这个 IP |
| `invalid_token` | 401 | 令牌非法 |
| `not_found` | 404 | 查不到（附带 `query`，有时附 `tried`） |
| `unknown_version` | 404 | 版本号不认识（附带可用版本） |
| `gone` | 410 | `/api/card.png` 已下线 |
| `rate_limited` | 429 | 配额或限速 |
| `busy` | 429 | 并发闸门满 |
| `internal` | 500 | 内部错误 |
| `upstream_failed` | 502 | 上游失败（附带 `query`） |

## 14. 缓存

| 数据 | TTL | 备注 |
| --- | --- | --- |
| `/api/player/card` JSON | **90 秒**新鲜，**1800 秒** stale-while-revalidate | 最多 **64** 条；**只缓存"健康"的卡片** |
| Hypixel 反代响应 | **固定 300 秒** | 最多 512 条；只缓存`200` + 非空体 |
| Bugland 反代 | 无 | —— |
| `/api/denick` / `search` / `recent` / `nick-history` | 无 | 直查本地索引，本来就快 |
| `/api/quota` | 无 | `Cache-Control: no-store` |

`/api/player/card` 另外在响应里返回 `cached`（bool）、`cache_age`（秒），
以及仅当处于 stale 时出现的 `stale: true`。
"健康"的定义是**没有 `warn` 且 `hyp_ok` 不为 `false`**；不健康的条目会被丢弃重新查，
失败的响应**永不入缓存**。

## 15. 实施基线

本文档核对自服务实现仓库 **`bedkillerspacex-boop/bsk-qqbot`**：

| 项 | 值 |
|---|---|
| 核对提交 | `58c78eccff6cd60621d8da0fbc60021ee498c6c0`（`58c78ec`） |
| 该提交下最新代码提交 | `38b046d` |
| 生产发布 ID | `20261002054735-d9fe0d46e2` |
| 核对日期 | 2026-10-02 |

**代码与本文档冲突时以代码为准。** 改动路由、参数、响应、额度、限速、缓存或文案语言时，
必须**在同一次变更里**更新本文档与 [`../parameter-registry.md`](../parameter-registry.md)，
并遵守 [`../README.md`](../README.md) 的维护规则。
