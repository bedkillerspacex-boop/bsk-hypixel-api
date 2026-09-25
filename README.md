# BSK Hypixel API

> 📌 **这个仓库里有两个服务，接口格式完全不同，别照抄**：
>
> | 服务 | Base | 格式 |
> |---|---|---|
> | **denick 查询** | `https://api.firebounce.today` | 本站自有 `{ok, data}` 格式，见本文档 |
> | **Hypixel 官方 API 反代** | `https://hyp-api.firebounce.today` | **就是 Hypixel 官方格式** —— 端点和字段以 [官方文档](https://github.com/HypixelDev/PublicAPI) 为准，见[这一节](#hypixel-官方接口反代) |
>
> 给 AI / 爬虫的入口索引另见 [`llms.txt`](./llms.txt)。

把 **Hypixel 昵称（nick）** 反查成 **真实玩家 ID**。

```
Base URL:  https://api.firebounce.today
版本:      /api/<端点>        = 走**最新版**（现在 v1）
           /api/<端点>/v1     = 写死 v1；响应头 X-API-Version 会告诉你实际走了哪版
Endpoint:  GET / POST  /api/denick          昵称 -> 真名/UUID
           GET / POST  /api/player          身份 + 战绩 + 可疑度 + 标签
           GET / POST  /api/player/card     整张卡片的内容(JSON, 网页靠它渲染)
           (已下线)    /api/card.png        410 —— 改用 /api/player/card
           GET         /api/tags            只要反作弊标签(最轻量)
           GET         /api/search          昵称/真名模糊搜索(本地)
           GET         /api/recent          最近记录到的昵称(轮询)
           GET         /api/nick-history    某个昵称的完整出现历史

反代:      https://hyp-api.firebounce.today/v2/...   Hypixel 官方接口原样透传
           (只把 base url 换掉就能用; 端点和字段**以 Hypixel 官方文档为准**:
            https://github.com/HypixelDev/PublicAPI)
```

> **不是 Hypixel 官方数据**，可能过期或有错。**同名 ≠ 同一人**是常态，见文末 [注意事项](#注意事项重要)。

---

## 目录

- [申请 API Key](#申请-api-key)
- [鉴权](#鉴权)
- [接口](#接口)
- [返回格式](#返回格式)
- [错误码](#错误码)
- [额度](#额度)
- [示例代码](#示例代码)
- [玩家资料聚合 `/api/player`](#玩家资料聚合-apiplayer)
- [卡片内容 `/api/player/card`](#卡片内容-apiplayercard)
- [其它接口](#其它接口)
- [Hypixel 官方接口反代](#hypixel-官方接口反代)
- [注意事项](#注意事项重要)

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

**不带版本号 = 最新版。** 三种写法：

```http
GET /api/denick?nick=theoshadow              # 最新版（永远跟着走）
GET /api/denick/v1?nick=theoshadow           # 最新版的 v1（也永远跟着走）
GET /api/denick/v1-260925?nick=theoshadow    # 钉死在 2026-09-25 那一版
```

| 写法 | 含义 | 什么时候用 |
|---|---|---|
| `/api/denick` | 最新版 | 随便写写、临时调 |
| `/api/denick/v1` | **最新的 v1** —— 和上面同一个东西 | 想写明"我用 v1"，但接受它以后会变 |
| `/api/denick/v1-260925` | **2026-09-25 的那一版**，以后改接口它**不动** | 接进生产代码，不想某天被上游改字段搞挂 |

> 💡 **`v1` 和 `v1-260925` 现在返回的是一样的东西** —— 区别在**以后**：`v1` 是会动的
> 浮标，改了接口它就跟着变；日期版不会。要长期依赖就写日期版，图省事就写 `v1`。
> 日期是 `YYMMDD`（`260925` = 2026-09-25），取的是**发布日**。

- 版本号是**路径最后一段**：`/api/player/card/v1-260925` → 端点 `player/card` + 版本 `v1-260925`
- 所有响应都带 `X-API-Version`（实际走的版本）和 `X-API-Latest`（当前最新）
- 不认识的版本 → `404 {"error": "unknown_version"}`，并告诉你支持哪些
- `/api`（不带端点）会返回**端点清单**，自己发现用；每个端点同时给出 `versioned`
  和 `alias` 两个版本化地址
- 老路径（`/api/denick`、`/api/player/card` …）**继续可用**，不会因为加版本而失效
- **已经发布过的日期版会一直认**（比如 `v1-250101` 照样能调）；只有**未来**的日期
  （还没发布的）才会被拒 —— 免得你写错一位数字却以为调到了新接口

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

**每把 Key 默认 120 / 分钟**，超过返回 `429`。

### 按响应体积加权

不是"一次请求扣 1"，而是**按返回内容的大小**扣额度：

| 响应大小 | 扣多少 |
|---|---|
| 普通响应（≤ 3 MB） | **1** |
| > 3 MB | **7**（1 + 6） |
| > 5 MB | **15**（1 + 14） |

> `MB` 按**十进制**算（1 MB = 1,000,000 字节）。边界是**严格大于**：
> 正好 3 MB 仍算 1，正好 5 MB 仍算 7。

**为什么**：`/v2/resources/skyblock/items` 有 **5 MB**，而查一次 `/v2/status`
只有 85 字节。两者在我们这边（带宽 / 内存 / 上游等待）成本差得很远，按次数一刀切
不公平 —— 拿大响应的人会挤占别人的份额。加权之后自然就均衡了。

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
| 全局默认 | `/apikey rate default 240` | 所有 Key 的默认值（原本 120） |
| 某一把 Key | `/apikey rate bsk_完整的key 600` | 贴完整 Key；也可以**直接复制** `/apikey list` 里的掩码（`bsk_a1b2…9f3c`） |
| 某个 QQ 号 | `/apikey rate 123456789 300` | 认这个 QQ 号 —— **必须先 `/apikey bind` 过，否则不生效** |
| 不限额度 | 填 `0` | 慎用 |
| 删掉这条覆盖 | `/apikey rate bsk_xxx off` | 回到上一级（QQ 覆盖 → 全局默认） |
| 看当前配置 | `/apikey rate` | 列出默认值 + 所有覆盖，并标出**匹配不到 Key、实际不生效**的那些 |

优先级：**具体 Key > 该 Key 的 QQ 号 > 全局默认 > 环境变量 `QQBOT_DENICK_RATE`（120）**。

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

```json
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

- 每把 Key **120 / 分钟**（跟 `/api/denick` 共用，且按**响应体积**加权扣，见[额度](#额度)）
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

```json
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
- 每 Key **120 / 分钟** + **全局闸门 90 / 分钟**（跟 `/api/player` 共用）；
  命中缓存**不吃**这个额度 —— 那 120 是**真的上游取数**配额
- 错误码同 [`/api/player`](#错误码-1)

### 网站内部接口 `/web/api/card`

`hyp.firebounce.today` 用的是**同一份数据**：

```http
GET /web/api/card?name=<名字 或 UUID 或 昵称>
```

- **不需要你在浏览器里带 Key** —— Key 由服务器侧的 nginx 反向代理注入
  （`proxy_set_header Authorization "Bearer …"`），**访客永远看不到它**
- 但服务端**照样要过 Key 校验**，所以那把"网站专用 Key"的额度（默认 120 / 分钟）对整站生效；
  管理员可以用 `/apikey rate` 调它的额度
- **面向访客的限速**是按 IP 做的：**7 秒间隔 + 每分钟 6 次**（跟机器人 `/hyp` 完全一致）
- 只在服务器内部反代（`/web/api/`），不是给第三方用的接口

`/web/api/player` 同规则（也要注入的 Key），`/web/api/search` 不需要（纯本地、按 IP 60 次/分钟）。

---

## 其它接口

所有接口共用同一套 **API Key 鉴权**（`?key=` / `Authorization: Bearer` / `X-API-Key`）
和每 Key **120 / 分钟**的限制。

### `/api/tags` —— 只要反作弊标签（最轻量）

```http
GET /api/tags?name=<名字|UUID|昵称>
```

```json
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

```json
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

`/api/player`、`/api/player/card`、`/api/tags` 这几个**会真的访问外部服务**，
除了每 Key 120/分钟（**按响应体积加权**，见[额度](#额度)），还有一道**全局闸门**：**合计每分钟最多 90 次**（`429` 表示超了）。
本地接口（`/api/denick`、`/api/search`、`/api/recent`、`/api/nick-history`）不受这道闸门限制。

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

### 和官方有什么区别

| | 官方 `api.hypixel.net` | 这个反代 |
|---|---|---|
| Key | Hypixel 的 Key | **本站 `/apikey` 申请的那把**（`bsk_` 开头） |
| 额度 | 一把 300 / 分钟 | **多把池子叠加**，一把失效自动换下一把；本站计费另按**响应体积**加权（见[额度](#额度)） |
| 认证方式 | `API-Key: <key>` | `Authorization: Bearer <key>` / `?key=` / `X-API-Key` |
| 限流头 | `ratelimit-*` | **同样透传**，可据此自己限速 |

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

### 覆盖范围

**所有 `/v2/*` 端点**都转发，不限于下面这几个常用例子：

| 路径 | 说明 |
|---|---|
| `/v2/player?uuid=` | 玩家完整数据 |
| `/v2/status?uuid=` | 在线状态 |
| `/v2/recentgames?uuid=` | 最近对局 |
| `/v2/guild?player=` | 公会 |

### 为什么不能拿真 Hypixel Key 来用

**故意的。** 如果这里接受别人自己的 Hypixel Key，这个域名就成了**开放代理** ——
任何人都能借它隐藏真实来源、并白嫖我们 Key 池的额度。所以**只认本站 `bsk_` Key**，
其它一律 `401 invalid_key`。

### 一个已知情况：Cloudflare 会挡特定 User-Agent

这个域名在 Cloudflare 后面并开启了 Browser Integrity Check，**`python-urllib`
的默认 UA 会被挡，返回 `403 error code: 1010`**（请求根本没到我们这边）。

浏览器、`curl`、`requests`、各种 SDK 都自带 UA，**不受影响**。只有裸用 Python
`urllib` 且不设 UA 的脚本会撞上 —— 那时随便设一个 `User-Agent` 头即可：

```python
req = urllib.request.Request(url, headers={"User-Agent": "my-app/1.0"})
```

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

## 变更记录

| 日期 | 变更 |
|---|---|
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