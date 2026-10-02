# BSK Hypixel API

> 📌 **这个仓库里有两个服务，接口格式完全不同，别照抄**：
>
> | 服务 | Base | 格式 |
> |---|---|---|
> | **denick 查询** | `https://api.firebounce.today` | 本站自有 `{ok, data}` 格式，见本文档 |
> | **Hypixel 官方 API 反代** | `https://hyp-api.firebounce.today` | **就是 Hypixel 官方格式** —— 端点和字段以 [官方文档](https://github.com/HypixelDev/PublicAPI) 为准，见[这一节](#hypixel-官方接口反代) |
>
> 给 AI / 爬虫的入口索引另见 [`llms.txt`](./llms.txt)。
>
> 🔌 **不想改代码就想用上反代？** 用
> [`interceptor/`](./interceptor/README.md) —— 一个网络层拦截器，
> 把代码里所有 `api.hypixel.net` 的请求自动改道到反代并自动填 Key，
> **业务代码一行都不用改**。带中文控制面板的油猴脚本、JS 和 Python 三种版本。

把 **Hypixel 昵称（nick）** 反查成 **真实玩家 ID**。

```
Base URL:  https://api.firebounce.today
版本:      /api/<端点>            = 走**最新版**（现在 v1-261001，服务端文案为**英文**）
           /api/<端点>/v1         = "最新版"的别名，会跟着发版走
           /api/<端点>/v1-261001  = **钉死当前版**（接生产用这个）
           /api/<端点>/v1-260925  = 钉死**旧版**（中文契约，已冻结不变）
方法:      GET / POST 都支持；OPTIONS 回 204
Endpoint:  /api/denick          昵称 -> 真名/UUID
           /api/player          身份 + 战绩 + 可疑度 + 标签
           /api/player/card     整张卡片的内容(JSON, 网页靠它渲染)
           /api/tags            只要反作弊标签(最轻量)
           /api/bancheck        查封禁(本地索引, 带来源); /api/checkban 是别名
           /api/search          昵称/真名模糊搜索(本地)
           /api/recent          最近记录到的昵称(轮询)
           /api/nick-history    某个昵称的完整出现历史
           /api/quota           查**你自己**的额度/并发/限流状态(免费)
           (已下线)             /api/card.png 恒回 410 —— 改用 /api/player/card

清单:      GET /api   端点清单 + 版本 + **全部 24 个永久参数 ID 的定义**(机器可读)
文档:      docs/api/  **按版本归档**的契约（当前版 + 冻结的历史版），见下
反代:      https://hyp-api.firebounce.today/v2/...   Hypixel 官方接口原样透传
           /bjd/v2/...                              Bugland 接口原样透传(bsk_bjd_ Key)
           (只换 base url 就能用; 端点和字段**以各自官方文档为准**:
            Hypixel: https://github.com/HypixelDev/PublicAPI)
```

## 文档按版本归档

**同一个 API 有多个版本，各自有独立文档，互不覆盖** —— 老版本永远查得到。

| 版本 | 状态 | 服务端文案 | 文档 |
|---|---|---|---|
| **`v1-261001`** | **当前版** | 英文 | [当前版完整契约](docs/api/v1-261001/README.md) |
| `v1-260925` | **冻结** | 中文 | [历史版说明](docs/api/v1-260925/README.md) · [原文快照](docs/api/v1-260925/REFERENCE.md) |

- 版本总览、路径解析规则、`X-API-Version` 语义、**迁移步骤**：
  [`docs/api/README.md`](docs/api/README.md)
- **24 个永久参数 ID**：[`docs/api/parameter-registry.md`](docs/api/parameter-registry.md)
- 只想快查某个端点：[`docs/api/v1-261001/endpoints/`](docs/api/v1-261001/endpoints/)

> ⚠️ **不写版本号或写 `/v1` 拿到的是当前版（英文文案 + 信封三件套）。**
> 要一直吃中文旧契约就显式写 `/v1-260925`；要钉住现在这一版写 `/v1-261001`。
> 详见[版本化](#版本化)。

> **不是 Hypixel 官方数据**，可能过期或有错。**同名 ≠ 同一人**是常态，见文末 [注意事项](#注意事项重要)。

---

## 目录

- [文档按版本归档](#文档按版本归档) —— **先看这个**：当前版 / 历史版 / 迁移入口
- [申请 API Key](#申请-api-key)
- [鉴权](#鉴权)
- [版本化](#版本化)
- [请求参数 ID（稳定契约）](#请求参数-id稳定契约)
- [网站短期令牌](#网站短期令牌)
- [接口](#接口)
- [返回格式](#返回格式)
- [错误码](#错误码)
- [额度](#额度)
- [示例代码](#示例代码)
- [玩家资料聚合 `/api/player`](#玩家资料聚合-apiplayer)
- [卡片内容 `/api/player/card`](#卡片内容-apiplayercard)
- [其它接口](#其它接口)
- [全局闸门](#全局闸门重要)
- [封禁查询 `/api/bancheck`](#封禁查询-apibancheck)
- [查自己的额度 `/api/quota`](#查自己的额度-apiquota)
- [Hypixel 官方接口反代](#hypixel-官方接口反代)
- [Bugland 接口反代](#bugland-接口反代)
- [注意事项](#注意事项重要)
- [实现基线与维护](#实现基线与维护)

**按端点分册（当前版）**：
[`denick`](docs/api/v1-261001/endpoints/denick.md) ·
[`player`](docs/api/v1-261001/endpoints/player.md) ·
[`player/card`](docs/api/v1-261001/endpoints/player-card.md) ·
[`tags`](docs/api/v1-261001/endpoints/tags.md) ·
[`search`](docs/api/v1-261001/endpoints/search.md) ·
[`recent`](docs/api/v1-261001/endpoints/recent.md) ·
[`nick-history`](docs/api/v1-261001/endpoints/nick-history.md)

---

## 申请 API Key

在 **QQ 群里**（机器人所在的那个群）直接发指令 —— **不用私聊，也私聊不了**：

```
① /apikey 你的QQ号        ->  机器人往 <你的QQ号>@qq.com 发一个 6 位验证码
② /apikey verify 654321   ->  验证通过, 申请进入管理员审批队列（同样在群里发）
③ 管理员同意后             ->  Key 发到你的 QQ 邮箱
```

> 💡 **不知道从哪下手就直接发 `/apikey help`** —— 机器人会把上面这套步骤、常见问题
> 和管理员命令一条条列出来（管理员还会多看到一段 `/apikey rate` 限速配置的用法）。
> 只发 `/apikey`（不带参数）出来的也是同一份说明。

> ⚠️ **全程走 QQ 邮箱，Key 不在 QQ 里发。**
> 机器人的私聊**只对管理员开通**（管理员在白名单里 —— 实测审批通知能私聊送达），
> **普通申请人收不到机器人的私聊**，所以：
>
> - **不要私聊机器人** —— 指令在群里发就行（第 ① ② 步都是）
> - Key **不会**出现在群里（明文会被所有人看到），也**不会**私聊推给你
> - 唯一能送到任意申请人的通道是 **QQ 邮箱**：`<你填的QQ号>@qq.com`
> - 提交申请后**会私聊通知管理员**（消息里直接带 `approve` / `deny` 指令）；
>   万一一条都没发出去（没配管理员 / 额度用完），群里也会提示一句，
>   管理员也可以随时发 `/apikey pending` 主动查队列

- **必须提供真实 QQ 号**：QQ bot 平台只给 openid、拿不到 QQ 号，所以让你自己填，
  再用邮件验证，确保申请人身份是真的
- **同一个人只发一把 Key**：已经有的再申请还是同一把（不会重复签发）
- Key 丢了：**在群里再发一次 `/apikey`**（或 `/apikey 你的QQ号`），会重新发到你的邮箱
- 管理员：`/apikey pending` 看待审、`/apikey approve <编号>` 同意、`/apikey list` 看已发出的 Key、
  `/apikey revoke <key>` 停用、`/apikey rate` 调额度（见 [额度](#额度)）

### 查某个人：`/apikey status`

不带参数 = 看自己（**已经有 Key 的话会直接告诉你掩码**，不再误报"你还没申请过"）：

```
/apikey status
```

带参数 = 查那一个人。参数可以是 **QQ 号 / openid / Key / Key 掩码 / 申请编号** 任意一种
（普通人只能查自己，管理员能查任何人）：

```
/apikey status 123456789
/apikey status 74E421647E938DFC52140A8F75244892
/apikey status bsk_a1b2…9f3c
/apikey status 03a5
```

会一次性列出：openid、这个人的所有 Key（含启用状态 / 用量）、最近的申请、
**实际生效的额度**，以及任何"哪里不对"的提示。查不到时会**说明为什么**，
不会只回一句"没查到"。

### QQ 号和 openid 的对应关系：`/apikey bind`

平台只给 openid，从不给 QQ 号 —— 而**按 QQ 号配的限速必须先把 QQ 绑到人身上才生效**。
绑定的可信来源只有两个：申请人自己的**邮箱验证码**（发 `/apikey 你的QQ号` →
`/apikey verify <验证码>` 即可，走完就自动绑上），或者管理员手动绑：

```
/apikey bind 123456789 bsk_a1b2…9f3c     # 把 QQ 号绑到这个 Key 的人身上
/apikey unbind 123456789                  # 解绑
```

> ⚠️ **一个 QQ 号只能属于一个人。** 已经绑给别人时会直接拒绝，不会静默覆盖 ——
> 要改先 `unbind`。
>
> 💡 如果 `/apikey rate <QQ号> <次数>` 配完发现**没生效**，基本就是这个原因：
> 那个 QQ 号还没绑到任何 Key 上。`/apikey rate` 和 `/apikey list` 都会把这种
> **"配了但不生效"的覆盖显式标出来**。

Key 长这样（下面都是**示例占位**，不是真的）：

```
bsk_00000000000000000000000000000000
```

---

## 鉴权

三种传法任选其一：

| 方式 | 写法 | 建议 |
|---|---|---|
| 请求头 | `Authorization: Bearer bsk_xxx` | ✅ **推荐**（Key 不会进 URL / 访问日志） |
| 请求头 | `X-API-Key: bsk_xxx` | ✅ 可以 |
| 查询参数 | `?key=bsk_xxx` | ⚠️ 方便，但 Key 会出现在 URL 和日志里 |

---

## 版本化

**不带版本号 = 最新版。** 当前最新版是 **`v1-261001`**（服务端文案为英文）。

```http
GET /api/denick?nick=theoshadow              # 最新版（跟着发版走，现在是 v1-261001）
GET /api/denick/v1?nick=theoshadow           # "最新版"的别名（同上，也会跟着变）
GET /api/denick/v1-261001?nick=theoshadow    # 钉死当前版 —— 接生产用这个
GET /api/denick/v1-260925?nick=theoshadow    # 钉死旧版（中文契约，已冻结）
```

| 写法 | 含义 | 什么时候用 |
|---|---|---|
| `/api/denick` | 最新版（`v1-261001`） | 随便写写、临时调 |
| `/api/denick/v1` | **最新版的别名** —— 和上面同一个东西 | 想写明"我用 v1"，但接受它以后会变 |
| `/api/denick/v1-261001` | **钉死 `v1-261001`**，以后改接口它**不动** | **接进生产代码，推荐** |
| `/api/denick/v1-260925` | 钉死**旧版**，返回**中文**旧契约 | 已有集成吃老格式，暂时不动 |

> ⚠️ **`v1` 不等于 `v1-260925`。**
> `v1` 是"最新版"的别名，现在指向 `v1-261001` —— 也就是说**它会返回英文文案
> 和多出来的信封字段**，而不是旧的中文契约。要旧契约就显式写 `/v1-260925`。
>
> 日期是 `YYMMDD`（`260925` = 2026-09-25，`261001` = 2026-10-01），取的是**发布日**。

- 版本号是**路径**最后一段**：`/api/player/card/v1-261001` → 端点 `player/card` + 版本 `v1-261001`
- 所有响应都带 `X-API-Version` 和 `X-API-Latest`。注意 **`X-API-Version` 回显的是你请求的
  那一段**（写 `/v1` 就回 `v1`），不是解析后的完整版本号；body 里的 `api_version`
  才是写死的完整号
- 不认识的版本 → `404 {"error": "unknown_version"}`，并告诉你支持哪些
- `/api`（不带端点）会返回**端点清单 + 全部 24 个参数定义 + 两个反代的 base**，自己发现用；
  每个端点同时给出 `versioned` 和 `alias` 两个版本化地址
- 老路径（`/api/denick`、`/api/player/card` …）**继续可用**，不会因为加版本而失效
- **未来的日期会被拒**（还没发布的），免得你写错一位数字却以为调到了新接口

> 🔴 **只有字符串 `v1-260925` 会被当成旧版。** 服务端判定"走不走旧契约"是一次
> **精确字符串比较**，所以写 `v1-250101` 这类别的日期时路由会接受，但返回的是
> **当前版行为**，不是那一天的行为。别拿任意旧日期当"永久冻结档"。

**版本差异、迁移步骤、以及冻结的历史文档**都在 [`docs/api/`](docs/api/README.md)：

- [版本总览与维护规则](docs/api/README.md)
- [当前版 `v1-261001` 完整契约](docs/api/v1-261001/README.md)
- [历史版 `v1-260925`](docs/api/v1-260925/README.md)（[原文快照](docs/api/v1-260925/REFERENCE.md)）
- [24 个永久参数 ID](docs/api/parameter-registry.md)

---

## 请求参数 ID（稳定契约）

每个请求参数有一个**永久的数字 ID**，是公开契约的一部分：[参数注册表](docs/api/parameter-registry.md)。

- 目前 **24 个，ID 1–24 连续**；1–5 是五种鉴权写法，所有端点共用。
- 规则：**只追加、不复用、不改含义**。删掉的参数它的 ID 也不会被回收。
- `GET /api` 的 `data.parameters` 回**同一份**机器可读注册表，
  `endpoints[].parameter_ids` 给出每个端点用的 ID。
- 参数 ID 标识的是**你的请求参数**；响应里的 `state` / `source` / `code` 是**业务字段**，
  两者无关，不要混用。

```json
{
  "id": 14, "key": "bancheck.uuid", "name": "uuid",
  "location": "query/body", "type": "string", "required": false,
  "description": "Player UUID; lower-cost lookup."
}
```

---

## 网站短期令牌

网站（hyp.firebounce.today）**不给访客发 API Key**，而是按 IP 签一个**短期令牌**：

```http
GET /web/api/token            # 同源，只能从网站调
→ {"ok": true, "token": "wt1_…", "token_type": "Bearer",
   "expires_at": 1790169527, "ttl": 900, "per_min": 60}
```

拿到之后**直接查版本化接口**（不用再走 `/web/api/card` 那道"每 IP 7 秒一次"的闸门）：

```http
GET /api/player/card/v1?name=bsk10ww
Authorization: Bearer wt1_…
```

- **有效期 15 分钟**、**绑 IP**（换网络/过期就重新签一个）、**60 次/分钟**
- 它**不是** API Key：不进 Key 列表、不能被 `/apikey revoke`、到期自动失效
- 签发本身也限速（15 秒 1 个 / 每小时 20 个），防止被拿去刷令牌
- 这个响应**绝不能被缓存**（`Cache-Control: no-store`，服务器侧也禁了 nginx 缓存）：
  令牌是绑 IP 的，一旦被缓存，后来的人拿到的就是**别人签发的旧令牌** → 一律 ip mismatch
- 为什么这么设计：站长的 Key 永远不下发到浏览器；每个访客有自己的额度，所以连查多个玩家
  不会被"每 IP 7 秒一次"卡住（这就是"网页查询慢"的老原因）

---

## 接口

### ① 查一个"名字"（主要用法）

`nick=` 参数**不限于昵称** —— 下面三种都能查，返回体里的 `matched_by` 会告诉你命中的是哪种：

| 传什么 | 例子 | `matched_by` | 说明 |
|---|---|---|---|
| **昵称**（nick） | `?nick=theoshadow` | `nick` | 精确命中某条记录 |
| **真名 / 旧名**（IGN） | `?nick=bsk10ww`、`?nick=Youwy` | `ign` | 命中该玩家的任意一个用过的正版 ID（**含改名前的旧名字**）|
| **UUID** | `?nick=694cd52b8197...` | `uuid` | 32 位十六进制 |

```http
GET /api/denick?nick=<昵称 或 真名 或 UUID>
Authorization: Bearer <Key>
```

> 拿游戏里看到的**真名**反查"他有哪些昵称"是最常用的方向 —— 直接 `?nick=<真名>` 就行。
> 按真名/UUID 查时，`nick` 返回的是该玩家**最新**的那个昵称，`nicks` 是全部。

#### 查询偏好 `prefer` —— 先按哪种查

三种匹配是**不同的人**：某个字符串完全可能既是甲的昵称、又是乙的真名。默认顺序是
`uuid → nick → ign`，想改就加 `prefer`：

| 传什么 | 实际尝试顺序 | 什么时候用 |
|---|---|---|
| 不传 / `prefer=auto` | `uuid → nick → ign` | 默认，和以前一样 |
| `prefer=nick` | `nick → uuid → ign` | 明确"我这是昵称" |
| `prefer=ign` | `ign → uuid → nick` | 明确"我这是真名/旧名"，避免撞上同名的昵称 |
| `prefer=uuid` | `uuid → nick → ign` | 明确"我这是 UUID"（不是 32 位十六进制时这一轮自动跳过，不会误判） |
| `prefer=ign,nick` | 按你给的顺序，没提到的补在后面 | 想完整控制顺序 |

```http
GET /api/denick?nick=shared&prefer=ign
GET /api/denick?nick=shared&prefer=ign,nick
```

- 返回体里的 **`matched_by`** 告诉你这次实际是靠什么命中的（`nick` / `ign` / `uuid`）。
- `prefer` 写错会返回 **400 `bad_prefer`**，并在 `accepted` 里列出可用值。
- 查不到时返回 404，并带上 `tried`（本次按什么顺序试过）—— 便于判断"是不是偏好设错了"。
- **不传 `prefer` 的行为和以前完全一致**，老调用方不受影响。

### ② 用 UUID 反查

```http
GET /api/denick?uuid=<UUID>
X-API-Key: <Key>
```

UUID **带不带横线都行**（`694cd52b-8197-45f0-b28d-ad73eb299699` 与
`694cd52b819745f0b28dad73eb299699` 等价）。

### ③ POST + JSON

```http
POST /api/denick
Content-Type: application/json
Authorization: Bearer <Key>

{"nick": "theoshadow"}
```

也可以用 body 里的 `key` 字段代替请求头：`{"key": "bsk_xxx", "nick": "theoshadow"}`

---

## 返回格式

### 成功 `200`

```json
{
  "ok": true,
  "api_version": "v1-261001",
  "locale": "en",
  "schema": 1,
  "data": {
    "nick": "theoshadow",
    "ign": "bsk10ww",
    "uuid": "694cd52b819745f0b28dad73eb299699",
    "seen_at": "2026-08-28 10:56",
    "seen_ts": 1787885782,
    "first_seen": "2026-08-20 21:52",
    "first_ts": 1787233926,
    "names": ["bsk10ww"],
    "nicks": ["theoshadow", "..."],
    "nick_count": 1
  }
}
```

> 💡 **`api_version` / `locale` / `schema` 三个顶层字段是 `v1-261001` 新增的**，
> `v1-260925` 没有它们。写严格 schema 校验的客户端要允许这三个字段出现。
> `locale` 说明服务端生成文案的语言（当前恒为 `en`）。
> 详细差异见[历史版说明](docs/api/v1-260925/README.md#与-v1-261001-的差异)。

| 字段 | 类型 | 说明 |
|---|---|---|
| `nick` | string | 昵称（原样，大小写按记录里的）。按真名/UUID 查时返回该玩家**最新**的昵称 |
| `matched_by` | string | 本次是靠什么命中的：`nick` / `ign`（真名或旧名）/ `uuid` |
| `current_name` | string \| null | **当前名** = 最近一次被记录到的正版 ID。按旧名查时 `ign` 回显的是你查的那个旧名，想要"他现在叫什么"就看这个 |
| `ign` | string | 真实正版 ID |
| `uuid` | string \| null | 真实玩家 UUID，**无横线小写**；记录里没有时是 `null` |
| `seen_at` | string | 这条记录**最后一次**出现的时间（本地时区 `YYYY-MM-DD HH:MM`）。**不是同步时间** |
| `seen_ts` | number | 同上，Unix 时间戳（秒）。判断"这 nick 多久没出现了"用它 |
| `first_seen` | string \| null | 这条记录**第一次**出现的时间 |
| `first_ts` | number \| null | 同上，Unix 时间戳（秒） |
| `names` | string[] | **同一个 UUID 用过的所有正版 ID**（含旧名），**按最近被记录到的时间倒序**（`names[0]` 就是 `current_name`）|
| `nicks` | string[] | 同一个 UUID 用过的所有昵称（按时间倒序，最新的在前） |
| `nick_count` | number | `nicks` 的条数 |

查询**大小写不敏感**：`nick=THEOSHADOW` 与 `nick=theoshadow` 等价。

> ### ⚠️ 用 `uuid` 做标识，不要用 `ign`
>
> **UUID 不会变，正版 ID 会变。** 实测 39348 条记录里，**650 个 UUID 对应过多个 IGN**
> （同一个玩家改过名），例如：
>
> ```
> uuid 1998680f818c47d09307aa8c1a4f5b3c
>   names: ["HIB0BA", "eflaesunhiagh", "Youwy"]
>   nicks: 113 个
> ```
>
> 所以：
> - 要判断"两条记录是不是同一个人" → **比 `uuid`**
> - 要长期跟踪一个玩家 → **存 `uuid`**，别存 `ign`（他改名后你就找不到了）
> - `ign` 只适合用来显示 / 手动搜索

### 失败

统一是 `{"ok": false, "error": "<错误码>", "message": "<中文说明>"}`：

```json
{
  "ok": false,
  "error": "not_found",
  "message": "索引里没有这个昵称/UUID",
  "query": "zzz_nope",
  "tried": ["uuid", "nick", "ign"]
}
```

`tried` 是本次实际尝试过的匹配方式（受 `prefer` 影响）—— 查不到时先看它，就能判断
是"真没有"还是"偏好设歪了"。`prefer` 写错时则是 `bad_prefer` + `accepted`：

```json
{
  "ok": false,
  "error": "bad_prefer",
  "message": "prefer 只能是 uuid/nick/ign（或 auto）; 不认识: nope",
  "accepted": ["uuid", "nick", "ign"]
}
```

---

## 错误码

| HTTP | `error` | 意思 | 怎么处理 |
|---|---|---|---|
| 400 | `missing_param` | 既没给 `nick` 也没给 `uuid` | 补参数 |
| 400 | `bad_prefer` | `prefer` 写了不认识的值 | 看响应里的 `accepted`（`uuid` / `nick` / `ign`），或直接不传 |
| 401 | `missing_key` | 没带 Key | 加 `Authorization` 头 |
| 401 | `invalid_key` | Key 不存在 | 检查 Key 有没有抄错 |
| 401 | `key_disabled` | Key 被管理员停用了 | 找管理员重新申请 |
| 404 | `not_found` | 索引里没有这个昵称/UUID | 可能没被记录过，或拼错了；响应里有 `tried` 说明本次试过哪些方式 |
| 429 | `rate_limited` | 超过额度 | 退避重试（见下） |
| 500 | `internal` | 服务内部错误 | 稍后重试 |

---

## 额度

**每把 Key 默认 225 / 分钟**，超过返回 `429`。

> ⚠️ **这个数字是"当前线上值"，不是固定出厂值** —— 管理员可以随时用
> `/apikey rate default <次数>` 改（改完立刻生效，不用重启）。
> 想知道**此刻**真正生效的数字，发 `/apikey rate`（列出全局默认 + 所有覆盖），
> 或 `/apikey status <QQ号>` 看某个人实际拿到多少。
> （代码里的出厂默认是 120，线上被调到了 225。）
>
> 💡 **写程序的话不用去群里问** —— 直接调 [`GET /api/quota`](#查自己的额度-apiquota)，
> 它回的就是**你这把 Key 此刻生效的额度、已用、剩余、并发水位**，而且**免费**。

### 打了上游的接口扣 1.5

不是所有接口一样贵。**每次要真的出网打 Hypixel / Urchin 的**，一次扣 **1.5**；
纯本地查索引的扣 **1**：

| 接口 | 出网？ | 扣多少 |
|---|---|---|
| `/api/denick` | 否（查本地索引） | **1** |
| `/api/search` | 否 | **1** |
| `/api/recent` | 否 | **1** |
| `/api/nick-history` | 否 | **1** |
| `/api/player` | **是**（Hypixel + Urchin + Mojang） | **1.5** |
| `/api/player/card` | **是** | **1.5** |
| `/api/tags` | **是**（Urchin） | **1.5** |
| `/api/bancheck` · `/api/checkban` | 否（查本地封禁索引） | **UUID 0.7 / 名字 1.0** |
| `/api/quota` | 否 | **0**（免费） |
| `/api/hypixel` · `/v2/*`（Hypixel 反代） | 是（转发上游） | **1** |
| `/bjd/v2/*`（Bugland 反代） | 是（转发上游） | **1** |
| `/api/card.png` | —— | 不扣（已下线，恒回 `410`） |

**为什么**：出网的接口要占 Hypixel Key 池的额度、还要等网络（几百毫秒到几秒），
纯本地的查一次索引只要 10~300 毫秒。成本不同，收一样的额度不合理。

> ⚠️ **`hyp-api.firebounce.today/v2/*`（那个反代）不在上面这张表里 —— 它的基础价是 1，不是 1.5。**
>
> 实测（2026-09-26 复查）：`/v2/player` 也是 **cost=1**。
> 1.5 只适用于 `/api/player`、`/api/player/card`、`/api/tags` 这三个**本站加工的**接口。
> 反代是从头到尾的透传、不做解析也不建卡，所以按 1 收。
>
> 反代的**体积加权照样生效**：`resources/skyblock/items` = 15、`bazaar` = 7，
> 而 2.4 MB 的 `skyblock/auctions` 仍是 1（没到 3 MB 那档）。
>
> 另外：**4xx 也扣额度**（401 / 404 实测都是 cost=1）—— 出错不代表没占用资源。
> 唯一不扣的是**根本没到源站**的那类（比如被 Cloudflare 挡下的 403，cost=0）。

> 💡 **额度按总量算，不是按次数** —— 1.5 这种小数会真的累加。所以 225 的额度
> 能放 **150 次** `/api/player`（150 × 1.5 = 225），而不是"必须凑整"。
> 卡到边界上不会浪费：比如额度 10 时能放 6 次（用掉 9.0），第 7 次才超。

### 按响应体积加权

在上面那个基础上，**响应特别大**再多扣（因为带宽 / 内存都是我们出）：

| 响应大小 | 额外扣 | 合计（本地接口 / 出网接口 / 反代） |
|---|---|---|
| ≤ 3 MB | — | **1** / **1.5** / **1** |
| > 3 MB | +6 | **7** / **7.5** / **7** |
| > 5 MB | +14 | **15** / **15.5** / **15** |

> `MB` 按**十进制**算（1 MB = 1,000,000 字节）。边界是**严格大于**：
> 正好 3 MB 不额外扣，正好 5 MB 也只算 3 MB 那档。

**为什么**：`/v2/resources/skyblock/items` 有 **5 MB**，而查一次 `/v2/status`
只有 85 字节。两者在我们这边（带宽 / 内存 / 上游等待）成本差得很远，按次数一刀切
不公平 —— 拿大响应的人会挤占别人的份额。加权之后自然就均衡了。

> 两者是**叠加**的：先定基础价（本站本地 1 / 本站出网 1.5 / 反代 1），再看体积加。
> 所以流媒体接口拉一个 5 MB 的响应扣 **15.5**，反代拉一个 5 MB 的扣 **15**。

每次响应都有 **`X-Quota-Cost`** 头，一眼看到这次花了多少：

```bash
curl -s -D - -o /dev/null -H "API-Key: bsk_你的key" \
  "https://hyp-api.firebounce.today/v2/resources/skyblock/items" | grep -i x-quota-cost
# X-Quota-Cost: 15
```

> 💡 这些 `resources/*` 是**静态资源**（官方文档说几天才更新一次）。
> 要反复用请**本地缓存** —— 不然每拉一次就扣 15。

管理员可以在 QQ 里**按 Key 或按 QQ 号**单独调额度（机器人命令，不用重启服务）：

| 想改谁 | 命令 | 说明 |
|---|---|---|
| 全局默认 | `/apikey rate default 240` | 所有 Key 的默认值（**线上现值 225**，可随时改） |
| 某一把 Key | `/apikey rate bsk_完整的key 600` | 贴完整 Key；也可以**直接复制** `/apikey list` 里的掩码（`bsk_a1b2…9f3c`） |
| 某个 QQ 号 | `/apikey rate 123456789 300` | 认这个 QQ 号 —— **必须先 `/apikey bind` 过，否则不生效** |
| 不限额度 | 填 `0` | 慎用 |
| 删掉这条覆盖 | `/apikey rate bsk_xxx off` | 回到上一级（QQ 覆盖 → 全局默认） |
| 看当前配置 | `/apikey rate` | 列出默认值 + 所有覆盖，并标出**匹配不到 Key、实际不生效**的那些 |

优先级：**具体 Key > 该 Key 的 QQ 号 > 全局默认（现值 225）> 环境变量 `QQBOT_DENICK_RATE`（出厂 120）**。

> ⚠️ **按 QQ 号配的覆盖只有在那个 QQ 已绑到某把 Key 上时才生效。**
> 没绑就是白配 —— 命令会成功返回，但额度一点没变。`/apikey rate` 与 `/apikey list`
> 会把这种覆盖单独列出来提醒你，`/apikey status <QQ号>` 也会直说
> "有一条额度覆盖 N/分，但没有任何 Key 绑在这个 QQ 上，所以它现在不生效"。
> 绑法见 [QQ 号和 openid 的对应关系](#qq-号和-openid-的对应关系apikey-bind)。

接口是**本地索引查询**（不经过 Hypixel / Discord），通常 **30~70ms** 返回。

遇到 `429` 建议退避重试，例如 1s → 2s → 4s。

---

## 示例代码

完整可运行版本在 [`examples/`](examples/) 目录：

- [`denick_curl.sh`](examples/denick_curl.sh) —— curl
- [`denick_client.py`](examples/denick_client.py) —— Python（标准库，无第三方依赖）
- [`denick_client.js`](examples/denick_client.js) —— Node.js 18+

### curl

```bash
export BSK_KEY="bsk_你的key"

# 查昵称
curl -s -H "Authorization: Bearer $BSK_KEY" \
     "https://api.firebounce.today/api/denick?nick=theoshadow"

# 查 UUID
curl -s -H "X-API-Key: $BSK_KEY" \
     "https://api.firebounce.today/api/denick?uuid=694cd52b-8197-45f0-b28d-ad73eb299699"

# 指定先按"真名/旧名"查（这个名字同时也是别人的昵称时，默认会先命中昵称）
curl -s -H "Authorization: Bearer $BSK_KEY" \
     "https://api.firebounce.today/api/denick?nick=shared&prefer=ign"

# POST
curl -s -X POST -H "Authorization: Bearer $BSK_KEY" \
     -H "Content-Type: application/json" \
     -d '{"nick":"theoshadow"}' \
     "https://api.firebounce.today/api/denick"
```

### Python（标准库，无依赖）

```python
import json
import os
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.firebounce.today/api/denick"
KEY = os.environ.get("BSK_KEY", "")


def denick(nick):
    url = API + "?" + urllib.parse.urlencode({"nick": nick})
    req = urllib.request.Request(url, headers={
        "Authorization": "Bearer " + KEY,
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode("utf-8"))


if __name__ == "__main__":
    d = denick("theoshadow")
    if d.get("ok"):
        print(d["data"]["nick"], "->", d["data"]["ign"], d["data"]["uuid"])
    else:
        print("失败:", d.get("error"), d.get("message"))
```

### Node.js 18+

```js
const API = "https://api.firebounce.today/api/denick";
const KEY = process.env.BSK_KEY;

async function denick(nick) {
  const r = await fetch(`${API}?nick=${encodeURIComponent(nick)}`, {
    headers: { Authorization: `Bearer ${KEY}` },
  });
  return r.json();
}

const d = await denick("theoshadow");
console.log(d.ok ? `${d.data.nick} -> ${d.data.ign}` : `失败: ${d.error}`);
```

### 浏览器控制台

接口带了 CORS，可以直接在任意网页的控制台里试：

```js
await (await fetch("https://api.firebounce.today/api/denick?nick=theoshadow", {
  headers: { Authorization: "Bearer bsk_你的key" },
})).json()
```

---

## 玩家资料聚合 `/api/player`

**一次调用拿全**一个人的资料（会访问 Hypixel / Urchin / Mojang / NameMC，带磁盘缓存）。

```http
GET /api/player?name=<名字 或 UUID 或 昵称>
Authorization: Bearer <Key>
```

`name=` 的解析顺序：**UUID → Mojang 正版 ID → denick 索引里的昵称**。

> ⚠️ **同名撞车**：如果一个字符串**既是正版账号又是别人的昵称**（实测 `theoshadow`
> 本身是个正版账号，同时又是 `bsk10ww` 的昵称），这个接口按 **Mojang 真账号**返回。
> 想要昵称映射请用 [`/api/denick`](#接口)。

### 返回

```jsonc
{
  "ok": true,
  "data": {
    "query": "bsk10ww",
    "uuid": "694cd52b-8197-45f0-b28d-ad73eb299699",
    "name": "bsk10ww",
    "name_source": "mojang",
    "rank": "§6[MVP§c++§6]",
    "network_level": 206.62,
    "online": true, "game": "决斗", "mode": null,
    "guild": {"name": "...", "tag": "..."},
    "country": "中国",
    "ping_ms": 201, "ping_region": "亚洲 41% / 大洋洲 29%(大致)",
    "region_guess": [{"region": "亚洲", "pct": 41}, {"region": "大洋洲", "pct": 29}],
    "names": ["bsk10ww"],
    "bedwars": {
      "level": 503, "wins": 2981, "losses": 2278, "games": 5259,
      "fkdr": 3.54, "wlr": 1.309, "bblr": 1.66,
      "final_kills": 8532, "final_deaths": 2410,
      "beds_broken": 4637, "beds_lost": 2797,
      "clutch_rate": 16.3, "winstreak": null
    },
    "suspicion": {"score": 49, "legit": 51, "tag_adjust": 10.0, "parts": [...]},
    "tags": [{"tag_type": "blatant_cheater", "reason": "legitscaff, fastmine", ...}],
    "nicks": ["theoshadow", "oldowl"], "nick_count": 2,
    "denick": {"first_seen": "2026-03-12 01:27", "first_ts": 1773250078,
               "last_seen": "2026-08-28 10:56", "last_ts": 1787885782, "records": 2},
    "sources": {"hypixel": "ok", "status": "ok", "guild": "ok", "tags": "ok",
                "ping": "ok", "country": "ok", "names": "ok"}
  }
}
```

几个要点：

- **`sources`**：每一项的成功/失败原因。**任何一项挂了都不会让整个请求失败** ——
  对应字段给 `null`，`sources` 里写明原因
- **`suspicion.score`**：我们自己的可疑度评分（0~100，越高越可疑），
  `parts` 是每个指标的权重拆解
- **`tags`**：Urchin 的反作弊标签（原始结构，含 `tag_type` / `reason`）
- **`rank`**：带 `§` 颜色代码的原始字符串，客户端自行处理
- **`bedwars.level`** 是 BedWars 等级，`network_level` 是服务器总等级，别搞混
- **`country` / `ping_ms` / `ping_region` / `region_guess`**：`country` 是卡面上显示的那个地区，
  取值优先级 NameMC 机主自设 → 窄语种`(推测)` → 延迟`(大致)`，都拿不到就是 `null`；
  `ping_ms` 是玩家连 Hypixel 的延迟（bordic.xyz，**只有该站跟踪过的玩家才有**，否则 `null`）；
  `ping_region` 是**纯由延迟推出来的大致方位**，想自己权衡可信度、或者想忽略推测时用它
  （2026-09-24 起带实测占比，如 `"亚洲 41% / 大洋洲 29%(大致)"`）；
  `region_guess` 是同一份东西的**结构化版本**，省得你去解析字串：
  `[{"region": "亚洲", "pct": 41}, {"region": "大洋洲", "pct": 29}]`。
  **两种后缀别混**：`(推测)` = 语言→国家，基本一对一；`(大致)` = 延迟区间→一整片大陆，
  只是给个方向（见卡片那一节）。**带后缀的值都不是事实，别当依据。**

  > **百分比怎么来的**：41 个「NameMC 自设国家 + bordic 延迟」的干净样本上算出来的**实测占比**，
  > 只列 ≥ 20% 的地区。**故意不归一到 100%** —— 比如 `≥165ms` 实测是
  > 亚洲 41% / 大洋洲 29% / **非洲 18%** / 其它 12%，只取前二归一就成了「亚洲 58% / 大洋洲 42%」，
  > 读起来像"只可能是这两个"，那是骗人。剩下的百分点就是没列出来的地区。
  > 样本量只有 6/18/17，百分比本身也有几个点的误差。

### 额度与闸门

- 每把 Key **默认 225 / 分钟**（跟 `/api/denick` 共用，且按**响应体积**加权扣，见[额度](#额度)；数值以 `/apikey rate` 为准）
- **额外**还有一道**全局限流**：该接口每分钟最多 **90 次**
  （因为它会真的访问 Hypixel/Urchin，得保护上游配额）→ 超了返回 `429`
- 命中磁盘缓存时很快（毫秒级）；冷查询约 **1~3 秒**

### 错误码

跟 `/api/denick` 相同，另外多了：

| HTTP | `error` | 意思 |
|---|---|---|
| 502 | `upstream_failed` | 上游（Hypixel 等）整体失败，稍后重试 |

---

## 卡片内容 `/api/player/card`

**整张卡片的全部内容**（就是 QQ 机器人 `/hyp` 发出来的那张图上的所有东西）以 JSON 返回。

和已下线的 `/api/card.png` 的区别：**只取数据、不渲染图片**，
所以快得多 —— 省掉了最贵的那步画图。网页版 `hyp.firebounce.today` 就是靠这个接口
把卡片完整画出来的（"把图片搬到网页上"）。

```http
GET /api/player/card?name=<名字 或 UUID 或 昵称>
Authorization: Bearer <Key>
```

`name=` 的解析顺序和 `/api/player` 一样：**UUID → Mojang 正版 ID → denick 索引里的昵称**。

### 返回

```json
{
  "ok": true,
  "data": {
    "name": "Satanify",
    "uuid": "543a48ad-0091-4d54-8c63-d08fffb783c0",
    "model": "slim",
    "skin_px": "64×64",
    "avatar": "data:image/png;base64,iVBOR…",
    "stamp": "2026-09-22 20:50:22 +08:00",
    "generated_at": 1790081422,
    "cached": false,
    "cache_age": 0,
    "footer": "BSK 玩家档案 · Hypixel / Urchin / NameMC / Mojang",
    "status": {"online": true,
               "text": "在线 · 正在玩 密室杀手 · MURDER_DOUBLE_UP",
               "note": "Hypixel 实时状态"},
    "rename": {"ok": true, "text": "可以 (距上次改名 40 天)"},
    "suspicion": 14,
    "legit": 86,
    "tags": [{"label": "Confirmed Cheater", "color": "#cc3333",
              "note": "reason · by someone · 2026-08-01"}],
    "left":  [ "…块…" ],
    "right": [ "…块…" ]
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` / `uuid` | string | 玩家名 / 带横线 UUID |
| `model` | string | `slim`（Alex 细手臂）或 `classic`（Steve） |
| `skin_px` | string \| null | 皮肤贴图分辨率，如 `64×64` |
| `avatar` | string \| null | **头像**（data URL）：只有头 + **帽子层**（第二层皮肤），近正面小角度、透明底，约 152px 宽。我们自己渲染的，不依赖第三方 —— mc-heads 的 `/avatar/` 丢掉帽子层、`/head/` 又转太多（脸是歪的） |
| `stamp` | string | 卡片右上角那个时间戳（**取数时刻**，不是同步时间） |
| `generated_at` | number | 同上，Unix 秒 |
| `cached` | bool | 是否命中下面的 90 秒缓存 |
| `cache_age` | number | 这份数据是几秒前取的（`0` = 刚拉的） |
| `warn` | string \| null | **数据源异常**说明（如 `Hypixel API Key 失效 —— 战绩 / 等级 / 账号信息取不到。不是这号没数据`）。有值时**必须显眼提示**：字段全是 `-` 是**我们取不到**，不是这号没数据 |
| `stale` | bool \| 无 | 只在命中**过期缓存**时出现：`true` = 这份是旧的，后台正在刷新（见下文「缓存与限制」）|
| `status` | object \| null | 在线状态。`null` = 上游没给 |
| `rename` | object \| null | 改名资格（`ok` 为 `null` 表示缺名称历史、无法判断） |
| `suspicion` / `legit` | number | 可疑度 / 可信度（0~100）。只是把 `right` 里那个圆环的值提出来方便直接用 |
| `tags` | object[] | 反作弊标签：`label` / `color`（`#rrggbb`）/ `note`（原因 · 谁加的 · 日期） |
| `left` / `right` | object[] | **左列 / 右列的所有块** |

### 块（`left` / `right` 的元素）

**数组顺序 == 卡片图片上的顺序**，网页照着顺序画就是原图。每个块都有 `kind` / `title`：

| `kind` | 位置 | 字段 |
|---|---|---|
| `skin` | 左 | `image`（data URL）、`note`（`SLIM · 64×64`）、`model`、`size`、`empty_text` |
| `capes` | 左 | **当前穿戴** `worn: {label, image, source}` 、**拥有** `items: [{label, image}]`、`count`、`note`、`empty_text` |
| `score` | 右 | `suspicion`、`legit`、`color`、`caption`、`note`、`tag_adj`、`parts` |
| `account` | 右 | `accent`、`cells`（玩家 Rank / 服务器等级 / 赠送 Rank / 地区 / 语言 / Hypixel延迟）|
| `mode` | 右 | `key`（`bedwars` / `skywars` / `duels`）、`badge`（等级）、`accent`、`cells` |
| `anticheat` | 右 | `text`（`No Record` / 具体标签 / **`查询失败`**）、`color`、`icon`（`check` / `x` / `none`）、`note`、`source`、`tags` |
| `info` | 左右 | `accent`、`cells`（2×2 格：账号信息 / 账号统计 / 近期活动 / 公会）|
| `list` | 左右 | `rows: [{label, right}]`、`note`（右上角小字）|
| `history` | 右 | `rows: [{name, current, ts, date}]`、`note`、`empty_text` |

`score.parts` 是可疑度的逐项拆解：

```json
{"label": "FKDR", "value": "3.65", "level": 0.62, "points": 7,
 "points_text": "+7", "color": "#cc3333"}
```

`level` 是 0~1 的进度（画进度条用），`points` 是这一项给总分贡献了几分
（各项相加 ≈ 总分，不含标签修正）。

### 格子（`cells`）

两种，看 `kind`：

```jsonc
{"label": "服务器等级", "kind": "text", "value": "322.35"}

{"label": "玩家 Rank", "kind": "legacy", "value": "§6[MVP§c++§6]",
 "plain": "[MVP++]",
 "spans": [["[MVP", "#ffaa00"], ["++", "#ff5555"], ["]", "#ffaa00"]]}
```

- `kind: "text"` —— `value` 直接显示
- `kind: "legacy"` —— 带 Minecraft `§` 颜色码的 Rank。**`spans` 已经切好了**（文本 + 颜色），
  直接拿来渲染；`plain` 是去掉颜色码的纯文本；`value` 是原始串
- 值缺失时是 `"-"` —— 跟图片上显示的一致，**不是 `null`**

### 皮肤 / 披风

`skin.image` 和 `capes.*.image` 是 **base64 data URL**（`data:image/png;base64,…`），
可以直接当 `<img src>` 用，不用再请求别的接口。皮肤是 3/4 视角的渲染图（把披风也穿上了，约 16 KB）。

披风块**把"当前穿戴"和"拥有"分开**（这是两件事）：

```json
{"kind": "capes", "title": "披风", "note": "拥有 5 件", "count": 5,
 "worn": [
   {"label": "Migrator", "image": "data:image/png;base64,…", "source": "Minecraft 官方皮肤"},
   {"label": "OptiFine 披风", "image": "data:…",
    "source": "OptiFine（显示时盖住官方那件）"}
 ],
 "items": [{"label": "Builder", "image": "data:…"}, {"label": "Menace", "image": "data:…"}],
 "empty_text": "该账号没有披风"}
```

- **`worn` 是数组 —— 可以有两件**：**官方披风（Mojang）和 OptiFine 披风是同时装备的**，
  只是显示上分客户端：装了 OptiFine 的人看到 OF 那件（它**盖住**官方那件），原版客户端看到官方那件。
  所以两件都标「当前穿戴」，不存在"OptiFine 那件没穿"这回事
- 官方那件以 **Minecraft 官方皮肤属性**为准（实时），名字用像素指纹去"拥有"列表里认
  （Mojang 只给贴图不给名字）—— **只比正面 10×16**：NameMC 的贴图在背面/未用区域跟 Mojang
  不一样（同一件披风整张差 119、正面差 0.00）。`source` 会写清是从哪来的
- ★ 名字是**两级**找的：先在你 NameMC **档案页**的「拥有」列表里找；找不到就去 NameMC 的
  [**全量披风目录**](https://namemc.com/capes)（约 50 件）里按同一套指纹再找一次。
  理由：档案页的 `Capes (N)` 区块**更新有延迟** —— 刚拿到的新披风还没进那份列表，
  只查它就会显示成「未命名披风」（2026-09-29 修）。
  ⚠️ 这个过程**不会**去信档案页标的"当前穿戴"：实测它会把 A 标成 B ——
  给一个**错名字**比「未命名」更糟（前者是假信息）。所以认不出时就是「未命名披风」，不猜
- **`items`** = **拥有**的其余披风（不含正在穿的，避免重复画），可能为空
- `count` = 拥有总数（含正在穿的）；`note` 就是"拥有 N 件"
- 数据源：[NameMC](https://namemc.com) 档案页的 `Capes (N)` 区块（拥有列表 + 谁在穿），
  贴图走 `s.namemc.com`。**laby.net 的 API 现在要 edge challenge token，爬不了**；
  OptiFine 披风是另一套系统（NameMC 不列），它**也在穿戴中**，所以和官方那件并列在 `worn` 里
- 披风贴图有 30 天磁盘缓存；冷启动时若某张缩略图没赶上建卡预算，这一次 `image` 会是 `null`，
  但名字照给，后台线程会把缓存补上（下次就有图）

### 缓存与限制

- 同一个玩家 **90 秒内**直接回缓存（`cached: true`，`cache_age` 是数据年龄）；
  **90 秒 ~ 30 分钟**之间回的是**旧数据 + 后台刷新**（这时会多一个 `stale: true`）——
  也就是 stale-while-revalidate：宁可先给你 90 秒前的数据，也不让你干等一次冷查询
- 网站那条路（`/web/api/card`）在 nginx 上还有一层 **60 秒共享缓存**：
  命中时前端几乎瞬开（响应头 `X-Cache-Status: HIT`），根本不进 Python
- 冷查询 **约 3~5 秒**（要等 Hypixel / Urchin / NameMC 上游）；热缓存 **<50ms**
- 每 Key **默认 225 / 分钟** + **全局闸门 90 / 分钟**（跟 `/api/player` 共用）；
  命中缓存**不吃**这个额度 —— 那 120 是**真的上游取数**配额
- 错误码同 [`/api/player`](#错误码-1)

### 网站内部接口 `/web/api/card`

`hyp.firebounce.today` 用的是**同一份数据**：

```http
GET /web/api/card?name=<名字 或 UUID 或 昵称>
```

- **不需要你在浏览器里带 Key** —— Key 由服务器侧的 nginx 反向代理注入
  （`proxy_set_header Authorization "Bearer …"`），**访客永远看不到它**
- 但服务端**照样要过 Key 校验**，所以那把"网站专用 Key"的额度（现值 225 / 分钟）对整站生效；
  管理员可以用 `/apikey rate` 调它的额度
- **面向访客的限速**是按 IP 做的：**7 秒间隔 + 每分钟 6 次**（跟机器人 `/hyp` 完全一致）
- 只在服务器内部反代（`/web/api/`），不是给第三方用的接口

`/web/api/player` 同规则（也要注入的 Key），`/web/api/search` 不需要（纯本地、按 IP 60 次/分钟）。

---

## 其它接口

所有接口共用同一套 **API Key 鉴权**（`?key=` / `Authorization: Bearer` / `X-API-Key`）
和每 Key 的每分钟额度限制（现值 225，见[额度](#额度)）。

### `/api/tags` —— 只要反作弊标签（最轻量）

```http
GET /api/tags?name=<名字|UUID|昵称>
```

```jsonc
{"ok": true, "data": {
  "name": "bsk10ww", "uuid": "694cd52b-...",
  "tag_types": ["blatant_cheater"],
  "tags": [{"tag_type": "blatant_cheater", "reason": "legitscaff, fastmine", ...}],
  "suspicion": {"score": 49, "legit": 51, "tag_adjust": 10.0},
  "sources": {"tags": "ok", "hypixel": "ok"}
}}
```

只打 Urchin + Hypixel 两次，适合插件做**角标**。命中缓存约 0.2 秒。
同样受全局闸门限制（见文末）。

### `/api/search` —— 模糊搜索（本地，快）

```http
GET /api/search?q=<至少2字符>&limit=20
```

```json
{"ok": true, "data": {"query": "clef", "count": 4, "results": [
  {"nick": "NewLouis", "ign": "clefer", "uuid": "3ac04f4b...",
   "seen_at": "2026-09-21 16:58", "seen_ts": 1789981083, "matched": "ign"}
]}}
```

- 昵称和真名（含旧名）都搜，`matched` 告诉你命中在哪边
- 排序：**前缀命中 > 子串命中**，同档按最近出现倒序
- 纯本地，**约 10 毫秒**

### `/api/recent` —— 最近记录到的昵称（监控流）

```http
GET /api/recent?limit=50&since=<上次的 max_seen_ts>
```

```json
{"ok": true, "data": {
  "count": 5, "since": 0, "max_seen_ts": 1790067491,
  "records": [{"nick": "deadlykill", "ign": "Satanify", "uuid": "...",
               "seen_at": "2026-09-22 16:58", "seen_ts": 1790067491,
               "first_seen": "2026-09-22 16:58"}]
}}
```

轮询用法：把上次拿到的 `max_seen_ts` 当 `since` 传回来，就只拿新的。纯本地。

### `/api/nick-history` —— 某个昵称的完整历史

```http
GET /api/nick-history?nick=<昵称>&limit=200
```

```jsonc
{"ok": true, "data": {
  "nick": "theoshadow", "ign": "bsk10ww", "uuid": "694cd52b...",
  "count": 3,
  "first_seen": "2026-08-20 21:52", "first_ts": 1787233926,
  "last_seen": "2026-08-28 10:56",  "last_ts": 1787885782,
  "channels": [{"channel": "1498800024794955887", "count": 2}, ...],
  "recent": [{"ts": 1787885782, "at": "2026-08-28 10:56",
              "channel": "1477691475578982483", "message_id": "1542729530362302547"}]
}}
```

数据来自**本地消息归档**（拉下来的原始记录，按消息 id 去重），所以是**真实出现记录**，
不是推断。`count` 是出现过几次，`channels` 是各频道分布。纯本地，约 0.3 秒。

### `/api/card.png` —— 已下线

**这个接口没有了，现在返回 `410 gone`。**

```json
{"ok": false, "error": "gone",
 "message": "/api/card.png 已下线: 没人用且每次都要真的渲染 PNG, 太费算力。改用 /api/player/card 拿 JSON(快得多), 或在群里发 /hyp <名字>"}
```

下线原因（2026-09-25）：**没人用**，而且每次调用都要**真的渲染一张 PNG**
（几十 MB 内存 + CPU），纯浪费算力。

想拿卡片图有两条路：

| 想要 | 用什么 |
|---|---|
| 一张图 | 在群里发 `/hyp <名字>`（机器人出图） |
| 自己渲染 | `GET /api/player/card` —— 同样是整张卡片的内容（两列所有块 + 皮肤/披风/头像的 data URL），但**不出图**，快得多 |

> 之所以保留路由回一句 `410` 而不是直接删掉：删了就掉进 `404 查无此路`，
> 调用方分不清是"接口没了"还是"我路径写错了"。

### 全局闸门（重要）

有**两道**全局闸门，别混：

| 闸门 | 默认 | 管谁 | 能否热改 |
|---|---:|---|---|
| **每分钟**玩家闸门 | **90/分钟** | `/api/player`、`/api/player/card`、`/api/tags`、（网站内部 `/web/api/player`） | ❌ 改环境变量 + 重启 |
| **并发**闸门 | **20** | **所有** `/api/*`（含 `/api/quota`） | ✅ `/apikey rate concurrency` |

- **纯本地接口**（`/api/denick`、`/api/search`、`/api/recent`、`/api/nick-history`）
  不受每分钟玩家闸门限制。
- **但没有任何 `/api/*` 能绕过并发闸门** —— `/api/quota` 也一样要排队。
  并发打满时它回 `429 {"ok": false, "error": "busy", "retry_after": 1}`。
- 撞闸门都带 `Retry-After` 头。

---

## 封禁查询 `/api/bancheck`

```http
GET /api/bancheck?uuid=<UUID>
GET /api/bancheck?name=<玩家名或昵称>
```

**`/api/checkban` 是它的完整别名**，行为一模一样。

### 数据来源：本地索引，不是官方实时验证

查的是服务端**磁盘上的本地封禁索引**，查询时不打 Discord、也不打 Hypixel。
**这不是"官方封禁验证"**，也没有实时性保证。

| `source` | 来源 | 可信度 |
|---|---|---|
| `tracker` | tracking 服务器的 `#bans` 消息，带精确封禁时间戳 | **权威** |
| `hyp_dc` | Hypixel 官方 Discord 的成员昵称解绑启发式 | **较低**，是推断 |

`source` 报**主来源**（有 tracker 就用 tracker），`banned` 只取主来源的结论；
要看全部证据读 `sources[]`。

### 参数与额度

| 参数 | 扣费 |
|---|---:|
| `uuid` | **0.7** |
| `name` / `nick` | **1.0** |

- **两个都给时按 `uuid` 计费（0.7）**；查找时先看索引里有没有这个 UUID，没有才回退用名字。
- **名字大小写不敏感。**
- 基础额度之外还有**体积加权**。
- **查不到也照扣**（不退费）。

### 返回

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

| 字段 | 说明 |
|---|---|
| `known` | 索引里有没有这个人的记录 |
| `banned` | `true`/`false`/**`null`**（无记录）；**仅取主来源结论** |
| `state` | **机器字段**：`banned` / `not_banned` / `unknown`（`v1-261001` 新增） |
| `data_quality` | `complete` / `partial` / `no_record`（`v1-261001` 新增） |
| `source` | 主来源 |
| `sources[]` | 全部证据 |
| `banned_at` | 主来源的封禁时刻（Unix 秒） |
| `name` / `uuid` / `query` | 回显 |
| `cost` | 本次扣费 |

> ⚠️ **`banned_days_ago` 不是这个接口的字段。** 它只出现在
> [`/api/player/card`](#卡片内容-apiplayercard) 的 `ban_status` 块里。

### 「没记录」不等于「没被封」

没有命中时 **HTTP 仍然是 `200`**：

```json
{"ok": true, "data": {"known": false, "banned": null, "state": "unknown",
                      "data_quality": "no_record", "source": null,
                      "sources": [], "query": "...", "cost": 1.0}}
```

注意这时响应里**根本没有 `name` / `uuid` / `banned_at` 这几个键**（是缺席，不是 `null`）。

- **`state: "unknown"` 不能被当成安全。** 客户端要把 `unknown` 与 `not_banned`
  区别对待。
- **展示文案不可信**：卡片渲染会把**所有非 banned 的状态**都显示成
  `Not banned` / `未封禁`。所以**卡片上写着 "Not banned" 的可能其实是 `unknown`**。
  程序判断一律用 `state` / `data_quality`，**不要解析文案**。

### 与旧版的差异

`v1-260925` **没有** `state` 和 `data_quality`，只能靠 `known: false` + `banned: null`
判断"无记录"。详见[版本差异](docs/api/v1-260925/README.md#与-v1-261001-的差异)。

### 错误

| 状态码 | `error` | 场景 |
|---:|---|---|
| `400` | `missing_param` | `uuid` / `name` 都没给。**这个检查在鉴权之前** —— 既没 Key 又没参数时回 `400` 而不是 `401` |
| `401` | 鉴权系列 | 见[鉴权](#鉴权) |
| `429` | `rate_limited` | 配额或闸门 |
| `500` | `internal` | 内部错误 |

---

## 查自己的额度 `/api/quota`

```http
GET /api/quota?key=<你的 Key>
```

**查你自己这把 Key 的额度、剩余、并发水位和限流状态。免费，1 秒内返回。**

### 为什么需要它

在这之前，公网**拿不到**任何额度信息 —— 只有响应头 `X-Quota-Cost` 告诉你
"这一单花了多少"。限额是多少、还剩多少、并发水位多少，全部只能在**群里**
（`/apikey rate`、`/apikey status`）或者**服务端本机**（`/health`）看：

| 想知道的 | 以前只能从哪看 | 外部程序能用吗 |
|---|---|---|
| 每 Key 每分钟额度（现值 225 加权） | QQ 群 `/apikey status` | ❌ |
| 并发上限 + 水位（默认 20） | `/health`（本机 `127.0.0.1:18096`） | ❌ |
| 反代全站每分钟（默认 600） | QQ 群 `/apikey rate` | ❌ |
| 这一单花了多少 | `X-Quota-Cost` 响应头 | ✅ |

后果是插件只能**自己把 `X-Quota-Cost` 加起来**：刚重启游戏时显示
`quota: last 0.0 / total 0.0`，用户第一反应是"插件坏了"；而且**没法预判 429**，
只能撞上了再退避 —— 可 429 的三种原因（并发 / 全站 / 自己额度）处理方式
完全不同（等 1~2 秒 / 等 10 秒 / 等 60 秒），以前根本分不清。

### 返回

```json
{"ok": true, "cost": 0, "data": {
  "key": "bsk_efbb…b398",
  "window_seconds": 60,
  "per_min": 225,
  "per_min_src": "default",
  "used": 6.0,
  "remaining": 219.0,
  "weighted": true,
  "reset_at": 1790603500,
  "unlimited": false,
  "charged": 6.0,
  "reserved": 0.0,
  "concurrency": {"limit": 20, "in_flight": 1, "src": "global"},
  "prices": {"base_local": 1, "base_proxy": 1, "base_upstream": 1.5,
             "size_gt_3mb": 7, "size_gt_5mb": 15},
  "global_gate": {"per_min": 90, "used": 12},
  "proxy_gate": {"per_min": 600, "used": 41},
  "self": {"per_min": 10, "used": 1, "remaining": 9}
}}
```

| 字段 | 说明 |
|---|---|
| `per_min` | 你这把 Key **实际生效**的每分钟额度。`0` = 不限 |
| `per_min_src` | 这个值来自哪一档：`key` / `qq` / `default` / `env` / `web_token` —— 报"额度不对"时一秒定位 |
| `used` | 当前 60 秒窗口**已用**（加权后的总量，小数）。`= charged + reserved` |
| `remaining` | `per_min - used`；**不限额度时是 `null`**（配 `unlimited: true`） |
| `charged` / `reserved` | 拆开给：`charged` 是已经花掉的，`reserved` 是**还在飞、马上要花掉的** |
| `reset_at` | unix 秒。窗口里没记录时 = 当前时刻（即"立刻可用"） |
| `weighted` | 恒为 `true` —— 额度按**总量**算，1.5 这种小数会真的累加 |
| `concurrency` | **你自己**的并发档位：上限、此刻在飞数、这个上限来自哪一档 |
| `prices` | 价格表，省得客户端硬编码（和[额度](#额度)那两张表一致） |
| `global_gate` / `proxy_gate` | 两道全站闸门的水位。**只给 `per_min` + `used`** |
| `self` | 查额度这个动作**自己**的水位，见下 |

> ⚠️ **`used` 必须把"在飞预留"算进来。**
> 服务端判定超限时用的是 `已结算 + 在飞预留`，所以快照也只报已结算是错的 ——
> 会出现"显示还剩 50，可下一个请求立刻 429"。两者都算，另外单独给 `reserved`
> 让调用方分得清。

### 特性

- **免费**：`cost: 0`。查额度还要花额度的话就没人敢查了，而且它纯查内存、
  不碰任何外部服务。**不会**把 `used` 推高（否则查一次涨一点，永远看不到真实剩余）。
- **不进任何全站闸门**（并发 / 反代 / player 那三道），所以**随时可查** ——
  哪怕全站正忙、别人正在 429，它照样 200。
- **但它自己有限速**：**每分钟 10 次**，超了回 `429` + `Retry-After`。
  理由：免费又秒回、不设限就是个可以随便刷的洞。
  正常用法（启动查一次 + 撞 429 时查一次）碰不到这个限制；
  被挡时 `self` 字段和 `message` 都会告诉你还剩几秒。
- **`Cache-Control: no-store`**：实时数字，不能被缓存。
- **只回你自己**：坏 Key / 被停用的 Key 一律 `401`，**绝不会** 200 顺手回别人的数据。
  返回里的 `key` 是**打码**的（`bsk_efbb…b398`），不回明文。
- 和别的接口一样支持三种鉴权（`API-Key` / `Authorization: Bearer` / `?key=`），
  也认**网站短期令牌**。
- 支持版本化写法：`/api/quota`、`/api/quota/v1`、`/api/quota/v1-260925`。

### 错误

| 情况 | 状态码 | `error` |
|---|---|---|
| 没带 Key | `401` | `missing_key` |
| 坏 Key / 被停用 | `401` | `invalid_key` / `key_disabled` |
| **查得太频繁**（> 10/分钟） | `429` | `rate_limited`，带 `retry_after` 和 `Retry-After` 头 |
| 不限额度的 Key（`per_min: 0`） | `200` | —— `remaining` 是 `null`，**不报错** |

### 客户端可以拿它做什么

```python
# 启动时查一次, 报告真实剩余（而不是本地估算的 ~219）
q = requests.get("https://api.firebounce.today/api/quota",
                 headers={"API-Key": KEY}).json()["data"]
print("剩余 %s / %s" % (q["remaining"], q["per_min"]))

# 撞了 429 之后, 分清是哪一种, 用不同的退避
#   concurrency limit -> 等 1~2 秒
#   Quota exceeded    -> 等 60 秒
#   Server is busy    -> 等 10 秒
# （本站 /api/* 的 429 现在也带 Retry-After 头, 连算都不用算）

# 主动限流: 剩余不足 10% 时把自动查询降到保守间隔, 不再撞 429
if q["remaining"] is not None and q["remaining"] / q["per_min"] < 0.1:
    slow_down()
```

---

## Hypixel 官方接口反代

> **这是 Hypixel 官方 API 的镜像入口 —— 你不需要看我们自己的接口文档。**
>
> 要调这个反代，请**按 Hypixel 官方文档写代码**：
>
> | | 地址 |
> |---|---|
> | 官方 API 入口 | https://api.hypixel.net/ |
> | 官方 API 文档与仓库 | https://github.com/HypixelDev/PublicAPI |
> | 官方开发者后台（申请真 Key） | https://developer.hypixel.net/ |
>
> **你唯一要改的就是 base url**：把 `api.hypixel.net` 换成
> `hyp-api.firebounce.today`，路径 / 参数 / 返回的 JSON **一模一样**。
> Key 用本站的 `bsk_` Key（`/apikey` 申请），不用 Hypixel 的 Key。
>
> 所以：**端点列表、字段含义、参数写法，一律以 Hypixel 官方文档为准** ——
> 下面只讲"和官方的差别"，不重复抄一遍官方的接口说明（抄了会过期，也会误导）。

**把 base url 换掉就能用**，其它一行都不用改：

```diff
- https://api.hypixel.net/v2/player?uuid=<uuid>          (Header: API-Key: <Hypixel 的 Key>)
+ https://hyp-api.firebounce.today/v2/player?uuid=<uuid>  (Header: API-Key: <你的 bsk_ Key>)
```

路径、查询参数、返回的 JSON **全都是原样透传**的 —— 你的客户端仍然以为自己在跟
Hypixel 说话，不用改任何解析代码。

### 别名入口 `/api/hypixel/v2/...`

如果出于某种原因不想用第二个域名，反代在**主域名上也有一个别名**：

```
https://hyp-api.firebounce.today/v2/player?name=Notch
https://api.firebounce.today/api/hypixel/v2/player?name=Notch   ← 等价
```

两条路径返回的东西**字节级一致**（实测 7741 B / 85 B / 23981 B 三个样本
`BODY_IDENTICAL=True`，`Content-Type` 也一致），Key、额度、缓存全部共用。

少写 `/v2` 也行，会自动补上：

```
/api/hypixel/player?name=Notch   ==   /api/hypixel/v2/player?name=Notch
```

（裸调 `/api/hypixel` 没有子路径可转发，会回一段说明 JSON，**不消耗上游额度**。
还是**推荐直接用 `hyp-api.firebounce.today`** —— 少一层转发、少一次跳转。）

### 和官方有什么区别

| | 官方 `api.hypixel.net` | 这个反代 |
|---|---|---|
| Key | Hypixel 的 Key | **本站 `/apikey` 申请的那把**（`bsk_` 开头） |
| 额度 | 一把 300 / 分钟 | **多把池子叠加**，一把失效自动换下一把；本站计费另按**响应体积**加权（见[额度](#额度)） |
| 认证方式 | `API-Key: <key>` | `Authorization: Bearer <key>` / `?key=` / `X-API-Key` |
| 限流头 | `ratelimit-*` | **只透传白名单里的几个**（见下方"响应头边界"），不是全部 |

### 上游重试与时序

| 项 | 值 |
|---|---|
| 单把 Key 的上游超时 | **12 秒**（每次尝试还会被剩余总预算截断） |
| 最多尝试 | **3 把不同的 Key**（第一次 + 换 2 次） |
| 总预算 | **30 秒**（只覆盖上游尝试，**不含**写回客户端） |

**任何失败都会换一把还没试过的 Key 重试** —— `429` / `401` / `403` / `5xx` / `404` /
超时 / 连接重置都算。换 Key 成本很低，而猜"哪种错值得重试"只会漏掉真实情况。

- 三把都失败 → **原样返回最后一次的响应**（是 `429` 就回 `429`，body 与上游一致）。
- 全是网络错误 → `502`。
- **网络错误不会隔离 Key**，所以内部要显式挑没试过的，否则会一直在同一把上打转。

### 计费

| 项 | 值 |
|---|---|
| 基础额度 | **1**（不是 1.5 —— 1.5 只给 `/api/player`、`/api/tags`、`/api/player/card`） |
| 体积加权 | 有，档位见[额度](#按响应体积加权) |
| 结算时机 | **先把响应完整写回客户端、且状态码 < 400，才按完整额度结算** |
| 失败计费 | **基础额度的 50%**（0.5），覆盖上游错误 / 超时 / 连接失败 / 客户端写回失败 |
| 失败的体积费 | **不追加** |

**例外**（这几条跟"失败半价"不一样）：

- **鉴权失败（`401` / 配额 `429`）一分不扣** —— 那时候还没记账。
- **反代自己的全站闸门 `429` 会按 0.5 结算**（预留已经建好了）。
- 预留超过 **60 秒**才结算的话，那条预留已被清掉，结算按 **0** 处理。

> ⚠️ 缓存的 `X-Quota-Cost` 报的仍是**体积理论价**（1/7/15），
> 不是实际扣掉的 0.5。**别拿它当账本**，要准确数字用
> [`/api/quota`](#查自己的额度-apiquota)。

### 缓存：哪些响应能缓存

**TTL 固定 300 秒**（不可用环境变量调），最多 **512** 条，先淘汰过期再淘汰最旧。

**只有「上游状态码 `200` **且** 响应体非空」才进缓存。** 以下**都不缓存**：

- 任何非 `200`（含 `429` / `401` / `403` / `5xx`）
- 名字冷却期的 `429`
- `200` 但**响应体为空**
- 所有网络错误
- **所有 Bugland 响应**（BJD 侧没有缓存）

缓存键是 **`name→uuid` 改写、剥掉 `key`/`apikey` 之后的最终上游 URL**，**跨调用方共享**。
**命中缓存仍然照常扣 1/7/15** —— 缓存省的是上游时间，不是额度。

### 响应头边界

- **状态码与响应体：逐字节原样转发。**
- **响应头：只带走白名单里的几个** —— `content-type`（缺失时补
  `application/json; charset=utf-8`）、`ratelimit-limit`、`ratelimit-remaining`、
  `ratelimit-reset`、`retry-after`、`cache-control`（统一改写成 `CamelCase`）。
- `Content-Length` 重新计算；额外加上 `Access-Control-Allow-Origin: *` 和 `X-Quota-Cost`。
- **`Set-Cookie`、`Date`、`Server`、`Connection` 以及其余上游响应头全部丢弃。**

> ⚠️ **不是"所有上游响应头都照原样带走"** —— 只有上面那几个。
>
> 另一个已知瑕疵：上游返回 HTTP 错误时，转发出去的 `ratelimit-*` 取自内部的
> `_last_headers`，而该变量**只在上游成功时才填**。所以**错误响应上的
> `ratelimit-*` 可能是空的或上一次的陈旧值**，别用它判断错误响应的限流状态。

### 管理员：`/apikey rate proxy`

| 命令 | 效果 |
|---|---|
| `/apikey rate proxy` | 查看当前值、来源（环境变量 / 群内设定）与水位 |
| `/apikey rate proxy <N>` | 设为 N/分钟，**立即生效**并落盘（重启仍在） |
| `/apikey rate proxy 0` | **不限速**（持久化的"无限"，不是删除设定） |
| `/apikey rate proxy off` | **删除**群内设定，回落到环境变量 |

优先级：**群内设定 > 环境变量 `QQBOT_PROXY_RATE` > 默认 600**。
这道闸门只管反代，**不影响**每 Key 额度、并发闸门，也**不影响 Bugland**。

### 出错时的响应

**形状和官方一致**（`{success, cause}`），所以只认官方格式的解析代码不会炸。
但 `cause` 是**英文**的，而且会**明确点名"这是反代这一侧的额度"**：

```json
{
  "success": false,
  "cause": "Quota exceeded on the hyp-api.firebounce.today reverse-proxy (this is the proxy's request quota, not your Hypixel API key). Wait about a minute and retry, or ask the operator to raise the limit via '/apikey rate'. Large responses cost more quota: see the X-Quota-Cost response header."
}
```

> ⚠️ **为什么要点名**：官方那句是 `{"success":false,"cause":"Key throttle"}` ——
> 照抄的话，你会以为**自己的 Hypixel Key** 被限流了，跑去 Hypixel 后台查半天，
> 方向完全错。实际是我们这一侧的额度到了。

| 情况 | 状态码 |
|---|---|
| 本站额度用完 | `429` |
| 全站闸门繁忙（反代侧突发限流） | `429` |
| **同时处理的请求太多**（并发上限） | `429` |
| Key 无效 / 没带 / 被停用 | `401` |
| 上游失败（重试 3 次仍不行） | `502` |

> ⚠️ **所有 `429` 都是 JSON，而且 `cause` 会告诉你"是谁的限额"**。
> 这一条是修出来的：以前 nginx 那层限流回的是 **`503` + 一页 HTML**，
> 按 `{success,cause}` 解析的客户端直接炸，重试库还会把它当成"服务器挂了"。
> 现在限流层全都回 429 + JSON，并且分得清是谁：
>
> | `cause` 里出现 | 是谁的限额 | 怎么办 |
> |---|---|---|
> | `concurrency limit` | 反代**同时在处理**的请求数到了上限（默认 20） | 等一两秒重试 |
> | `reverse-proxy`（没有别的词） | **全站**每分钟的突发闸门（默认 600/分钟） | 等几秒重试 |
> | `Quota exceeded ... X-Quota-Cost` | **你这把 `bsk_` Key 的额度** | 等一分钟，或找管理员提额 |
>
> 只有第三种才是"你的额度用完了"。前两种跟你的 Key 完全无关，
> 换 Key、重新申请都没用。

### 限流：并发 + 每分钟，各自管什么

| 层 | 位置 | 默认 | 管什么 |
|---|---|---|---|
| ① **并发上限** | 服务进程（`QQBOT_MAX_CONCURRENCY`） | **20** | **同时**在处理几个请求。这个是防"进程被打垮"的关键 —— 见下面那段 |
| ② 全站每分钟 | 服务进程（`QQBOT_PROXY_RATE`） | **600 / 分钟** | 防"很多 IP 各打一点"把 Hypixel 池子打光。按池子容量给：3 把 × 300 × 2/3 |
| ③ 每 Key 额度 | 服务进程（`/apikey rate`） | **225 / 分钟**（按响应体积加权） | **真正的公平分配**。这一层才是"你的额度" |
| ④ 网站/其它站点 | nginx `limit_req` | 20 req/s（每 IP） | 只管 `hyp.firebounce.today` 和 GitHub webhook，**不作用于 `hyp-api`** |

**为什么并发那层是关键，以及为什么不用速率限制**：服务是
`ThreadingHTTPServer` —— **每个请求开一个线程**，并发数本来**没有上限**。
一瞬间打进来几千个请求，它就真去开几千个线程把内存吃光。
而"每秒 N 次"的速率限制**看不见**这个：速率只管新请求来得多快，
不管同时有多少个还在跑。所以真正要卡的是**同时在处理的请求数**。

满员时**直接拒绝（429），不排队** —— 排队会让延迟雪崩（调用方干等到超时），
而且排队的请求本身还占着连接和线程。快速失败让调用方重试，对反代这种
"上游本来就慢"的场景友好得多。

> 层 ④ 以前也压在 `hyp-api` 上（20 req/s 每 IP），已经**删掉** ——
> 它既挡不住"很多 IP 各打一点"（按 IP 分桶），对单个突发客户端又太狠
> （20 req/s 其实比池子本身还宽，3 把 Key 一共才 900/分钟 = 15 r/s）。
> 统一交给 ① 那层并发闸门。

调 ① 看水位：

```bash
curl -s 127.0.0.1:18096/health | python3 -m json.tool
# "concurrency": {"limit": 20, "src": "env", "in_flight": 0, "peak": 20, "rejected": 166}
```

`peak` 长期贴着 `limit` 就说明该调大；`rejected` 一直在涨而 `peak` 没到
`limit`，那是别的层在拦。

**不用登服务器也能调** —— 管理员在群里发一条指令，**立刻生效、不用重启**
（打满的那一刻正是不能重启的时刻，所以特意做成热改的）。挂在已有的
`/apikey rate` 下面，不另开指令：

```
/apikey rate                              看全部限流配置（含并发 + 水位 + 谁在占着）
/apikey rate concurrency 50               全站并发上限改成 50
/apikey rate concurrency 0                全站不限（危险：线程无上限）
/apikey rate concurrency default off      删掉全站设定，回到环境变量

/apikey rate concurrency <Key|QQ> 5       给**这一个人**单独设 5
/apikey rate concurrency <Key|QQ> off     删掉这个人的
```

别名 `/apikey rate 并发 50`、`/apikey rate conc 50` 也认。
**只带一个参数 = 全站，带两个 = 先是谁、再是值** —— 靠参数个数消歧，
不然 QQ 号和并发数都是数字，分不出来。

### 为什么要"每人一档"

全站那一档是**共享**的：一个调用方开 50 个并发就把 20 个槽位全占了，
别人全部 429。全站档只能保护「进程别被打垮」，保护不了「谁也别把谁挤死」——
后者得靠每人一档。

优先级：**按 Key 覆盖 > 按 QQ 覆盖 > 全站设定 > 环境变量 `QQBOT_MAX_CONCURRENCY`
> 代码默认 20**。

| 写法 | 含义 |
|---|---|
| `/apikey rate concurrency bsk_xxxx…yyyy 5` | 这一把 Key 最多 5 个并发 |
| `/apikey rate concurrency 3950591067 5` | 这个 QQ **名下所有** Key 最多 5 个并发 |
| `/apikey rate concurrency 50` | 全站 50（没单独设过的人都跟着这个） |

`0` = 这个人不限（他**仍然**受全站那一档约束）。

按 Key 分桶只读请求里的 Key 做标识，**不做鉴权** —— 拿一把不存在的 Key 来刷
只会进它自己的桶，然后照样 401。POST 请求的 Key 如果在 body 里，那次只算全站档。

设定落盘到 `rate_limits.json`（跟额度配置同一个文件），重启后还在。
`/apikey rate` 里还会列出「谁在占着」（Key 打码）—— 排查是谁把并发占满就看它。
三个认证方式**任选其一**即可：

```bash
# ① 请求头 (推荐, Key 不会进 URL 日志)
curl -H "API-Key: bsk_你的key" \
  "https://hyp-api.firebounce.today/v2/player?uuid=069a79f444e94726a5befca90e38aaf5"

# ② Authorization
curl -H "Authorization: Bearer bsk_你的key" \
  "https://hyp-api.firebounce.today/v2/player?uuid=069a79f444e94726a5befca90e38aaf5"

# ③ URL 参数
curl "https://hyp-api.firebounce.today/v2/player?uuid=069a79f444e94726a5befca90e38aaf5&key=bsk_你的key"
```

```python
import requests

r = requests.get(
    "https://hyp-api.firebounce.today/v2/player",
    params={"uuid": "069a79f444e94726a5befca90e38aaf5"},
    headers={"API-Key": "bsk_你的key"},
)
print(r.json()["player"]["displayname"])
```

### 覆盖范围：官方全部 34 个端点

**官方 v2 的每一个端点都转发** —— 我们不做白名单，所以官方文档里有什么这里就有
什么。[官方文档](https://github.com/HypixelDev/PublicAPI)。

下面是**实测过**的清单（2026-09-25 全量跑过一遍，都通；
2026-09-26 复查时官方已增至 **34 个**，补上了 Housing 和 Garden 那 4 个）：

| 端点 | 参数 | 实测大小 | 说明 |
|---|---|---|---|
| `/v2/player` | `uuid` | 24 KB | 玩家完整数据（各游戏 stats） |
| `/v2/status` | `uuid` | 85 B | 在线状态 |
| `/v2/recentgames` | `uuid` | 69 B | 最近对局 |
| `/v2/guild` | `player` / `id` / `name` | 29 B～ | 公会 |
| `/v2/counts` | — | 4 KB | 各游戏当前在线人数 |
| `/v2/leaderboards` | — | **389 KB** | 各榜前列玩家 |
| `/v2/boosters` | — | 67 B | 当前网络 booster |
| `/v2/punishmentstats` | — | 142 B | 处罚统计 |
| `/v2/resources/achievements` | — | **434 KB** | 成就表 |
| `/v2/resources/challenges` | — | 14 KB | 挑战表 |
| `/v2/resources/games` | — | 7.7 KB | 游戏信息 |
| `/v2/resources/quests` | — | 49 KB | 任务表 |
| `/v2/resources/guilds/achievements` | — | 1 KB | 公会成就 |
| `/v2/resources/vanity/companions` | — | 1.9 KB | 伙伴（宠物外观） |
| `/v2/resources/vanity/pets` | — | 15 KB | 宠物表 |
| `/v2/resources/skyblock/collections` | — | 83 KB | SkyBlock 收集 |
| `/v2/resources/skyblock/skills` | — | 117 KB | SkyBlock 技能 |
| `/v2/resources/skyblock/items` | — | **5.07 MB** | SkyBlock 物品表 ⚠️ 扣 15 |
| `/v2/resources/skyblock/election` | — | 2.5 KB | 市长选举 |
| `/v2/resources/skyblock/bingo` | — | 4.9 KB | Bingo 目标 |
| `/v2/skyblock/news` | — | 1.2 KB | SkyBlock 新闻 |
| `/v2/skyblock/bazaar` | — | **3.6 MB** | 集市价格 ⚠️ 扣 7 |
| `/v2/skyblock/auctions` | `page` | **2.4 MB** | 活跃拍卖（分页）⚠️ 扣 1（实测 2.4 MB 未达 3 MB 档） |
| `/v2/skyblock/auctions_ended` | — | 147 KB | 刚结束的拍卖 |
| `/v2/skyblock/firesales` | — | 27 B | 限时抢购 |
| `/v2/skyblock/profiles` | `uuid` | 12 KB | 玩家所有 SkyBlock 档案 |
| `/v2/skyblock/profile` | `profile` | 12 KB | 单个档案（用 profile_id） |
| `/v2/skyblock/museum` | `profile` | 29 B～ | 博物馆 |
| `/v2/skyblock/bingo` | `uuid` | — | 玩家 Bingo 进度（没数据时 404） |
| `/v2/skyblock/auction` | `uuid` | 2.3 KB | 单个拍卖详情 |
| `/v2/skyblock/garden` | `profile` | — | 花园（2026-09 新增） |
| `/v2/housing/active` | — | — | 活跃房屋列表 |
| `/v2/housing/houses` | `uuid` | — | 某玩家的房屋 |
| `/v2/housing/house` | `house` | — | 单个房屋详情 |

> ⚠️ **Housing 那三个返回的是裸数组，没有 `success` 外壳** —— 这是 Hypixel
> 那边的行为，我们原样透传。按 `{success, cause}` 解析的代码在它们上面会拿到
> null，用之前先看一眼实际返回。
>
> ⚠️ 标了大小的是**大响应** —— 会按[体积加权](#按响应体积加权)多扣额度。
> `skyblock/items`（5 MB）和 `bazaar`（3.6 MB）这类**请本地缓存**，
> 它们是静态/准静态数据，反复拉纯属浪费。
>
> 💡 响应头里的 **`X-Quota-Cost`** 会告诉你这次花了多少额度，不用自己算。

### 这个反代**只接受 GET**

官方 v2 本来就是 GET-only，所以功能上没损失。但要知道：

| 方法 | 返回 |
| --- | --- |
| `GET /v2/*` | Hypixel 的原样响应 |
| 其它方法（`POST` 等） | **本站**的 `404 {"error":"not found","path":…}` |
| `HEAD` | **本站**的 `501` |

也就是说**非 GET 的报错形状不保证是官方的 `{success,cause}`**。
只认官方形状的解析代码遇到 404/501 会拿到 null —— 别把非 GET 当正常路径用。

### 为什么不能拿真 Hypixel Key 来用

**故意的。** 如果这里接受别人自己的 Hypixel Key，这个域名就成了**开放代理** ——
任何人都能借它隐藏真实来源、并白嫖我们 Key 池的额度。所以**只认本站 `bsk_` Key**，
其它一律 `401 invalid_key`。

### 一个已知情况：Cloudflare 会挡特定 User-Agent

这个域名在 Cloudflare 后面，Browser Integrity Check 会挡掉一些 UA：

- **`python-urllib/x.y`（urllib 默认）** → `403 error code: 1010`
- **`Java/1.x`（Java 的 `HttpsURLConnection` 默认）** → 同样 `403 / 1010`

请求**根本没到我们这边**，所以这种情况**不计额度**。

> ⚠️ **这条不稳定**：实测同一天第一轮 403，半小时后连打 3 次全是 200。
> 别去赌"这次没被挡"，**永远显式带一个 `User-Agent`** 才对：
>
> ```python
> req = urllib.request.Request(url, headers={"User-Agent": "my-app/1.0"})
> ```

已针对 API 域名加了一条 WAF 规则跳过 Browser Integrity Check ——
`hyp-api.firebounce.today` 和 `api.firebounce.today` 现在不受影响；
`mail.firebounce.today` 这类浏览器站点**保护照旧**（Java UA 仍会被挡）。

浏览器、`curl`、`requests`、各种 SDK 都自带 UA，本来就不受影响。

---

## Bugland 接口反代

**Base：`/bjd/v2`** → 上游 `https://api.mcbjd.net/v2/`。

```bash
curl 'https://api.firebounce.today/bjd/v2/player?uuid=<uuid>&key=<你的 bsk_bjd_ key>'
```

| 项 | 值 |
|---|---|
| 对外 Key 前缀 | **`bsk_bjd_`** + 32 位十六进制 |
| 鉴权 | 同[鉴权](#鉴权)：`?key=` / `?apikey=` / `Authorization: Bearer` / `API-Key` / `X-API-Key` |
| 方法 | **`GET` 和 `POST` 都支持** |
| 基础额度 | **1 次/请求** + 体积加权 |
| 每 Key 限速 | 默认 **30/分钟**（`QQBOT_BJD_RATE`） |
| 每 Key 并发 | 默认 **20**（`QQBOT_BJD_MAX_CONCURRENCY`） |
| 请求体上限 | **4 MiB**，超出回 `413` |
| 缓存 | **无** |

### 与 Hypixel 完全独立

| | Hypixel | Bugland |
|---|---|---|
| 对外 Key 存哪 | `denick_keys.json` | `bjd_api_keys.json` |
| 上游凭据 | Hypixel Key 池 | `bjd_keys.txt` / `QQBOT_BJD_TOKEN` |
| 限速状态 | `rate_limits.json` | `bjd_rate_limits.json` |
| 每分钟闸门 | 600/分钟（反代闸门） | **不受该闸门管辖**，只有自己的 30/分钟 |
| 管理员命令 | `/apikey rate` | `/bjdkey rate` |

**共用**的只有：进程级**并发闸门**（默认 20，与 Hypixel 共享同一个计数器）、
以及响应写出与扣费通道。

### 计费与 Hypixel 不同（重要）

- **每笔授权请求先扣满 1 次**，即使随后上游失败 —— **没有 50% 失败折扣**。
- 配额是**整数计**，不是加权小数。
- 体积附加费在**每一个**响应上都加，**包括 `4xx` / `5xx`**
  （Hypixel 侧只在成功时加）。
- 体积档位同样是 3 MB / 5 MB → 合计 7 / 15。

### 错误形状

```json
{"success": false, "cause": "..."}
```

| 状态码 | 场景 |
|---:|---|
| `401` | Key 缺失 / 非法（不以 `bsk_bjd_` 开头）/ 已停用 |
| `413` | 请求体超过 4 MiB |
| `429` | 该 Key 额度用完 |
| `502` | 上游失败 |
| `503` | 反代模块或配额存储不可用 |

### 上游 Token 体检

Bugland 的上游 Token 池会定期体检，与你的 Key 无关，但解释了偶发的上游不可用：

- 目标周期 **3 小时**（`QQBOT_BJD_PROBE_PERIOD`），按 Token 数均匀错开，
  单个间隔不小于 30 秒。
- **只有 `401` / `403` 算失败**；`429`、上游错误、网络异常都算"不确定"，**保留** Token。
- 退场需要**初次失败 + 两次复检都失败**（默认等 10 秒、15 秒）。
- 退场前备份到 `bjd_tokens_dead.txt`；**环境变量 `QQBOT_BJD_TOKEN` 永不退场**。

> 注意：上游重试只用**文件里前 3 个** Token（按顺序），不是"最闲的 3 个"。

---

## 注意事项（重要）

1. **同名 ≠ 同一人。** 实测 `theoshadow` 本身就存在一个正版账号（`THEOshadow`），
   同时它又是 `bsk10ww` 的昵称记录。查询结果只代表「社区记录里这么写过」，
   **不要当成结论** —— 尤其拿去举报、封人之前，务必自己再核实。
2. **数据是社区上报的**，覆盖不全：查不到很正常（返回 `404`）。
3. **每 30 分钟**增量同步一次（systemd timer），刚出现的记录最多等 30 分钟。
4. 只返回公开字段，**不含** Discord 内部的频道 id / 消息 id。
5. Key 泄漏了：让管理员 `/apikey revoke <key>` 停用，然后重新 `/apikey` 申请。
6. 数据来源是第三方社区，与 Hypixel 官方无关。

---

## 实现基线与维护

本仓库的文档内容核对自**服务实现仓库**：

| 项 | 值 |
|---|---|
| 仓库 | [`bedkillerspacex-boop/bsk-qqbot`](https://github.com/bedkillerspacex-boop/bsk-qqbot) |
| **代码核对基线** | `05ef64b` |
| **生产发布 ID** | `20261002061325-4b267c5414`（revision `05ef64b`） |
| 生产是否等于代码基线 | ✅ **是** |
| 核对日期 | 2026-10-02 |

> 两者分开记是有意的：文档描述的是**代码**（唯一依据），但"某个行为现在线上是否已经生效"
> 取决于**部署**。若两者不一致，下面会有一节[复核记录](#复核记录)说明差在哪。

**代码与文档冲突时以代码为准**，并按下面的规则修正文档。

### 本次核对做到了什么、没做什么

诚实区分证据强度：

| 手段 | 覆盖 | 说明 |
|---|---|---|
| **逐行读实现代码** | 绝大部分内容 | 路由表、处理函数、额度/限速/缓存常量、响应构造函数。每条结论都能落到具体文件与行 |
| **读服务端契约测试** | 参数注册表、版本文档 | `tests/test_api_*.py` |
| **线上只读探测（不带任何凭据）** | 少量错误路径 | 见下 |
| **静态检查工具** | 链接 / 锚点 / JSON | [`tools/check_docs.py`](tools/check_docs.py) |

**线上探测过**（全部**不带 Key**，因此**不消耗任何额度**）：

| 探测 | 观测结果 |
|---|---|
| `GET /api` | `latest=v1-261001`、`latest_alias=v1`、`versions=[v1, v1-261001, v1-260925]`、24 个参数、两个反代 base |
| `GET /api/denick/v9` | `404 unknown_version`，且**不带** `X-API-Version` |
| `GET /api/card.png` | `410 gone`（`message` 仍是中文） |
| `GET /api/bancheck`（无 Key 无参数） | `400 missing_param` —— **证明参数校验先于鉴权** |
| `GET /api/denick`（无 Key 无参数） | `401 missing_key` —— 与 bancheck 相反，**先鉴权** |
| `GET /api/quota`（无 Key） | `401`，且 `X-Quota-Cost: 0` |
| `GET /api/hypixel`（裸路径） | `200 {"ok": false, message, use, aliases}` |
| `POST /api/hypixel`（裸路径） | `200 {"ok": false, message, use, aliases}` —— 修复已上线，见[复核记录](#复核记录) |

> ⚠️ **没有做到、也不该声称做到的**：
> 用**有效凭据**跑真实业务请求（会消耗额度）、核对具体扣费金额、
> 验证卡片渲染结果、验证上游返回的数据正确性。
> **"本文档通过静态检查"不等于"生产接口已逐项验证"。**
> 扣费与额度数字来自**读代码**，不是实测账单。

### 复核记录

文档写完后，服务实现仓库又往前走了，这里如实记账：

| 项 | 内容 |
|---|---|
| 新提交 | `05ef64b` — `fix(http): pass path instead of JSON to Hypixel POST discovery` |
| 起因 | 文档核对时发现 `POST /api/hypixel`（无子路径）**连接被关闭、无任何响应** |
| 根因 | POST 分支把 **JSON 请求体当成路径**传给反代，在 `subpath.rstrip` 上抛异常 |
| 修复 | POST 改为走与 GET 相同的**发现响应**：`200`，**不鉴权、不消耗额度、不打上游**；覆盖 5 种路径形态，各有子测试 |
| 上游转发 | **仍然只接受 GET**（未变） |
| **部署状态** | ✅ **已部署** —— 发布 `20261002061325-4b267c5414`（revision `05ef64b`），线上实测 `POST /api/hypixel` 与 `/api/hypixel/v1` 均回 `200` 发现响应 |

也就是说：**现在线上已经是修复后的行为**。只有在更早的发布上，`POST /api/hypixel`
才会断连。文档把两种行为都写清楚了，以[实现基线](#实现基线与维护)里的生产发布 ID 为准。

### 以后怎么维护（重要）

改动以下**任何一项**时，必须在**同一次变更**里同步对应版本的文档与示例，
否则文档会再次过时：

- 新增 / 删除 / 重命名任何 `/api/*` 路由或别名
- 请求参数（新增参数 → **必须追加新的永久参数 ID**，并同步
  `docs/api/parameter-registry.md`）
- 响应字段、错误 `error` 取值、状态码
- 额度、限速、缓存、闸门
- 服务端生成文案的语言或翻译边界

同时更新本文档顶部的[实现基线](#实现基线与维护)提交号。

> 🔴 **绝不修改已发布版本的既有语义。** 行为要有变化就发**新版本号**，让老版本继续按
> 老契约跑；新版本另开目录。改旧目录等于单方面撕毁对老接入方的承诺 ——
> 老版本之所以留着，就是为了让人还能照着适配。

服务实现仓库里的 `tests/test_api_documentation.py` 会校验版本文档与参数注册表
存在且一致。文档是**受测试保护的契约**，不是随手写的说明。

### 本次核对发现并修正的过时内容

| # | 原来写的 | 实际行为 |
|---:|---|---|
| 1 | 「`v1` 和 `v1-260925` 现在返回的是一样的东西」 | **反了** —— `v1` 指向 `v1-261001`（英文文案 + 信封三件套），`v1-260925` 才是旧中文契约 |
| 2 | 「已经发布过的日期版会一直认、钉死在那一版」 | 只有**字符串 `v1-260925`** 走旧契约；其它日期被接受但返回**当前版行为** |
| 3 | 响应示例只有 `{ok, data}` | 当前版多了 `api_version` / `locale` / `schema` |
| 4 | 没有 `/api/bancheck` 章节 | 已补：来源、语义、字段、额度、错误、与旧版差异 |
| 5 | 没有参数 ID | 已补 `docs/api/parameter-registry.md`（**24 个，1–24 连续**） |
| 6 | 没有 Bugland 反代 | 已补 `/bjd/v2`（`bsk_bjd_` Key、独立限速与计费） |
| 7 | 「限流头 `ratelimit-*` 同样透传」 | 只透传**白名单**里的几个；其余上游响应头全部丢弃 |
| 8 | 反代基础额度容易被误读成 1.5 | 反代是 **1**；1.5 只给 `/api/player`、`/api/tags`、`/api/player/card` |
| 9 | 反代缺超时/预算/失败计费/缓存规则 | 已补：12 秒 / 3 把 Key / 30 秒 / 失败 50% / 缓存 300 秒及可缓存条件 |
| 10 | 「本地接口不受全局闸门限制」（含 `/api/quota`） | 每分钟闸门确实不受限，**但并发闸门对包括 `/api/quota` 在内的所有 `/api/*` 都生效** |
| 11 | 没有版本归档结构 | 已建 `docs/api/`：当前版 + 冻结的历史版 + **旧版原文快照** |

**尚未修正的服务端缺陷**（属实现侧，文档已如实标注）：

- `401` 的 `message` **没进翻译表**，在 `v1-261001` 下仍是中文 —— 与"服务端文案是英文"不一致。
  客户端请按 `error` 代码判断，不要按文案语言判断。
- ~~`POST /api/hypixel`（裸路径或 `/v1`）会抛异常、不返回文档化的错误响应。~~
  **已在 `05ef64b` 修复并部署**，线上实测回 `200` 发现响应 —— 详见[复核记录](#复核记录)。
- 卡片的封禁展示把**所有非 banned 状态**都显示成 `Not banned`，与机器字段
  `state: "unknown"` 不一致。
- 管理员命令 `/apikey rate` 的帮助文案里的体积阈值（">1 MB 扣 4 / >5 MB 扣 8"）
  与实现（3 MB / 5 MB → 7 / 15）不符。
- `/api` 发现文档里的 `docs` 字段指向服务实现仓库的路径，而非本公开文档仓库。

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-02 | **文档全面对齐实现**：修正版本化章节（`v1` ≠ `v1-260925`、只有 `v1-260925` 被特殊对待）、补 `api_version`/`locale`/`schema` 信封、新增 [`/api/bancheck`](#封禁查询-apibancheck) 完整章节、新增**永久参数 ID**（24 个）章节、新增 [Bugland 反代](#bugland-接口反代) 章节、补全 Hypixel 反代的上游超时/重试预算/失败计费/缓存与响应头白名单、修正全局闸门说明（`/api/quota` 也过并发闸门）。建立**按版本归档**的文档结构：[`docs/api/`](docs/api/README.md)（当前版 `v1-261001` + 冻结的 [`v1-260925`](docs/api/v1-260925/README.md) + [旧版原文快照](docs/api/v1-260925/REFERENCE.md)）。基线与维护规则见[实现基线与维护](#实现基线与维护)。**补充**：核对期间发现的 `POST /api/hypixel` 断连缺陷已由实现提交 `05ef64b` 修复，并已发布（`20261002061325-4b267c5414`）—— 线上实测回 `200` 发现响应，见[复核记录](#复核记录) |
| 2026-09-29 | **修「新披风显示未命名披风」**：披风名字原来只在玩家 NameMC **档案页**的「拥有」列表里按像素找，而那份列表**更新有延迟** —— 玩家刚拿到的新披风还没进去，于是必然认不出。现在**两级查找**：档案页找不到就去 NameMC [全量披风目录](https://namemc.com/capes)（约 50 件）按同一套正面 10×16 指纹再找。⚠️ 顺带否掉了一个**看起来对但会撒谎**的写法：拿档案页标的"当前穿戴"兜底 —— 实测它会把 *Twisted* 标成 *Minecraft Experience*，给**错名字**比「未命名」更糟。新披风还会补进 `items`（否则"当前穿戴 Twisted"但拥有列表里没有 Twisted 自相矛盾）。认不出仍然是「未命名披风」，不猜 |
| 2026-09-27 | **新增 `GET /api/quota` —— 查你自己这把 Key 的额度 / 并发 / 限流状态，免费。** 以前公网**拿不到**任何额度信息（只有 `X-Quota-Cost` 告诉你这一单花了多少），限额、剩余、并发水位全在群里或本机 `/health` 里，于是插件只能自己累加 `X-Quota-Cost`（刚重启显示 `0.0 / 0.0`，用户以为插件坏了），而且**没法预判 429**、分不清三种原因（并发 / 全站 / 自己额度 —— 退避分别是 1~2 秒 / 10 秒 / 60 秒）。响应用 `used = charged + reserved`：**在飞预留必须算进 used**，因为服务端判定超限用的就是"已结算 + 预留"，只报已结算会出现"显示还剩 50 但下一个请求立刻 429"。`cost: 0` 且**不进任何全站闸门**（随时可查，全站正忙也 200），但**它自己限速 10 次/分钟**（免费又秒回、不设限就是个随便刷的洞），超了回 429 + `Retry-After`。只回调用方自己的信息，坏 Key 一律 401 **绝不**顺手回别人的数据，`key` 字段打码。另外顺带：`X-Quota-Cost` 补进 CORS `Access-Control-Expose-Headers`（以前浏览器读不到它，网页没法自己统计花费），本站 `/api/*` 的 429 也补上了 `Retry-After` 头 |
| 2026-09-26 | **并发上限支持「每人一档」**。全站那一档是**共享**的 —— 一个调用方开 50 个并发就能把 20 个槽位全占了，别人全 429；全站档只能保护「进程别被打垮」，保护不了「谁也别把谁挤死」。所以 `/apikey rate concurrency <Key或掩码|QQ号> <数字>` 能给单个人/单把 Key 另设一档，`off` 删掉。优先级 **按 Key > 按 QQ > 全站 > 环境变量 > 默认 20**。靠**参数个数**消歧（1 个 = 全站的值，2 个 = 先是谁再是值），不然 QQ 号和并发数都是数字没法分。按 Key 分桶只读请求里的 Key 做标识**不做鉴权** —— 拿不存在的 Key 来刷只会进它自己的桶然后照样 401；POST 的 Key 在 body 里时只算全站档。`/apikey rate` 会列出「谁在占着」（Key 打码）。实测：给两个 QQ 分别设 2 和 9，限 2 的连开 3 个得 `[True, True, False]`，同时另一个照常通过；释放后能再进；全站档独立生效。每把 Key 的计数在释放到 0 且没被拒过时整条删除，表不会涨 |
| 2026-09-26 | **并发上限做成 `/apikey rate concurrency <N>`（热改，不用重启）**。`/apikey rate` 现在把并发上限和它的水位一起列出来；`concurrency <N>` 改、`concurrency 0` 不限、`concurrency off` 删掉设定回到环境变量。**没有单开指令** —— "每 Key 每分钟额度"和"同时在处理几个请求"同属"服务侧怎么限流"，挂在同一条下面就够了（第一版单开了一条 `/并发`，已撤掉重做）。优先级 **群里设的 > 环境变量 `QQBOT_MAX_CONCURRENCY` > 默认 20**，群里设的落盘到 `rate_limits.json` 所以重启后还在。做这个是因为"并发上限"是最需要**边看水位边调**的东西，而打满的那一刻正是不能重启的时刻 —— 只能改环境变量+重启的话等于没用。`/health` 的 `concurrency` 也补了 `src` / `env_default`，一眼看出当前值是哪来的 |
| 2026-09-26 | **限流改成「并发上限 + 每分钟」两层，并把 nginx 那层从 `hyp-api` 删掉**。`hyp-api` 上的 nginx `limit_req`（20 req/s 每 IP）已移除，统一交给服务进程的**并发闸门** `QQBOT_MAX_CONCURRENCY`（默认 **20**，可调；`0` = 不限）。换成并发而不是速率的原因是：服务是 `ThreadingHTTPServer`，**每个请求开一个线程**，并发数本来没有上限 —— 一瞬间几千个请求就真去开几千个线程把内存吃光，而"每秒 N 次"的速率限制**看不见**这一点（它只管新请求来得多快，不管同时有多少还在跑）。满员时直接回 `429`（不排队 —— 排队会让延迟雪崩，而且排队的请求本身还占着连接和线程）。反代路径回 Hypixel 形状、本站 API 回 `{ok:false}`，两条路径分开不串味。水位可以从 `/health` 的 `concurrency: {limit, in_flight, peak, rejected}` 看。实测并发 60 打 200 发：`peak` 正好卡在 20 从没超，166 个 429 的 `cause` 都写明 `concurrency limit of 20` 且**明确不是你的 Key**。`hyp.firebounce.today` 和 GitHub webhook 的 nginx 限流**保留不动**（用户指定只删 api 端点那个）—— 它们上次补的 `limit_req_status 429` + JSON error_page 也保留，那是"别回 503 HTML"的修复 |
| 2026-09-26 | **修两个限流 bug（压测暴露的）**。① **nginx 边缘限流回的是 `503` + 一页 HTML**：`hypapi` / `denick-api` / `hyp-web` 三个站点用了 `limit_req` 却都没设 `limit_req_status` —— nginx 默认值是 503（仓库里 southside / namewall 都设了 429，这三个当初漏了）。后果是状态码语义全错（503 = "服务器挂了"，重试库和监控都会当真故障）**而且**反代"只改 base url 就能用、返回和 Hypixel 一样"的承诺当场作废 —— 按 `{success,cause}` 解析的客户端会拿到 HTML。现在三个站点都设了 429，并用 `error_page 429` 让 nginx 自己的限流也回 JSON（`proxy_intercept_errors` 默认 off，所以**不会**盖掉上游 Python 那几种 429 的 cause）。② **反代跟 `/api/player` 共用同一个全局 90/分钟闸门**：那个闸门是给要真打 Hypixel/Urchin 的重接口准备的，全局不分人 —— 于是反代卖着"多把 Key 叠加额度"（3 把 = 900/分钟）却卡在 90/分钟，而且网站一忙反代跟着一起挂。实测压测 120 发里 30 发是 `Server is busy (global throttle)`。现在拆成独立一档 `QQBOT_PROXY_RATE`（默认 600/分钟），并把 `cause` 改成明确说"这是反代侧的突发限流，不是你的 Key"。修完复测：300 发并发里**零**个应用侧 429，非 200 全部是 nginx 边缘限流，形状正确 |
| 2026-09-26 | **修 `/api/hypixel` 别名（原来五种形态全 404）**：文档和 `/api` 清单里一直列着这个别名，但它**从来没成功过一次**。两个原因叠在一起：① 反代处理函数**不管从哪进来的都读 `self.path`**，于是 `/api/hypixel/v2/status` 把整串（含 `/api/hypixel` 前缀）丢给上游 → 上游 404；② 带后缀的形态**先撞上版本路由**，被解析成「端点=hypixel，版本=v2/status」→ 本站 404 未知版本，根本走不到反代那段代码。现在在版本路由**之前**拦下 `/api/hypixel(/*)`，剥掉前缀交给反代。顺带修掉两个附带毛病：裸调 `/api/hypixel` 以前兜底成 `/v2` 让上游回一个看不懂的 404，现在直接回一段说明 JSON（不消耗上游额度）；少写 `/v2` 的形态（`/api/hypixel/player?name=X`）以前会 `path = "/v2"` **把子路径整个丢掉**变成 `/v2?name=X` → 上游 `Unknown endpoint`，现在是**补上** `/v2` 得到 `/v2/player?name=X`。线上实测五种形态全通，且与 `hyp-api` 直连**字节级一致**（7741 B / 85 B / 23981 B 三样本 `BODY_IDENTICAL=True`）。反代返回格式**一个字没动** |
| 2026-09-26 | **端点清单 30 → 34**：官方 v2 新增了 `/v2/housing/{active,houses,house}` 和 `/v2/skyblock/garden`。同时把两条容易被坑的事实写进文档：`/v2/housing/*` 返回的是**裸数组**（没有 `success` 外壳，这是 Hypixel 的行为，我们原样透传）；反代**只接受 GET**，非 GET 拿到的是本站的 404/501，形状**不是**官方的 `{success,cause}` |
| 2026-09-25 | **补全反代的端点清单**：《覆盖范围》从"四个常用例子"扩成**官方全部 30 个端点**的实测表（带参数、响应大小、备注）。起因：反代本来就转发所有 `/v2/*`，但文档只列了 4 个，用的人（和 AI）不知道别的能不能用 —— 于是把 30 个**全量跑了一遍**确认都通，并标出哪几个是大响应（`skyblock/items` 5 MB、`bazaar` 3.6 MB、`leaderboards` 389 KB…），提醒本地缓存 |
| 2026-09-25 | **打了上游的接口改成扣 1.5**：`/api/player`、`/api/player/card`、`/api/tags` 每次要真的出网打 Hypixel / Urchin，一次扣 **1.5**；`/api/denick`、`/api/search`、`/api/recent`、`/api/nick-history` 纯本地查索引，仍是 1。为了支持小数，额度计数器从"记一条时间戳"改成**带权重**的形式（`(时间, 权重)`），判断超限按**总量**比 —— 所以 225 的额度能放 150 次 1.5，而不是凑整成 2 只能放 112 次。体积加权与它**叠加**：出网接口拉 5 MB 响应扣 15.5 |
| 2026-09-25 | **反代出错的 `cause` 改成英文 + 点名是"反代的额度"**：以前额度用完回的是中文 `"请求过于频繁, 请稍后再试"` —— 那是**给群消息用的文案**，放在接口响应里不合适（调用方可能是任何语言的程序），而且没说是谁的额度。现在 `cause` 一律英文，并明确写出 `Quota exceeded on the hyp-api.firebounce.today reverse-proxy (this is the proxy's request quota, not your Hypixel API key)` 外加怎么办（等一会儿重试 / `/apikey rate` 提额 / 大响应有 `X-Quota-Cost`）。**不照抄官方那句 `"Key throttle"`** —— 那会让人误以为是自己的 Hypixel Key 被限流，跑去 Hypixel 后台查，方向全错 |
| 2026-09-25 | **仓库改名 `bsk-denick-api` → `bsk-hypixel-api`**：老名字只体现了两个服务里的第一个（denick 反查），容易让人以为这里没有 Hypixel 反代。旧地址自动跳转，另在旧名下留了一个占位仓库写明已迁移 |
| 2026-09-25 | **`/api/card.png` 下线**（返回 `410 gone`）：没人用，而且每次都要**真的渲染一张 PNG**（几十 MB 内存 + CPU），纯浪费算力。想要卡片图请用群里的 `/hyp <名字>`，或改用 `/api/player/card` 拿 JSON 自己渲染 —— 那个不出图，快得多 |
| 2026-09-25 | **反代出错也保持 Hypixel 的形状**：以前额度用完时反代会回我们自己的 `{"ok":false,"error":"rate_limited"}` —— 可反代的卖点是"只改 base url 就能用"，调用方只认官方的 `{success, cause}`，突然冒出个自定义结构会让解析代码炸掉，还会被误以为 Hypixel 改了接口。现在额度用完 / Key 无效 / 上游失败一律回 `{"success":false,"cause":"..."}`（配 429 / 401 / 502） |
| 2026-09-25 | **额度按响应体积加权**：不再"一次请求扣 1"，而是普通响应扣 **1**、> 3 MB 扣 **7**（1+6）、> 5 MB 扣 **15**（1+14）；`MB` 按十进制算，边界**严格大于**。起因是反代能打到 `/v2/resources/skyblock/items` 这种 **5 MB** 的响应，而查一次 `/v2/status` 只有 85 字节 —— 按次数一刀切对别人不公平。每次响应带 **`X-Quota-Cost`** 头，调用方一眼看到这次花了多少。**「频率限制」统一改称「额度」**（`/apikey rate` 的文案、帮助、`/apikey list`/`status` 的显示都跟着改；`per_min`、`rate_limited` 这些**接口字段名没动**，老调用方不受影响） |
| 2026-09-25 | **反代失败一律换 Key 重试**：429 / 401 / 403 / 5xx / 404 / 超时 / 连接重置 —— **任何失败都换一把 Key 再试**（以前只对 401/403/429）。最多 **3 次**（第一次 + 换 2 次），仍失败则**原样返回**最后一次的响应（是 429 就回 429，body 与 Hypixel 的真实内容一致）；全是网络错误则回 502。目的是尽量把成功的数据交给调用方 —— 换 Key 成本很低，而猜"哪种错值得重试"只会漏掉真实情况。**注意**：网络错误不会隔离 Key，所以内部必须显式挑一把没试过的（`_pick_untried`），否则 `pool_pick` 会一直返回同一把，"重试"变成原地打转 |
| 2026-09-25 | **新增 Hypixel 官方接口反代 `hyp-api.firebounce.today`**：把 base url 从 `api.hypixel.net` 换成它就完事 —— 路径、参数、返回的 JSON **字节级原样透传**（实测 `/v2/player`、`/v2/status`、`/v2/guild` 与官方逐字节相同，连错误响应也一样）。Key 用本站 `/apikey` 申请的 `bsk_` Key（三种传法都认），背后是**多把 Hypixel Key 组成的池子**：额度按把叠加（每把 300/分钟），一把被拒自动换下一把、连续 5 次才自动退场。`ratelimit-*` 头照原样透传。**故意不接受**用真 Hypixel Key 转发 —— 那会让这个域名变成开放代理，别人可借它隐藏来源、白嫖额度；所以其它 Key 一律 `401 invalid_key`。另：该域名开了 Cloudflare Browser Integrity Check，**`python-urllib` 的默认 UA 会被 CF 挡（`403 error 1010`，请求到不了源站）** —— 浏览器/curl/requests 都自带 UA 不受影响，裸用 urllib 时设一下 `User-Agent` 即可 |
| 2026-09-25 | **版本号改成日期制**：新增 `/api/denick/v1-260925` 这种**钉死某一版**的写法（`YYMMDD` = 发布日），以后改接口它**不动**。原因是 `v1` 是个**会动**的浮标 —— 接口一改，用它的人会**无声地**跟着变。`/api/denick/v1` 继续可用且**含义不变**（= 最新的 v1，现在和 `v1-260925` 返回同一个东西），老文档/老脚本一个字都不用改。三条规则：先比大版本号（`v2` > 所有 `v1`），再比日期；**已发布过的日期版一直认**（`v1-250101` 照样能调），只有**未来**日期才拒（免得写错一位数字却以为调到了新接口）；版本号**写错时明确 404 unknown_version**，不再被当成端点名去查（以前 `/api/denick/v1-2609` 会回一句莫名其妙的"没有这个端点: denick/v1-2609"）。`/api` 清单里每个端点同时给 `versioned` 和 `alias` 两个地址 |
| 2026-09-24 | **修 `/apikey status <QQ号>` 读不到任何信息**：老代码**把参数静默丢掉**，拿发送者自己的 openid 去查，回一句"你还没申请过" —— 一个字节的信息都没有。而且对**已经有 Key 的人**也回这一句（因为只查"申请记录"，不看"你已经有一把 Key 了"）。现在 `/apikey status` 不带参数看自己（有 Key 就直接报掩码），带参数按 **QQ号 / openid / Key / 掩码 / 申请编号** 查那个人，一次列全 Key、申请、实际额度和异常提示；查不到会**说明为什么**。顺带补上根因：平台只给 openid，所以新增 **openid ↔ QQ 对照表**（`denick_people.json`，只在**邮箱验证码通过**或管理员 `/apikey bind` 时写入）—— 之前按 QQ 号配的限速**永远不生效**（Key 记录里根本没有 QQ 字段），现在 `/apikey bind` 后立即生效，并且 `/apikey rate`、`/apikey list`、`/apikey status` 都会把**"配了但匹配不到 Key、实际不生效"的覆盖显式列出来**。一个 QQ 号只能属于一个人，抢绑直接拒绝并提示先 `unbind`。另：指令现在会记日志（谁 / 哪个来源 / 参数，Key 已打码），这类"参数被吞"的问题不用再靠猜 |
| 2026-09-24 | **延迟推地区改成「分布」**：`ping_region` 从 `"亚洲·大洋洲(大致)"` 这种一个词，改成带**实测占比**的 `"亚洲 41% / 大洋洲 29%(大致)"`，并新增结构化的 **`region_guess`**（`[{"region","pct"}]`，省得解析字串）。占比是那 41 个干净样本上的**实测分布**，只列 ≥20% 的地区，而且**故意不归一到 100%** —— 归一会把 `≥165ms` 里那 18% 的非洲藏掉，读起来像"只可能是亚洲或大洋洲"。`(大致)` 后缀保留 |
| 2026-09-24 | 新增查询偏好 **`prefer`**（`/api/denick`）：三种匹配（`uuid` / `nick` / `ign`）指向的**可能是不同的人** —— 一个字符串既是甲的昵称又是乙的真名时，顺序决定查到谁。`?prefer=ign` 就是"先当真名查"，也支持 `prefer=ign,nick` 给完整顺序；**不传则与以前完全一致**（`uuid → nick → ign`）。写错返回 400 `bad_prefer` 并列出 `accepted`；404 现在带 `tried`，一眼看出是"真没有"还是"偏好设歪了"。`/api` 的端点清单也加了参数提示 |
| 2026-09-22 | 更正一处**写反了的事实**：管理员在白名单里、**审批通知的私聊是能送到的**（日志实测 `通知管理员 1`）；发不出私聊的只是**普通申请人**，所以 Key 仍必须走 QQ 邮箱。另外补了兜底：万一私聊全失败，会在群里提示一句 |
| 2026-09-23 | **修 markdown 转义导致的漏记录**：Discord 把名字里的下划线渲染成 `\_`，老解析器原样存下来 —— 昵称带下划线就**用真实拼写查不到**（索引里是 `all\_phoenix`，查 `all_phoenix` 返回 404，实测 10 个），真名带下划线则**整条记录被丢**（`^[A-Za-z0-9_]{1,16}$` 校验被 `\_` 打掉，实测 5 条，如 `ColdGame → RayanCherki_`）。现在解析时先反转义再存，并从本地归档 `rebuild()` 重算索引：**索引 39,476 → 39,472 条**（少的 4 条是同一人合并），带 `\` 的键 10 → 0，**UUID 覆盖率不变**（重建前后逐条比对：时间只会更新、不会更旧）|
| 2026-09-23 | **延迟推地区改回「粗粒度大致方位」**：之前一刀切成不推（实测单标签 59%~64%，英国 222ms / 澳洲 234ms / 中国 201ms 全落在同一段），结果只有 4% 的玩家有地区，卡面常年 `-` 也没信息量。现在按 41 个「NameMC 自设国家 + bordic 延迟」的干净样本重新标定成 3 档：`< 75ms → 北美` / `75~165ms → 欧美` / `≥ 165ms → 亚洲·大洋洲`，每档留两三个地区兜底，**整体 76%**（单档 67% / 83% / 71%），后缀写 `(大致)` 跟语言推的 `(推测)` 区分开。`ping_region` 字段同时恢复，另外新增：`country` 现在跟卡片走同一套取值逻辑 |
| 2026-09-23 | **不再用 Hypixel 延迟推断地区**（当天晚些被上面那条**改回粗粒度版**）：60 个真实样本跟 NameMC 自设国家对照，能判定的 14 个里只对 9 个（64%）—— 中国 201ms、韩国 178ms 与英国 222ms、澳洲 234ms 落在同一段，挂加速器的美国玩家也在 120~180ms。当时「地区」只显示有依据的值（NameMC 自设 / 窄语种推测），其余显示 `-` |
| 2026-09-23 | 修：`/web/api/token` 曾被 nginx 缓存 —— 后来访客拿到的是**别人签发的旧令牌**（绑的是别人的 IP）→ 一律 `token_ip_mismatch`。现在该接口精确匹配 + `no-store`；另外「空结果」永不推断「这号没数据」（Hypixel 对有数据的号也会偶发返空，实测被坑两次） |
| 2026-09-23 | **API 版本化**：`/api/<端点>` = 最新版，`/api/<端点>/v1` 写死版本（响应头 `X-API-Version` / `X-API-Latest`，不认识的版本 404，`/api` 列端点清单）；新增**网站短期令牌** `GET /web/api/token`（绑 IP、15 分钟、60 次/分钟），网页拿它**直接查 `/api/...`**，不再挤「每 IP 7 秒一次」那道闸门 —— 这是网页查询慢的老原因 |
| 2026-09-23 | 披风修正：**`worn` 改成数组** —— 官方披风和 OptiFine 披风是**同时装备**的（OF 那件只是**显示时盖住**官方那件），以前把 OptiFine 塞进「拥有」等于说它没穿，是错的；卡片上现在两件各占一行「当前穿戴」 |
| 2026-09-23 | 三条修正：① **坏卡不许顶用** —— 缓存里那张卡如果当初是「数据源异常」时出的，过期后**不会**再拿旧的糊弄（否则 Key 修好了、用户查到的还是空卡）；② Hypixel 偶尔返回 `success=true + player=null`，这种**空结果不再进 10 分钟缓存**（以前一存就把这号坑 10 分钟）；③ 「这号没进过 Hypixel」不再触发管理员告警，只有 Key 失效/限流才提醒 |
| 2026-09-23 | 新增顶层字段 **`warn`**：数据源异常（比如 Hypixel API Key 失效）时，卡片顶部出现红色「数据源异常」通栏、网页也显示横幅，并**私聊提醒管理员**（一小时一次）。起因：Key 挂了以前**完全不报错**，战绩整片是 `-`，容易被误读成「这号没数据」 |
| 2026-09-22 | **出图也加缓存**：`/hyp` 与 `/api/card.png` 现在共用一套 90 秒缓存 + 30 分钟 stale-while-revalidate —— 同一个玩家连着查从 ~3 秒变成 **~10ms**；新增响应头 `X-Card-Age` 如实报告数据多旧 |
| 2026-09-22 | 新增 **`/apikey help`**（不带参数也出这份）：一步步写清申请流程 + 常见问题，管理员会多看到一段限速配置用法；`/help` 底部也加了指引 |
| 2026-09-22 | **提速**：数据源超时收紧 + 失败冷却（之前 Urchin 会卡 20 秒、bordic 12 秒，每次都把建卡预算吃满 → 冷查询 12 秒）；建卡改**分级等待**（必需源等满预算、可选源只多等 1.5 秒）；缓存改 90 秒新鲜 + 30 分钟 stale-while-revalidate；nginx 加 60 秒共享缓存 + gzip（JSON 小 37%）。冷查询 **12s → 3~5s**，重复访问 **≈0ms** |
| 2026-09-22 | **诚实性修正**：Urchin 查询失败时不再显示成绿色的 `No Record`（那等于把「没查成功」说成「没问题」），改为黄色的 `查询失败` + 说明 |
| 2026-09-22 | 头像改为**纯水平视角**（yaw/pitch = 0：正面方脸 + 帽子层凸出） |
| 2026-09-22 | 更正**申请流程**：全程在**群里**发指令、Key 走 **QQ 邮箱**（机器人的私聊只对管理员开通，普通申请人收不到 —— 之前文档写成"私聊机器人"是错的；机器人回复里那句"同意后会私聊发 Key"也一并改掉了） |
| 2026-09-22 | 新增顶层字段 **`avatar`**（头 + 帽子层，我们自己渲染的正交投影，近正面小角度）；网页也改用它（旧的 mc-heads 头像会把帽子层丢掉） |
| 2026-09-22 | 披风拆成 **当前穿戴 `worn`**（高亮，以 Minecraft 官方皮肤属性为准）和 **拥有 `items`**（爬 NameMC 的 `Capes (N)` 区块）；网页新增 Plancke / NameMC / laby.net 外链；首页文案改为「用过的nick」 |
| 2026-09-22 | 新增 **`GET /api/player/card`** —— 整张卡片的内容（两列所有块 + 皮肤/披风 data URL + legacy Rank 的 `spans`），90 秒缓存；新增网站内部接口 `/web/api/card`；`api.firebounce.today` 放通整段 `/api/*`（之前只放通了 `/api/denick`，文档里写的 `/api/player`、`/api/card.png` 在线上其实是 404） |
| 2026-09-22 | `/web/api/*` 改成**服务端注入 Key 后照样校验**（访客看不到 Key，但整站共用那把 Key 的额度）；**限速可配**：新增 `/apikey rate`，管理员能按 Key / 按 QQ 号调每分钟次数（0 = 不限速） |
| 2026-09-22 | 返回体新增 `names` / `nicks` / `nick_count`（同一个 UUID 的所有名字与昵称）；文档强调 **UUID 是不变主键，正版 ID 会变** |
| 2026-09-21 | 接口上线：`GET/POST /api/denick`，API Key 鉴权，每 Key 120 次/分钟 |