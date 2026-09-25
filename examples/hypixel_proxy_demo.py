#!/usr/bin/env python3
"""
Hypixel 官方 API 反代 —— 示例。

★ 这个文件演示的核心只有一件事: **把 base url 从 api.hypixel.net 换掉**。
  端点、参数、返回的 JSON 全部与 Hypixel 官方一致, 所以**写代码请以官方文档为准**:

      Hypixel 官方 API 入口 : https://api.hypixel.net/
      官方 API 文档 / 仓库  : https://github.com/HypixelDev/PublicAPI
      官方开发者后台        : https://developer.hypixel.net/

  下面用到的字段 (player.displayname / player.stats.Bedwars ...) 都是**官方**的
  结构, 我们没有改动任何一个字节。

认证: 用本站的 bsk_ Key (在 QQ 群里发 /apikey 申请), **不是** Hypixel 的 Key。
      三种传法任选: API-Key 头 / Authorization: Bearer / ?key=

用法:
    export BSK_KEY=bsk_你的key
    python3 hypixel_proxy_demo.py [uuid]

    不给 uuid 就用默认那个(一个有真实战绩的玩家, 便于看出字段路径)。
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

# ↓↓↓ 全部改动就这一行: 官方是 https://api.hypixel.net
BASE = "https://hyp-api.firebounce.today"

# 默认演示用的玩家: 有真实 BedWars 战绩, 能看出 player.stats.Bedwars.* 的字段路径。
DEFAULT_UUID = "654e39a1599c4da7b711b0ebf4e73738"      # lovelycatuwu


def call(path, params=None, key=None, timeout=20):
    """按**官方**的调用方式打一次反代。返回 (status, body_bytes, headers)。"""
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url)
    # ★ 必须带 UA: 这个域名在 Cloudflare 后面开了 Browser Integrity Check,
    #   python-urllib 的默认 UA 会被挡 (403 error 1010)。
    req.add_header("User-Agent", "BSK-HypAPI-Demo/1.0")
    # ★ 认证头就叫 API-Key —— 和 Hypixel 官方**完全一样**, 所以照官方文档写就行。
    req.add_header("API-Key", key)
    try:
        r = urllib.request.urlopen(req, timeout=timeout)
        return r.status, r.read(), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers or {})


def main():
    key = (os.environ.get("BSK_KEY") or "").strip()
    if not key:
        print("请先设置 BSK_KEY=bsk_你的key")
        print("（在 QQ 群里发 /apikey 你的QQ号 申请, 走邮箱验证）")
        return 1
    uuid = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_UUID

    print("Base:", BASE)
    print("注意: 端点和字段都以 Hypixel 官方文档为准 ->")
    print("      https://github.com/HypixelDev/PublicAPI\n")

    # ---- ① /v2/player : 官方文档里的"Get Player" ----
    #   https://github.com/HypixelDev/PublicAPI/blob/master/Documentation/methods/player.md
    st, body, hdr = call("/v2/player", {"uuid": uuid}, key)
    print("GET /v2/player -> HTTP %s" % st)
    # 限流头也是官方那套, 原样透传, 可以据此自己限速
    print("  ratelimit-remaining:", hdr.get("Ratelimit-Remaining"))
    # ★ 本站计费: 一次请求扣多少额度是**按响应体积**加权的
    #   (普通 1; >1MB 扣 4; >5MB 扣 8)。X-Quota-Cost 告诉你这次花了多少。
    print("  X-Quota-Cost:", hdr.get("X-Quota-Cost"))
    if st == 200:
        d = json.loads(body)
        pl = d.get("player") or {}
        print("  success:", d.get("success"))
        print("  displayname:", pl.get("displayname"))
        # ★ 字段路径是**官方**的: player.stats.Bedwars.<stat>
        bw = ((pl.get("stats") or {}).get("Bedwars") or {})
        print("  Bedwars 胜场 (player.stats.Bedwars.wins_bedwars):",
              bw.get("wins_bedwars"))
    else:
        print("  body:", body[:200])

    # ---- ② /v2/status : 在线状态 ----
    st2, body2, _ = call("/v2/status", {"uuid": uuid}, key)
    print("\nGET /v2/status -> HTTP %s" % st2)
    if st2 == 200:
        print("  session:", json.loads(body2).get("session"))

    # ---- ③ /v2/guild : 公会 ----
    st3, body3, _ = call("/v2/guild", {"player": uuid}, key)
    print("\nGET /v2/guild -> HTTP %s" % st3)
    if st3 == 200:
        g = (json.loads(body3).get("guild") or {})
        print("  guild:", g.get("name"), "/", g.get("tag"))

    # ---- ④ 大响应: 额度按体积加权 ----
    #   /v2/resources/skyblock/items 有 ~5 MB, 扣 8 (普通请求只扣 1)。
    #   这类 resources 是**静态资源**(几天才更新), 反复用请本地缓存。
    st4, body4, hdr4 = call("/v2/resources/skyblock/collections", {}, key)
    print("\nGET /v2/resources/skyblock/collections -> HTTP %s (%d 字节)"
          % (st4, len(body4)))
    print("  X-Quota-Cost:", hdr4.get("X-Quota-Cost"), "(普通大小, 扣 1)")

    print("\n把 BASE 换成 https://api.hypixel.net 并改用你自己的 Hypixel Key,")
    print("上面每一行输出都应当完全一致 —— 这就是\"原样透传\"的意思。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
