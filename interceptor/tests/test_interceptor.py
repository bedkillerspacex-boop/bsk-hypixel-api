# -*- coding: utf-8 -*-
"""
Python 拦截器测试。

    python -m unittest discover -s tests -v
    （或者直接 python tests/test_interceptor.py）

除了纯函数，最后一段会**真起一个本地假反代**，用 requests / urllib
真发一遍请求，确认补丁真的生效 —— 只测纯函数会漏掉"补丁压根没挂上"这种问题。
"""

from __future__ import annotations

import json
import os
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bsk_hypixel_interceptor as bsk  # noqa: E402

KEY = "bsk_TESTKEY"

try:
    import requests
    HAVE_REQUESTS = True
except ImportError:
    HAVE_REQUESTS = False


class UrlRewriteTest(unittest.TestCase):
    def setUp(self):
        bsk.uninstall()
        bsk.configure(proxy_base=bsk.PROXY_BASE, target_hosts=("api.hypixel.net",),
                      api_key=KEY, force_key=True)

    def test_official_host_is_rewritten(self):
        self.assertEqual(
            bsk.rewrite_url("https://api.hypixel.net/v2/player?uuid=abc"),
            "https://hyp-api.firebounce.today/v2/player?uuid=abc")

    def test_path_and_query_are_preserved(self):
        u = bsk.rewrite_url("https://api.hypixel.net/v2/skyblock/auctions?page=3&x=1")
        self.assertIn("/v2/skyblock/auctions", u)
        self.assertIn("page=3", u)
        self.assertIn("x=1", u)

    def test_other_hosts_untouched(self):
        for u in ("https://example.com/a",
                  "https://api.mojang.com/users/profiles/minecraft/x",
                  "https://api.firebounce.today/api/denick?nick=x"):
            self.assertEqual(bsk.rewrite_url(u), u, u)

    def test_lookalike_hosts_are_not_targets(self):
        """
        ★ 最容易写错的地方: 用 in / endswith 判断就会把钓鱼站当目标,
          等于主动把你的 bsk_ Key 送给攻击者。
        """
        for u in ("https://api.hypixel.net.evil.com/v2/x",
                  "https://evilapi.hypixel.net.attacker.io/v2/x",
                  "https://notapi.hypixel.net/v2/x"):
            self.assertEqual(bsk.rewrite_url(u), u, "%s 不该被改" % u)

    def test_proxy_url_not_rewritten_again(self):
        u = "https://hyp-api.firebounce.today/v2/player?uuid=abc"
        self.assertEqual(bsk.rewrite_url(u), u)


class KeyPolicyTest(unittest.TestCase):
    def setUp(self):
        bsk.uninstall()
        bsk.configure(proxy_base=bsk.PROXY_BASE, target_hosts=("api.hypixel.net",),
                      api_key=KEY, force_key=True)

    def test_injects_when_absent(self):
        h = bsk.apply_key({"Content-Type": "application/json"})
        self.assertEqual(h.get("API-Key"), KEY)

    def test_force_overwrites_and_removes_old_key(self):
        h = bsk.apply_key({"API-Key": "their-own-key"})
        self.assertEqual(h.get("API-Key"), KEY)
        self.assertNotIn("their-own-key", list(h.values()))

    def test_force_removes_bearer_authorization(self):
        h = bsk.apply_key({"Authorization": "Bearer their-own-key"})
        self.assertNotIn("Authorization", h)
        self.assertEqual(h.get("API-Key"), KEY)

    def test_x_api_key_also_removed(self):
        h = bsk.apply_key({"X-API-Key": "their-own-key"})
        self.assertNotIn("X-API-Key", h)
        self.assertEqual(h.get("API-Key"), KEY)

    def test_no_force_keeps_callers_key(self):
        bsk.configure(force_key=False)
        h = bsk.apply_key({"API-Key": "their-own-key"})
        self.assertEqual(h.get("API-Key"), "their-own-key")

    def test_no_force_fills_in_when_absent(self):
        bsk.configure(force_key=False)
        self.assertEqual(bsk.apply_key({}).get("API-Key"), KEY)

    def test_key_in_query_counts_as_present(self):
        bsk.configure(force_key=False)
        h = bsk.apply_key({}, "https://hyp-api.firebounce.today/v2/x?key=zzz")
        self.assertNotIn("API-Key", h)

    def test_empty_key_injects_nothing(self):
        bsk.configure(api_key="")
        self.assertNotIn("API-Key", bsk.apply_key({}))

    def test_headers_input_is_not_mutated(self):
        """别把调用方传进来的 dict 就地改了 —— 那是很难查的副作用。"""
        original = {"API-Key": "their-own-key"}
        bsk.apply_key(original)
        self.assertEqual(original, {"API-Key": "their-own-key"})

    def test_case_insensitive_header_names(self):
        h = bsk.apply_key({"aPi-kEy": "their-own-key"})
        self.assertEqual(h.get("API-Key"), KEY)
        self.assertNotIn("their-own-key", list(h.values()))


class ConfigTest(unittest.TestCase):
    def setUp(self):
        bsk.uninstall()
        bsk.configure(**bsk.DEFAULTS)

    def test_unknown_option_is_rejected(self):
        """打错字要报错, 不能静默忽略 —— 否则用户以为配上了。"""
        with self.assertRaises(KeyError):
            bsk.configure(api_kye="bsk_x")

    def test_stats_exposes_installed_state(self):
        s = bsk.stats()
        self.assertIn("installed", s)
        self.assertIn("intercepted", s)

    def test_mask_key(self):
        self.assertEqual(bsk.mask_key("short"), "short")
        self.assertIn("…", bsk.mask_key("bsk_" + "a" * 32))


# ---------------------------------------------------------------------------
# 真发请求：本地假反代
# ---------------------------------------------------------------------------

class _FakeProxy(BaseHTTPRequestHandler):
    seen = []

    def do_GET(self):
        _FakeProxy.seen.append({
            "path": self.path,
            "key": self.headers.get("API-Key") or self.headers.get("X-API-Key") or "",
            "auth": self.headers.get("Authorization") or "",
        })
        body = json.dumps({"ok": True, "path": self.path}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


class LivePatchTest(unittest.TestCase):
    """
    ★ 真起一个假反代、真发请求 —— 只测纯函数会漏掉"补丁没挂上"。
    """

    @classmethod
    def setUpClass(cls):
        _FakeProxy.seen = []
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), _FakeProxy)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = "http://127.0.0.1:%d" % cls.port

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        bsk.uninstall()
        _FakeProxy.seen = []
        # 把"官方域名"当成 127.0.0.1，反代也指向它 —— 这样补丁会真的介入
        bsk.install(proxy_base=self.base, target_hosts=("127.0.0.1",),
                    api_key="bsk_LOCALTEST", force_key=True)

    def tearDown(self):
        bsk.uninstall()

    @unittest.skipUnless(HAVE_REQUESTS, "没装 requests")
    def test_requests_is_intercepted_and_key_replaced(self):
        r = requests.get(self.base + "/v2/status", headers={"API-Key": "their-key"}, timeout=10)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(_FakeProxy.seen), 1)
        self.assertEqual(_FakeProxy.seen[0]["key"], "bsk_LOCALTEST")
        self.assertEqual(_FakeProxy.seen[0]["path"], "/v2/status")

    @unittest.skipUnless(HAVE_REQUESTS, "没装 requests")
    def test_requests_with_bearer_is_replaced(self):
        requests.get(self.base + "/v2/player?uuid=x",
                     headers={"Authorization": "Bearer their-key"}, timeout=10)
        got = _FakeProxy.seen[-1]
        self.assertEqual(got["key"], "bsk_LOCALTEST")
        self.assertEqual(got["auth"], "", "旧的 Bearer 应该被删掉")

    @unittest.skipUnless(HAVE_REQUESTS, "没装 requests")
    def test_requests_session_also_intercepted(self):
        s = requests.Session()
        s.get(self.base + "/v2/x", timeout=10)
        self.assertEqual(_FakeProxy.seen[-1]["key"], "bsk_LOCALTEST")

    @unittest.skipUnless(HAVE_REQUESTS, "没装 requests")
    def test_non_target_is_not_intercepted(self):
        """非目标不该被塞 key。"""
        before = len(_FakeProxy.seen)
        try:
            requests.get("https://example.com/", timeout=5)
        except Exception:
            pass
        self.assertEqual(len(_FakeProxy.seen), before)

    def test_urllib_is_intercepted(self):
        import urllib.request
        with urllib.request.urlopen(self.base + "/v2/status", timeout=10) as r:
            self.assertEqual(r.status, 200)
        self.assertEqual(_FakeProxy.seen[-1]["key"], "bsk_LOCALTEST")

    def test_urllib_request_object_is_intercepted(self):
        import urllib.request
        req = urllib.request.Request(self.base + "/v2/y", headers={"API-Key": "their-key"})
        with urllib.request.urlopen(req, timeout=10) as r:
            self.assertEqual(r.status, 200)
        self.assertEqual(_FakeProxy.seen[-1]["key"], "bsk_LOCALTEST")

    @unittest.skipUnless(HAVE_REQUESTS, "没装 requests")
    def test_uninstall_restores(self):
        bsk.uninstall()
        _FakeProxy.seen = []
        # 还原之后, 调用方自己的 key 原样发出去
        requests.get(self.base + "/v2/z", headers={"API-Key": "their-key"}, timeout=10)
        self.assertEqual(_FakeProxy.seen[-1]["key"], "their-key")

    @unittest.skipUnless(HAVE_REQUESTS, "没装 requests")
    def test_context_manager_restores_config(self):
        bsk.uninstall()
        bsk.configure(api_key="bsk_OUTER")
        with bsk.intercept(api_key="bsk_INNER"):
            requests.get(self.base + "/v2/c", timeout=10)
            self.assertEqual(_FakeProxy.seen[-1]["key"], "bsk_INNER")
        self.assertEqual(bsk.stats()["config"]["api_key"], "bsk_OUTER")


if __name__ == "__main__":
    unittest.main(verbosity=2)
