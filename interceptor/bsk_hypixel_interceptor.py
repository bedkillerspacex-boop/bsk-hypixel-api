# -*- coding: utf-8 -*-
"""
BSK Hypixel API 反代拦截器 (Python)
================================================================

把代码里所有发给 ``api.hypixel.net`` 的请求**自动改道**到
``https://hyp-api.firebounce.today``，并把 API Key 换成你自己的 ``bsk_`` Key。

为什么需要它
------------
很多现成的 Hypixel 工具/脚本把 base URL 写死在代码深处，一个个改太麻烦。
这个拦截器在**网络层**动手 —— 业务代码一行都不用改。

支持两种调用方式（装了哪个拦哪个）::

    # requests（绝大多数脚本都用它）
    import bsk_hypixel_interceptor as bsk
    bsk.install(api_key="bsk_你的Key")
    import requests
    requests.get("https://api.hypixel.net/v2/player", params={"uuid": "..."})
    #  ↑ 上面这行会真的打到反代, 并带上你的 key

    # 标准库 urllib
    bsk.install(api_key="bsk_你的Key")
    import urllib.request
    urllib.request.urlopen("https://api.hypixel.net/v2/status?uuid=...")

也可以当上下文管理器用（用完自动还原）::

    with bsk.intercept(api_key="bsk_..."):
        requests.get("https://api.hypixel.net/v2/player", params={"uuid": "..."})

⚠️ 这个模块**只改 URL 和 header**，不碰响应体 —— 反代是透明转发，
   返回格式跟 Hypixel 官方一模一样。
"""

from __future__ import annotations

import threading

__all__ = [
    "install", "uninstall", "intercept", "configure",
    "rewrite_url", "is_target", "is_proxy_url", "needs_key", "apply_key",
    "stats", "reset_stats", "mask_key",
    "DEFAULTS", "PROXY_BASE",
]

PROXY_BASE = "https://hyp-api.firebounce.today"

DEFAULTS = {
    # 反代地址。所有命中目标的请求都会改到这里。
    "proxy_base": PROXY_BASE,
    # 哪些域名算"原来的 Hypixel API"。
    "target_hosts": ("api.hypixel.net",),
    # 你的 bsk_ Key。留空 = 不改 key（需要调用方自己带）。
    "api_key": "",
    # True = **强制**用上面的 Key（把调用方原本带的 key 丢掉）；
    # False = 调用方自己带了 key 就不动。
    "force_key": True,
    # 打印每一步改写（排查问题时开）。
    "debug": False,
}

_cfg = dict(DEFAULTS)
_lock = threading.RLock()
_installed = {"requests": False, "urllib": False}
_originals = {}
_stats = {"intercepted": 0, "key_injected": 0, "errors": 0, "last_url": ""}

# 认这些 header 名（大小写不敏感）当成"调用方带了 key"
_KEY_HEADERS = ("api-key", "x-api-key", "apikey")


# ---------------------------------------------------------------------------
# 纯函数（不依赖第三方库，可单独测试）
# ---------------------------------------------------------------------------

def _log(*a):
    if _cfg.get("debug"):
        print("[BSK反代]", *a)


def _host_of(url):
    """取 URL 的 host（小写，不含端口）。解析不出来返回空串。"""
    try:
        from urllib.parse import urlparse
        return (urlparse(str(url)).hostname or "").lower()
    except Exception:
        return ""


def is_target(url):
    """
    这个 URL 是不是"原来的 Hypixel API"？

    ★ 用 host **精确比较** —— 不能用 in / endswith，否则
      ``api.hypixel.net.evil.com`` 也会被当成目标，等于把你的
      bsk_ Key 主动送给钓鱼站。
    """
    host = _host_of(url)
    if not host:
        return False
    return host in tuple(h.lower() for h in _cfg["target_hosts"])


def rewrite_url(url):
    """
    把 URL 从 api.hypixel.net 改写到反代。

    只改 **host**，path / query **原样保留** —— 反代是透明转发，
    端点格式跟官方一模一样，不需要任何路径映射。
    不是目标的 URL 一律原样返回。
    """
    if not is_target(url):
        return url
    try:
        from urllib.parse import urlparse, urlunparse
        u = urlparse(str(url))
        p = urlparse(_cfg["proxy_base"])
        return urlunparse((p.scheme, p.netloc, u.path, u.params, u.query, u.fragment))
    except Exception:
        return url


def is_proxy_url(url):
    """这个 URL 本来就是发给反代的吗？"""
    h = _host_of(url)
    return bool(h) and h == _host_of(_cfg["proxy_base"])


def needs_key(url):
    """
    这个请求需不需要我们插手（改写 + 补 key）？

    ★ 两种都要管，不能只管第一种:
      1. 发给**官方** api.hypixel.net 的  -> 改写到反代 + 补 key
      2. 本来就发给**反代**的              -> 只补 key（地址不用改）

    第 2 种很容易被漏掉 —— 如果只在"URL 变了"时才补 key，那么
    "我把 baseURL 直接写成反代，但想让拦截器自动填 key" 这个
    完全合理的用法就会静默失效（key 不补，请求 401）。
    """
    return is_target(url) or is_proxy_url(url)


def _has_key(headers):
    """调用方是不是已经带了 key（含 ``Authorization: Bearer``）。"""
    if not headers:
        return False
    try:
        items = headers.items()
    except AttributeError:
        try:
            items = headers
        except Exception:
            return False
    for k, v in items:
        kl = str(k).lower()
        sv = str(v or "")
        if kl in _KEY_HEADERS and sv.strip():
            return True
        if kl == "authorization" and sv.strip().lower().startswith("bearer "):
            return True
    return False


def _has_key_in_query(url):
    """URL 的 query 里有没有 ``?key=``。"""
    try:
        from urllib.parse import urlparse, parse_qs
        q = parse_qs(urlparse(str(url)).query)
        return bool((q.get("key") or [""])[0].strip())
    except Exception:
        return False


def apply_key(headers, url=""):
    """
    按策略给 header 容器加上 / 覆盖上我们的 key，返回**新的 dict**。

    ``force_key=True``  -> 无条件用我们的 key，并把调用方原来的
                           key 头**删掉**（不删的话有些服务端会优先读旧
                           的那个，等于没换）
    ``force_key=False`` -> 调用方自己带了就不动

    headers 可以是 dict / requests 的 CaseInsensitiveDict / 二维可迭代。
    """
    out = {}
    if headers:
        try:
            items = list(headers.items())
        except AttributeError:
            items = list(headers)
        except Exception:
            items = []
        for k, v in items:
            out[str(k)] = v

    key = _cfg.get("api_key") or ""
    if not key:
        return out

    has_key = _has_key(out) or _has_key_in_query(url)
    if has_key and not _cfg.get("force_key"):
        return out

    if _cfg.get("force_key"):
        # ★ 删掉旧的 —— 不能只是"再加一个"，否则两个 key 同时存在时
        #   服务端读哪个是不确定的。
        for name in list(out.keys()):
            nl = name.lower()
            if nl in _KEY_HEADERS:
                del out[name]
            elif nl == "authorization" and str(out[name] or "").strip().lower().startswith("bearer "):
                del out[name]
    out["API-Key"] = key
    _stats["key_injected"] += 1
    return out


# ---------------------------------------------------------------------------
# 装 / 卸
# ---------------------------------------------------------------------------

def _install_requests():
    try:
        import requests
    except ImportError:
        return False
    if _installed["requests"]:
        return True

    orig = requests.Session.request
    _originals["requests"] = orig

    def patched(self, method, url, **kwargs):
        try:
            if needs_key(url):
                new_url = rewrite_url(url)
                kwargs["headers"] = apply_key(kwargs.get("headers"), new_url)
                _stats["intercepted"] += 1
                _stats["last_url"] = new_url
                _log("requests", (method or "GET"), url, "->", new_url)
                url = new_url
        except Exception:
            # 拦截器自己出错**绝不能**影响业务请求 —— 原样放行。
            _stats["errors"] += 1
        return orig(self, method, url, **kwargs)

    requests.Session.request = patched
    _installed["requests"] = True
    return True


def _install_urllib():
    try:
        import urllib.request as ur
        import urllib.error  # noqa: F401  (确保子模块加载)
    except ImportError:
        return False
    if _installed["urllib"]:
        return True

    orig = ur.urlopen
    _originals["urllib"] = orig

    def patched(url, data=None, timeout=None, **kw):
        try:
            if isinstance(url, ur.Request):
                new = rewrite_url(url.full_url)
                if needs_key(url.full_url):
                    headers = dict(url.headers or {})
                    headers = apply_key(headers, new)
                    req = ur.Request(new, data=url.data, headers=headers)
                    for attr in ("origin_req_host", "unverifiable", "method"):
                        try:
                            setattr(req, attr, getattr(url, attr))
                        except Exception:
                            pass
                    _stats["intercepted"] += 1
                    _stats["last_url"] = new
                    _log("urllib(Request)", url.full_url, "->", new)
                    return orig(req, data=None, timeout=timeout, **kw)
            else:
                if needs_key(url):
                    new = rewrite_url(url)
                    # ★ 传**字符串**给 urlopen 是没法加 header 的 —— 必须包成
                    #   Request，否则 key 根本送不出去（请求会 401）。
                    #   urlopen(s) 本来就等价于 urlopen(Request(s))，包一层不改变语义。
                    req = ur.Request(new, data=data, headers=apply_key({}, new))
                    _stats["intercepted"] += 1
                    _stats["last_url"] = new
                    _log("urllib", url, "->", new)
                    return orig(req, data=None, timeout=timeout, **kw)
        except Exception:
            _stats["errors"] += 1
        if timeout is None:
            return orig(url, data=data, **kw)
        return orig(url, data=data, timeout=timeout, **kw)

    ur.urlopen = patched
    _installed["urllib"] = True
    return True


def install(**options):
    """
    装上拦截器。返回装成功的名字列表，比如 ``['requests']``。

    ``install(api_key="bsk_...")``        —— 最常用
    ``install(proxy_base=..., force_key=False)``  —— 自定义
    """
    configure(**options)
    got = []
    if _install_requests():
        got.append("requests")
    if _install_urllib():
        got.append("urllib")
    if not got:
        _log("requests 和 urllib 都没拦到（requests 没装？）")
    else:
        _log("已拦截:", ", ".join(got))
    return got


def uninstall():
    """还原所有补丁。"""
    with _lock:
        if _installed.get("requests") and "requests" in _originals:
            try:
                import requests
                requests.Session.request = _originals["requests"]
            except Exception:
                pass
            _installed["requests"] = False
        if _installed.get("urllib") and "urllib" in _originals:
            try:
                import urllib.request as ur
                ur.urlopen = _originals["urllib"]
            except Exception:
                pass
            _installed["urllib"] = False


class intercept(object):
    """
    当上下文管理器用::

        with bsk.intercept(api_key="bsk_..."):
            ...   # 这里面的请求会走反代
        # 出了 with 自动还原成原来的状态
    """

    def __init__(self, **options):
        self.options = options
        self._before = None

    def __enter__(self):
        self._before = {k: v for k, v in _cfg.items()}
        install(**self.options)
        return self

    def __exit__(self, *exc):
        uninstall()
        with _lock:
            _cfg.update(self._before or {})
        return False


def configure(**options):
    """改配置（不用重装）。"""
    with _lock:
        for k, v in (options or {}).items():
            if k in _cfg:
                _cfg[k] = v
            else:
                raise KeyError("未知配置项: %r（可用: %s）"
                               % (k, ", ".join(sorted(_cfg))))
    return dict(_cfg)


def stats():
    """拦截统计，方便排查"到底拦到没有"。"""
    with _lock:
        return dict(_stats, installed=dict(_installed), config=dict(_cfg))


def reset_stats():
    for k in ("intercepted", "key_injected", "errors"):
        _stats[k] = 0
    _stats["last_url"] = ""


def mask_key(k=None):
    """打日志用的掩码。"""
    k = str(k if k is not None else _cfg.get("api_key") or "")
    return k if len(k) <= 12 else "%s…%s" % (k[:8], k[-4:])
