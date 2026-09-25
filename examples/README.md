# 示例代码

这个仓库有**两个**服务，示例也分两组：

| 服务 | Base | 示例 |
|---|---|---|
| **denick 查询**（本站自有接口） | `https://api.firebounce.today` | `denick_*.{sh,py,js}` |
| **Hypixel 官方 API 反代** | `https://hyp-api.firebounce.today` | [`hypixel_proxy_demo.py`](hypixel_proxy_demo.py) / [`hypixel_proxy_curl.sh`](hypixel_proxy_curl.sh) |

> ⚠️ **写反代的调用代码时，请以 Hypixel 官方文档为准**，不要照抄 denick 的格式：
> https://github.com/HypixelDev/PublicAPI · https://api.hypixel.net/
> 我们只换了 base url，端点和返回的 JSON 与官方**完全一致**。

---

# denick 查询 API 示例代码

| 文件 | 语言 | 说明 |
|---|---|---|
| [`denick_curl.sh`](denick_curl.sh) | Bash | curl：三种鉴权 + POST + jq 提取 + 状态码 |
| [`denick_client.py`](denick_client.py) | Python 3 | 标准库实现，**无第三方依赖**；含 429 退避重试、`--json`、`track_player()` |
| [`denick_client.js`](denick_client.js) | Node 18+ | 原生 fetch，同样带退避重试 / `--json` / `trackPlayer()` |

# Hypixel 反代示例代码

| 文件 | 语言 | 说明 |
|---|---|---|
| [`hypixel_proxy_demo.py`](hypixel_proxy_demo.py) | Python 3 | `/v2/player`、`/v2/status`、`/v2/guild`，读出限流头，演示"只改 base url" |
| [`hypixel_proxy_curl.sh`](hypixel_proxy_curl.sh) | Bash | 同样几个端点 + 限流头 + 另一种鉴权传法 |

```bash
export BSK_KEY="bsk_你的key"
python3 hypixel_proxy_demo.py                 # 默认一个有战绩的玩家
python3 hypixel_proxy_demo.py <uuid>
bash hypixel_proxy_curl.sh
```

## 跑之前

三份示例都从环境变量读 Key，**不要把 Key 写进代码或提交到仓库**：

```bash
export BSK_KEY="bsk_你的key"
```

申请 Key：在 QQ **群里**发 `/apikey 你的QQ号`（机器人发不出私聊，Key 发到你的 QQ 邮箱）
（会发验证邮件到你的 QQ 邮箱，经管理员同意后 Key 也发到邮箱）

## 快速试

```bash
# curl（含 jq 提取）
bash denick_curl.sh theoshadow

# Python
python3 denick_client.py theoshadow
python3 denick_client.py --batch theoshadow NewLouis h3110_
python3 denick_client.py --json theoshadow          # 原始 JSON

# Node
node denick_client.js theoshadow
node denick_client.js --uuid 694cd52b-8197-45f0-b28d-ad73eb299699
```

## 预期输出

```
theoshadow         -> bsk10ww            694cd52b819745f0b28dad73eb299699   (2026-08-20 21:52)
                     昵称 1 个: theoshadow
NewLouis           -> clefer             3ac04f4bc9e54489b3cf0833693e6d0f   (2026-09-21 16:58)
                     昵称 15 个: NewLouis, thecreepybanana, TheS4dAngel, …
查不到的人          -> ❌ not_found: 索引里没有这个昵称/UUID
```

如果那个玩家**改过名**，会多一行提示（同一个 UUID 用过多个正版 ID）：

```
1998680f...        -> Youwy              1998680f818c47d09307aa8c1a4f5b3c   (…)
                     ⚠️ 这个 UUID 用过 3 个名字: HIB0BA, eflaesunhiagh, Youwy
                     昵称 113 个: TheFluffyNever, jamiea2005, LazyJoshRider, …
```

## 关于 `names` / `nicks`（2026-09-22 新增）

返回体新增三个字段：

| 字段 | 说明 |
|---|---|
| `names` | 同一个 **UUID** 用过的所有正版 ID（改过名就 >1 个） |
| `nicks` | 同一个 **UUID** 用过的所有昵称（按时间倒序） |
| `nick_count` | `nicks` 条数 |

⚠️ **UUID 不会变、正版 ID 会变**：实测 39348 条记录里 **650 个 UUID 改过名**。
要长期跟踪一个玩家，**存 `uuid`，别存 `ign`**。

```python
from denick_client import track_player
p = track_player("1998680f818c47d09307aa8c1a4f5b3c")
# {"uuid": "...", "current_name": "Youwy",
#  "all_names": ["HIB0BA", "eflaesunhiagh", "Youwy"], "nicks": [...113 个...]}
```

完整文档见上一级目录的 [`README.md`](../README.md)。
