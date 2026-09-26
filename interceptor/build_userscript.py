# -*- coding: utf-8 -*-
"""
把「核心拦截器 + 控制面板」拼成一个**自包含**的油猴脚本。

    python build_userscript.py

为什么要 build 而不是手写一份成品:
    成品里必须内嵌核心代码（油猴 @require 远程加载在**国内经常被墙**，
    而我们的用户主要在国内 —— 拉不到就整个脚本不可用）。
    但内嵌 = 又抄一份，改了核心忘了改成品是迟早的事。
    所以核心只有 ``bsk-hypixel-interceptor.js`` 一份真源，
    成品由这个脚本生成（生成物也进仓库，方便直接安装）。

生成的成品: userscript/bsk-hypixel-proxy.user.js
"""

from __future__ import annotations

import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.join(HERE, "bsk-hypixel-interceptor.js")
PANEL = os.path.join(HERE, "userscript", "panel.js")
OUT = os.path.join(HERE, "userscript", "bsk-hypixel-proxy.user.js")

VERSION = "1.0.0"

# 油猴元数据块。@grant 是有意要的:
#   GM_getValue/GM_setValue -> 配置在所有站点之间共享（localStorage 做不到）
#   跨站点共享很重要 —— 否则用户得在每个网站上重新填一遍 Key
META = """// ==UserScript==
// @name         BSK Hypixel API 反代拦截器
// @name:en      BSK Hypixel API Proxy Interceptor
// @namespace    https://github.com/bedkillerspacex-boop/bsk-hypixel-api
// @version      {version}
// @description  把网页里所有 api.hypixel.net 的请求自动改道到 BSK 反代，并自动填入你的 bsk_ Key。带中文控制面板。
// @description:en  Redirect all api.hypixel.net requests to the BSK reverse proxy and auto-inject your bsk_ key.
// @author       BSK
// @match        *://*/*
// @run-at       document-start
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @homepageURL  https://github.com/bedkillerspacex-boop/bsk-hypixel-api
// @supportURL   https://github.com/bedkillerspacex-boop/bsk-hypixel-api/issues
// @downloadURL  https://raw.githubusercontent.com/bedkillerspacex-boop/bsk-hypixel-api/main/interceptor/userscript/bsk-hypixel-proxy.user.js
// @updateURL    https://raw.githubusercontent.com/bedkillerspacex-boop/bsk-hypixel-api/main/interceptor/userscript/bsk-hypixel-proxy.user.js
// ==/UserScript==
"""

HEAD = """/*!
 * 这个文件是**自动生成**的，别直接改 —— 改了下次 build 就没了。
 * 真源:  interceptor/bsk-hypixel-interceptor.js (核心)
 *        interceptor/userscript/panel.js          (中文面板)
 * 重新生成:  cd interceptor && python build_userscript.py
 */
"""


def read(path):
    with io.open(path, encoding="utf-8") as f:
        return f.read()


def render():
    """拼出成品的内容（build 和 --check 共用，保证两边一致）。"""
    core = read(CORE)
    panel = read(PANEL)

    # 核心代码要塞进 panel.js 里那个 '__BSK_CORE__' 占位符，
    # 用 JSON 字符串最安全（转义、换行、引号全都交给 JSON 处理）。
    core_literal = json.dumps(core, ensure_ascii=False)

    # ★ 不能用 str.replace('__BSK_CORE__', ...): 核心代码里万一出现同样的
    #   字符串就会替换错地方。这里明确只换那一处带引号的形式。
    needle = "'__BSK_CORE__'"
    if panel.count(needle) != 1:
        sys.exit("面板里的核心占位符不是恰好一处，拒绝生成（找到 %d 处）"
                 % panel.count(needle))
    panel = panel.replace(needle, core_literal)

    return META.format(version=VERSION) + HEAD + panel, core


def main():
    check = "--check" in sys.argv
    out_text, core = render()

    if check:
        # 用来防"改了核心忘了重新 build" —— 成品是提交进仓库的，
        # 不同步的话别人装到的就是旧版，而且很难发现。
        try:
            on_disk = read(OUT)
        except IOError:
            sys.exit("成品不存在: %s（先跑一次 python build_userscript.py）"
                     % os.path.relpath(OUT, HERE))
        if on_disk != out_text:
            sys.exit("成品和核心不一致 —— 跑一下 python build_userscript.py 重新生成")
        print("OK: 成品是最新的 (%d 字节)" % len(out_text.encode("utf-8")))
        return

    with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(out_text)

    print("已生成 %s (%d 字节)" % (os.path.relpath(OUT, HERE), len(out_text.encode("utf-8"))))
    print("  核心 %d 字节" % len(core.encode("utf-8")))


if __name__ == "__main__":
    main()
