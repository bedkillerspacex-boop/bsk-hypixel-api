# BSK denick 查询 API

把 **Hypixel 昵称（nick）** 反查成 **真实玩家 ID**。

```
Base URL:  https://api.firebounce.today
Endpoint:  GET / POST  /api/denick
```

> ⚠️ **数据来自社区记录**（Discord 服务器 `swag` 里 `Hypixel Tracker` bot 发的内容），
> **不是 Hypixel 官方数据**，可能过期或有错。**同名 ≠ 同一人**是常态，见文末 [注意事项](#注意事项重要)。

---

## 目录

- [申请 API Key](#申请-api-key)
- [鉴权](#鉴权)
- [接口](#接口)
- [返回格式](#返回格式)
- [错误码](#错误码)
- [频率限制](#频率限制)
- [示例代码](#示例代码)
- [注意事项](#注意事项重要)

---

## 申请 API Key

在 **QQ 里私聊 BSK 机器人**（不是群聊）：

```
① /apikey 你的QQ号        ->  机器人往 <你的QQ号>@qq.com 发一个 6 位验证码
② /apikey verify 654321   ->  验证通过, 申请进入管理员审批队列
③ 管理员同意后             ->  Key 会发到你的 QQ 邮箱
```

- **必须提供真实 QQ 号**：QQ bot 平台只给 openid、拿不到 QQ 号，所以让你自己填，
  再用邮件验证，确保申请人身份是真的
- **同一个人只发一把 Key**：已经有的再申请还是同一把（不会重复签发）
- Key 丢了：再发一次 `/apikey`，会重新发到你的邮箱
- 管理员：`/apikey list` 查看已发出的 Key、`/apikey revoke <key>` 停用

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
  "query": "zzz_nope"
}
```

---

## 错误码

| HTTP | `error` | 意思 | 怎么处理 |
|---|---|---|---|
| 400 | `missing_param` | 既没给 `nick` 也没给 `uuid` | 补参数 |
| 401 | `missing_key` | 没带 Key | 加 `Authorization` 头 |
| 401 | `invalid_key` | Key 不存在 | 检查 Key 有没有抄错 |
| 401 | `key_disabled` | Key 被管理员停用了 | 找管理员重新申请 |
| 404 | `not_found` | 索引里没有这个昵称/UUID | 可能没被记录过，或拼错了 |
| 429 | `rate_limited` | 超过频率限制 | 退避重试（见下） |
| 500 | `internal` | 服务内部错误 | 稍后重试 |

---

## 频率限制

**每把 Key 120 次 / 分钟**，超过返回 `429`。

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
    "ping_ms": 201, "ping_region": "亚洲(推测)",
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

### 频率限制

- 每把 Key **120 次/分钟**（跟 `/api/denick` 共用）
- **额外**还有一道**全局限流**：该接口每分钟最多 **90 次**
  （因为它会真的访问 Hypixel/Urchin，得保护上游配额）→ 超了返回 `429`
- 命中磁盘缓存时很快（毫秒级）；冷查询约 **1~3 秒**

### 错误码

跟 `/api/denick` 相同，另外多了：

| HTTP | `error` | 意思 |
|---|---|---|
| 502 | `upstream_failed` | 上游（Hypixel 等）整体失败，稍后重试 |

---

## 其它接口

所有接口共用同一套 **API Key 鉴权**（`?key=` / `Authorization: Bearer` / `X-API-Key`）
和每 Key **120 次/分钟**的限制。

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

### `/api/card.png` —— 直接拿卡片图

```http
GET /api/card.png?name=<名字>
```

返回 `image/png`（默认约 160 KB，1140px 宽），带 `Cache-Control: max-age=300`，
可以直接嵌网页或插件里：

```html
<img src="https://api.firebounce.today/api/card.png?name=bsk10ww&key=bsk_xxx">
```

> ⚠️ 这个接口**会真的渲染卡片**（跑 Hypixel/Urchin/Mojang 一圈），冷查询 1~3 秒，
> 所以跟 `/api/player` 一样受**全局闸门**限制。Key 放在 URL 里会被访问日志记下，
> 内部用建议走请求头。

### 全局闸门（重要）

`/api/player`、`/api/tags`、`/api/card.png` 这三个**会真的访问外部服务**，
除了每 Key 120/分钟，还有一道**全局限流**：**合计每分钟最多 90 次**（`429` 表示超了）。
本地接口（`/api/denick`、`/api/search`、`/api/recent`、`/api/nick-history`）不受这道闸门限制。

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
| 2026-09-22 | 返回体新增 `names` / `nicks` / `nick_count`（同一个 UUID 的所有名字与昵称）；文档强调 **UUID 是不变主键，正版 ID 会变** |
| 2026-09-21 | 接口上线：`GET/POST /api/denick`，API Key 鉴权，每 Key 120 次/分钟 |