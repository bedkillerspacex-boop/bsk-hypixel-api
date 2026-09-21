#!/usr/bin/env python3
"""
BSK denick 查询 API —— Python 客户端示例（只用标准库，无第三方依赖）

用法:
    export BSK_KEY="bsk_你的key"
    python3 denick_client.py theoshadow
    python3 denick_client.py --uuid 694cd52b-8197-45f0-b28d-ad73eb299699
    python3 denick_client.py --batch nick1 nick2 nick3
    python3 denick_client.py --json theoshadow        # 打印原始 JSON

文档: https://github.com/bedkillerspacex-boop/bsk-denick-api
申请 Key: 在 QQ 里私聊 BSK 机器人发  /apikey 你的QQ号
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.firebounce.today/api/denick"
KEY = os.environ.get("BSK_KEY", "")


class DenickError(Exception):
    def __init__(self, status, error, message):
        super().__init__("%s (%s): %s" % (status, error, message))
        self.status, self.error, self.message = status, error, message


def denick(nick=None, uuid=None, *, key=None, timeout=10, retries=2):
    """
    查一个昵称 / UUID。

    成功返回 dict（完整字段见文档）:
        {
          "nick": "theoshadow",         # 查到的昵称
          "ign": "bsk10ww",             # 真实正版 ID
          "uuid": "694cd52b...",        # 真实玩家 UUID（无横线小写）
          "seen_at": "2026-08-20 21:52",
          "seen_ts": 1787233926,
          "names": ["bsk10ww"],         # 同一个 UUID 用过的**所有**正版 ID
          "nicks": ["theoshadow"],      # 同一个 UUID 用过的**所有**昵称（新的在前）
          "nick_count": 1
        }

    ⚠️ UUID 不会变、正版 ID 会变 —— 要长期跟踪一个玩家请存 `uuid`。
    查不到抛 DenickError(error="not_found")。
    遇到 429 会自动退避重试（1s, 2s, 4s...）。

    Key 走 **请求头** 而不是 URL —— 否则会出现在访问日志里。
    """
    key = key or KEY
    if not key:
        raise DenickError(0, "no_key", "环境变量 BSK_KEY 没设置")
    if not nick and not uuid:
        raise DenickError(0, "missing_param", "要传 nick 或 uuid")

    params = {"nick": nick} if nick else {"uuid": uuid}
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={
        "Authorization": "Bearer " + key,
        "Accept": "application/json",
        "User-Agent": "bsk-denick-example/1.0",
    })

    wait = 1.0
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                d = json.loads(r.read().decode("utf-8"))
            if not d.get("ok"):
                raise DenickError(200, d.get("error"), d.get("message"))
            return d["data"]
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            try:
                d = json.loads(body)
            except Exception:
                d = {"error": "http_%s" % e.code, "message": body[:120]}
            if e.code == 429 and attempt < retries:
                time.sleep(wait)
                wait *= 2
                continue
            raise DenickError(e.code, d.get("error"), d.get("message"))


def track_player(uuid, *, key=None):
    """
    长期跟踪用: 拿到一个 UUID 的**当前名字**和**所有历史名字/昵称**。

    这就是"存 uuid 而不是存 ign"的用法 —— 他改名了你也跟得住。
    """
    d = denick(uuid=uuid, key=key)
    return {
        "uuid": d.get("uuid"),
        "current_name": d.get("ign"),
        "all_names": d.get("names") or [],
        "nicks": d.get("nicks") or [],
    }


def main(argv):
    args = argv[1:]
    as_json = "--json" in args
    args = [a for a in args if a != "--json"]
    if not args:
        print(__doc__)
        return 1
    if args[0] == "--uuid":
        rows = [(None, args[1])] if len(args) > 1 else []
    elif args[0] == "--batch":
        rows = [(n, None) for n in args[1:]]
    else:
        rows = [(n, None) for n in args]
    if not rows:
        print(__doc__)
        return 1

    rc = 0
    for nick, uid in rows:
        try:
            d = denick(nick, uid)
            if as_json:
                print(json.dumps(d, ensure_ascii=False, indent=2))
                continue
            print("%-18s -> %-18s %s   (%s)"
                  % (d.get("nick") or uid, d.get("ign"), d.get("uuid") or "-",
                     d.get("seen_at") or "-"))
            names = d.get("names") or []
            nicks = d.get("nicks") or []
            if len(names) > 1:
                print("%-18s    ⚠️ 这个 UUID 用过 %d 个名字: %s"
                      % ("", len(names), ", ".join(names)))
            if nicks:
                show = ", ".join(nicks[:5]) + (" …" if len(nicks) > 5 else "")
                print("%-18s    昵称 %d 个: %s" % ("", len(nicks), show))
        except DenickError as e:
            rc = 1
            print("%-18s -> ❌ %s: %s" % (nick or uid, e.error, e.message))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
