#!/usr/bin/env python3
"""
BSK 公共查询 API —— **全端点**演示（只用标准库，无第三方依赖）

用法:
    export BSK_KEY="bsk_你的key"
    python3 api_demo.py                      # 全部端点跑一遍(默认查 bsk10ww)
    python3 api_demo.py theoshadow           # 换查询目标(昵称/改名前的旧名都行)
    python3 api_demo.py --base http://127.0.0.1:18096    # 内网/自测时覆盖地址

覆盖的端点:
    0  GET /api                       端点清单(自己发现用)
    1  GET /api/denick                昵称 -> 真名/UUID
   1.5 /api/denick?prefer=…           查询偏好: 先按 nick / ign / uuid 哪种查
    2  GET /api/player                身份 + 战绩 + 可疑度 + 标签 + 地区 + 延迟
    3  GET /api/tags                  只要标签 + 可疑度分(轻量)
    4  GET /api/player/card           整张卡的内容(JSON, 不出图)
    5  GET /api/card.png              直接出图(PNG)
    6  GET /api/search                昵称/真名模糊搜索
    7  GET /api/recent                最近记录到的昵称(轮询用)
    8  GET /web/api/token             网站短期令牌 -> 拿它再查 /api/...
    9  版本化                         不带版本 / v1 / v1-YYMMDD, 写错的版本 404

认证: 三种写法等价, 任选一种(推荐请求头, 免得 Key 进访问日志)
    Authorization: Bearer bsk_xxx
    X-API-Key: bsk_xxx
    ?key=bsk_xxx

文档: https://github.com/bedkillerspacex-boop/bsk-denick-api
申请 Key: 在 QQ 群里发  /apikey 你的QQ号  (机器人发不出私聊, Key 走你的 QQ 邮箱)
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://api.firebounce.today"      # 公开 API
WEB = "https://hyp.firebounce.today"       # 网站(取短期令牌用)
KEY = os.environ.get("BSK_KEY", "")


# --------------------------------------------------------------------------
# 一个最小的调用封装: 统一处理 JSON / 错误体 / 响应头
# --------------------------------------------------------------------------
def call(path, params=None, *, key=None, base=None, raw=False, timeout=60):
    """
    返回 (status, headers, body)。body: raw=False 时是 dict, raw=True 时是 bytes。

    key=  不传 -> 用环境变量 BSK_KEY
    key=""     -> 匿名请求(用来演示"不给 Key 会怎样")
    """
    url = (base or BASE) + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    headers = {"Accept": "application/json", "User-Agent": "bsk-api-demo/1.0"}
    k = KEY if key is None else key
    if k:
        headers["Authorization"] = "Bearer " + k
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read()
            return r.status, dict(r.headers), (body if raw else json.loads(body))
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            return e.code, dict(e.headers), (body if raw else json.loads(body))
        except Exception:
            return e.code, dict(e.headers), (body if raw else {"raw": body[:200]})


def show(status, d, keys=None):
    """打印一行结果: 成功就挑几个字段, 失败就把 error/message 打出来。"""
    if not isinstance(d, dict):
        print("    HTTP %s  (非 JSON, %d 字节)" % (status, len(d or b"")))
        return d
    if not d.get("ok"):
        print("    HTTP %s  ❌ %s: %s" % (status, d.get("error"), d.get("message")))
        return d
    data = d.get("data")
    if keys and isinstance(data, dict):
        print("    HTTP %s  %s" % (status, "  ".join(
            "%s=%s" % (k, data.get(k)) for k in keys if data.get(k) is not None)))
    elif isinstance(data, dict):
        print("    HTTP %s  %s" % (status, json.dumps(data, ensure_ascii=False)[:160]))
    elif isinstance(data, list):
        print("    HTTP %s  %d 条" % (status, len(data)))
    else:
        print("    HTTP %s  %s" % (status, str(data)[:160]))
    return d


def step(n, title):
    print("\n%s) %s" % (n, title))


def main(argv):
    args = [a for a in argv[1:]]
    base, web = BASE, WEB
    if "--base" in args:
        i = args.index("--base")
        base = args[i + 1]
        args = args[:i] + args[i + 2:]
        web = base                                   # 内网自测时两边同址
    target = (args[0] if args else "bsk10ww")
    nick = "theoshadow"                              # denick 用的昵称样本

    if not KEY:
        print("⚠️  没设置 BSK_KEY —— 下面除 8) 之外都会是 401。")
        print("   export BSK_KEY=\"bsk_你的key\"   然后重跑\n")
    print("base=%s   查询目标=%s" % (base, target))

    step(0, "GET /api —— 端点清单(不需要 Key 也能看)")
    st, _, d = call("/api", key="", base=base)
    if d.get("ok"):
        for e in d["data"]["endpoints"]:
            print("    %-22s %s" % (e["endpoint"], e["desc"]))
        print("    latest=%s  docs=%s" % (d["data"]["latest"], d["data"]["docs"]))
    else:
        show(st, d)

    step(1, "GET /api/denick?nick=%s —— 昵称 -> 真名/UUID" % nick)
    st, _, d = call("/api/denick", {"nick": nick}, base=base)
    show(st, d, ["nick", "ign", "uuid", "seen_at", "nick_count"])

    step(1.5, "查询偏好 prefer —— 先按哪种方式查(nick / ign / uuid)")
    st, _, d = call("/api/denick", {"nick": nick, "prefer": "ign"}, base=base)
    show(st, d, ["matched_by", "nick", "uuid"])
    print("    ↑ matched_by 才是**实际**命中的方式; prefer=ign 只是让它先按真名试。")
    print("      一个名字既是甲的昵称、又是乙的真名时, 顺序就决定查到谁。")
    st, _, d = call("/api/denick", {"nick": nick, "prefer": "nope"}, base=base)
    print("    写错的话: HTTP %s  error=%s  accepted=%s"
          % (st, (d or {}).get("error"), (d or {}).get("accepted")))
    st, _, d = call("/api/denick", {"nick": "zzz_nobody_here", "prefer": "ign,nick"}, base=base)
    print("    查不到时: HTTP %s  error=%s  tried=%s  ← 本次按什么顺序试过"
          % (st, (d or {}).get("error"), (d or {}).get("tried")))

    step(2, "GET /api/player?name=%s —— 会真去打 Hypixel(有全局限流)" % target)
    st, h, d = call("/api/player", {"name": target}, base=base)
    show(st, d, ["name", "rank", "network_level", "online", "game",
                 "country", "ping_ms", "ping_region", "cache_age"])
    if isinstance(d, dict) and d.get("ok"):
        bw = (d["data"].get("bedwars") or {})
        print("     起床战争: 等级=%s 胜场=%s FKDR=%s 胜率=%s" % (
            bw.get("level"), bw.get("wins"), bw.get("fkdr"), bw.get("wlr")))
        print("     可疑度=%s / 可信=%s   (API版本头: %s)"
              % ((d["data"].get("suspicion") or {}).get("score"),
                 (d["data"].get("suspicion") or {}).get("legit"),
                 h.get("X-API-Version")))
        if d["data"].get("warn"):
            print("     ⚠️ warn=%s" % d["data"]["warn"])
            print("        ↑ 这是**我们没取到**, 不是这人没数据 —— 别拿它下结论")

    step(3, "GET /api/tags —— 只要反作弊标签(轻量, 适合批量)")
    st, _, d = call("/api/tags", {"name": target}, base=base)
    if isinstance(d, dict) and d.get("ok"):
        t = d["data"].get("tags") or []
        print("    HTTP %s  标签 %d 个: %s" % (st, len(t), ", ".join(
            str(x.get("label") or x.get("tag_type")) for x in t) or "(无)"))
        print("     原始结构: %s" % json.dumps(t[:2], ensure_ascii=False)[:200])
    else:
        show(st, d)

    step(4, "GET /api/player/card —— 整张卡的内容(JSON)")
    st, _, d = call("/api/player/card", {"name": target}, base=base)
    if isinstance(d, dict) and d.get("ok"):
        c = d["data"]
        print("    HTTP %s  左列 %d 块 / 右列 %d 块  avatar=%s"
              % (st, len(c.get("left") or []), len(c.get("right") or []),
                 "有" if c.get("avatar") else "无"))
        for blk in (c.get("left") or []) + (c.get("right") or []):
            if blk.get("kind") in ("account", "score"):
                for cell in (blk.get("cells") or []):
                    if "地区" in str(cell.get("label") or ""):
                        print("     地区那一格 = %s" % (cell.get("value") or cell.get("v")))
    else:
        show(st, d)

    step(5, "GET /api/card.png —— 直接出图")
    st, h, body = call("/api/card.png", {"name": target}, base=base, raw=True)
    if st == 200 and body[:4] == b"\x89PNG":
        fn = "card_%s.png" % target
        with open(fn, "wb") as f:
            f.write(body)
        print("    HTTP 200  PNG %d 字节 -> %s   (X-Card-Age=%s)"
              % (len(body), fn, h.get("X-Card-Age")))
    else:
        print("    HTTP %s  %s" % (st, body[:120]))

    step(6, "GET /api/search?q=bsk —— 模糊搜索(本地索引, 很快)")
    st, _, d = call("/api/search", {"q": "bsk", "limit": 5}, base=base)
    if isinstance(d, dict) and d.get("ok"):
        print("    HTTP %s  命中 %d 条:" % (st, d["data"]["count"]))
        for r in d["data"]["results"][:5]:
            print("     %-18s -> %-18s %s" % (r.get("nick"), r.get("ign"),
                                              (r.get("uuid") or "")[:8]))
    else:
        show(st, d)

    step(7, "GET /api/recent?limit=5 —— 最近记录(轮询用 since=)")
    st, _, d = call("/api/recent", {"limit": 5}, base=base)
    if isinstance(d, dict) and d.get("ok"):
        print("    HTTP %s  返回 %d 条, max_seen_ts=%s"
              % (st, d["data"]["count"], d["data"]["max_seen_ts"]))
        for r in d["data"]["records"][:5]:
            print("     %-18s -> %s" % (r.get("nick"), r.get("ign")))
    else:
        show(st, d)

    step(8, "网站玩法: /web/api/token 取短期令牌 -> 拿它查 /api(不给访客发 Key)")
    st, _, d = call("/web/api/token", key="", base=web)
    if isinstance(d, dict) and d.get("ok"):
        tok = (d.get("data") or {}).get("token")
        print("    令牌 %s…  绑IP 15分钟 60次/分" % (tok or "")[:16])
        st2, _, d2 = call("/api/player/card/v1", {"name": target}, key=tok, base=base)
        print("    用令牌查 /api/player/card/v1 -> HTTP %s  ok=%s"
              % (st2, d2.get("ok") if isinstance(d2, dict) else "?"))
    else:
        show(st, d)

    step(9, "版本化: 不带版本 = 最新; v1 = 最新的 v1; v1-YYMMDD = 钉死那一版")
    st, h, d = call("/api/denick", {"nick": nick}, base=base)
    print("    /api/denick          -> HTTP %s  X-API-Version=%-10s latest=%s"
          % (st, h.get("X-API-Version"), h.get("X-API-Latest")))
    st, h, d = call("/api/denick/v1", {"nick": nick}, base=base)
    print("    /api/denick/v1       -> HTTP %s  X-API-Version=%-10s latest=%s"
          % (st, h.get("X-API-Version"), h.get("X-API-Latest")))
    # 日期版: 从 X-API-Latest 里拿, 所以这个示例永远跟着线上最新版走
    dated = h.get("X-API-Latest") or "v1"
    st, h2, d = call("/api/denick/%s" % dated, {"nick": nick}, base=base)
    print("    /api/denick/%-8s -> HTTP %s  X-API-Version=%-10s (钉死这一版)"
          % (dated, st, h2.get("X-API-Version")))
    st, _, d = call("/api/denick/v9", {"nick": nick}, base=base)
    print("    /api/denick/v9       -> HTTP %s (未来的版本号要拒掉)" % st)
    show(st, d)

    step(10, "不给 Key 会怎样(匿名)")
    st, _, d = call("/api/denick", {"nick": nick}, key="", base=base)
    show(st, d)
    print("\n完成。")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
