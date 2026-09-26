// ==UserScript==
// @name         BSK Hypixel API 反代拦截器
// @name:en      BSK Hypixel API Proxy Interceptor
// @namespace    https://github.com/bedkillerspacex-boop/bsk-hypixel-api
// @version      1.0.0
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
/*!
 * 这个文件是**自动生成**的，别直接改 —— 改了下次 build 就没了。
 * 真源:  interceptor/bsk-hypixel-interceptor.js (核心)
 *        interceptor/userscript/panel.js          (中文面板)
 * 重新生成:  cd interceptor && python build_userscript.py
 */
/* ===========================================================================
 * BSK Hypixel API 反代拦截器 —— 油猴脚本的「控制面板」
 * ---------------------------------------------------------------------------
 * 这一段跑在油猴**沙箱**里（所以能用 GM_setValue 之类的跨站点存储），
 * 而真正打补丁的代码会被注入到**页面**环境去跑（见 build 出来的成品）。
 *
 * 为什么要分成两边:
 *   · 沙箱里能用 GM_* API，配置能在**所有站点之间共享**（用 localStorage
 *     的话每个域名各存一份，用户得在每个网站上重新填一遍 Key，很难用）
 *   · 页面环境里才能真的改到页面自己的 window.fetch
 * 两边靠这段代码通信: 沙箱这边负责 UI + 存配置 + 重新注入。
 * =========================================================================== */

(function () {
  'use strict';

  var CFG_KEY = 'bsk_hypixel_proxy_config';
  var DEFAULT_CFG = {
    enabled: true,
    proxyBase: 'https://hyp-api.firebounce.today',
    apiKey: '',
    forceKey: true,
  };

  function loadCfg() {
    var raw = null;
    try { raw = (typeof GM_getValue === 'function') ? GM_getValue(CFG_KEY, null) : null; } catch (e) {}
    if (!raw) {
      try { raw = localStorage.getItem(CFG_KEY); } catch (e) {}
    }
    var cfg = {};
    for (var k in DEFAULT_CFG) cfg[k] = DEFAULT_CFG[k];
    if (raw) {
      try {
        var d = (typeof raw === 'string') ? JSON.parse(raw) : raw;
        for (var k2 in d) if (d[k2] !== undefined && d[k2] !== null) cfg[k2] = d[k2];
      } catch (e) {}
    }
    return cfg;
  }

  function saveCfg(cfg) {
    var s = JSON.stringify(cfg);
    try { if (typeof GM_setValue === 'function') GM_setValue(CFG_KEY, s); } catch (e) {}
    try { localStorage.setItem(CFG_KEY, s); } catch (e) {}
  }

  function mask(k) {
    k = String(k || '');
    return k.length <= 12 ? k : k.slice(0, 8) + '…' + k.slice(-4);
  }

  // ---- 把拦截器注入页面环境 ----------------------------------------------

  var injected = null;

  /**
   * 往页面里塞一段 <script>。document-start 时 head 可能还不存在，
   * 所以要退到 documentElement，再不行就等 DOM 就绪。
   */
  function injectIntoPage(code) {
    function go() {
      var host = document.head || document.documentElement;
      if (!host) return false;
      var s = document.createElement('script');
      s.textContent = code;
      host.appendChild(s);
      s.remove();          // 执行完就删掉，别在 DOM 里留垃圾
      return true;
    }
    if (go()) return;
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', go, { once: true });
    } else {
      setTimeout(go, 0);
    }
  }

  function applyToPage(cfg) {
    var code = "/*!\n * BSK Hypixel API 反代拦截器 (JavaScript)\n * ---------------------------------------------------------------\n * 把代码里所有发给 api.hypixel.net 的请求**自动改道**到\n * https://hyp-api.firebounce.today，并把 API Key 换成你自己的 bsk_ Key。\n *\n * 为什么需要它:\n *   很多现成的 Hypixel 工具/网页/脚本里把 base URL 写死在代码深处，\n *   一个个改太麻烦。这个拦截器在**网络层**动手 —— 应用代码一行都不用改。\n *\n * 支持的拦截点:\n *   · fetch()\n *   · XMLHttpRequest\n *\n * 用法（浏览器）:\n *   <script src=\"bsk-hypixel-interceptor.js\"></script>\n *   <script>\n *     BSKHypixel.install({ apiKey: 'bsk_你的Key' });\n *   </script>\n *\n * 用法（Node / Electron）:\n *   const BSKHypixel = require('./bsk-hypixel-interceptor.js');\n *   BSKHypixel.install({ apiKey: process.env.BSK_KEY });\n *\n * ⚠️ Node 的 fetch 是全局的，能拦；但 Node 里如果用了 axios（走 http/https 模块）\n *    拦不到 —— 那种情况请用同目录的 Python 版思路，或者直接把 baseURL 改掉。\n */\n\n(function (root, factory) {\n  if (typeof module === 'object' && module.exports) {\n    module.exports = factory();\n  } else {\n    root.BSKHypixel = factory();\n  }\n})(typeof globalThis !== 'undefined' ? globalThis : this, function () {\n  'use strict';\n\n  // ---- 默认配置 ----------------------------------------------------------\n\n  var DEFAULTS = {\n    // 反代地址。所有命中目标的请求都会改到这里。\n    proxyBase: 'https://hyp-api.firebounce.today',\n    // 哪些域名算\"原来的 Hypixel API\"。\n    targetHosts: ['api.hypixel.net'],\n    // 你的 bsk_ Key。留空 = 不改 key（需要调用方自己带）。\n    apiKey: '',\n    // true = **强制**用上面的 Key（把调用方原本带的 key 丢掉）；\n    // false = 调用方自己带了 key 就不动。\n    forceKey: true,\n    // 调试日志。\n    debug: false,\n    // 拦截到之后回调 (url, 改写后的 url)。想自己记账/上报可以用。\n    onIntercept: null,\n  };\n\n  var config = Object.assign({}, DEFAULTS);\n  var installed = false;\n  var originals = { fetch: null, xhrOpen: null, xhrSetHeader: null, xhrSend: null };\n  var stats = { intercepted: 0, keyInjected: 0, lastUrl: '', errors: 0 };\n\n  // ---- 纯函数（可单独测试，不依赖 DOM）-----------------------------------\n\n  function log() {\n    if (!config.debug) return;\n    try {\n      var args = Array.prototype.slice.call(arguments);\n      args.unshift('[BSK反代]');\n      console.log.apply(console, args);\n    } catch (e) { /* 忽略 */ }\n  }\n\n  /**\n   * 这个 URL 是不是\"原来的 Hypixel API\"？\n   * 用 host 精确比较 —— 不能用 indexOf/endswith，否则\n   * `api.hypixel.net.evil.com` 也会被当成目标。\n   */\n  function isTarget(url) {\n    var host;\n    try {\n      host = new URL(url, 'https://placeholder.invalid').hostname.toLowerCase();\n    } catch (e) {\n      return false;\n    }\n    return config.targetHosts.some(function (h) {\n      return host === String(h).toLowerCase();\n    });\n  }\n\n  /**\n   * 把 URL 从 api.hypixel.net 改写到反代。\n   *\n   * 只改 **origin**，path / query **原样保留** —— 反代是透明转发，\n   * 端点格式跟官方一模一样，所以不需要任何路径映射。\n   * 不是目标的 URL 一律原样返回。\n   */\n  function rewriteUrl(url) {\n    if (!url || typeof url !== 'string') return url;\n    if (!isTarget(url)) return url;\n    try {\n      var u = new URL(url, 'https://placeholder.invalid');\n      var base = new URL(config.proxyBase);\n      u.protocol = base.protocol;\n      u.host = base.host;\n      return u.toString();\n    } catch (e) {\n      return url;\n    }\n  }\n\n  var KEY_HEADERS = ['api-key', 'x-api-key', 'apikey'];\n\n  /** 这个 URL 本来就是发给反代的吗？ */\n  function isProxyUrl(url) {\n    var host;\n    try {\n      host = new URL(url, 'https://placeholder.invalid').hostname.toLowerCase();\n    } catch (e) {\n      return false;\n    }\n    var base;\n    try {\n      base = new URL(config.proxyBase).hostname.toLowerCase();\n    } catch (e) {\n      return false;\n    }\n    return !!host && host === base;\n  }\n\n  /**\n   * 这个请求需不需要我们插手（改写 + 补 key）？\n   *\n   * ★ 两种都要管:\n   *   1. 发给**官方** api.hypixel.net 的 -> 改写到反代 + 补 key\n   *   2. 本来就发给**反代**的             -> 只补 key（地址不用改）\n   *\n   * 第 2 种很容易漏: 如果只在\"URL 变了\"时才补 key, 那\n   * \"我直接把 baseURL 写成反代, 但想让拦截器自动填 key\" 这个\n   * 完全合理的用法会**静默失效**（key 不补, 请求 401）。\n   */\n  function needsHandling(url) {\n    return isTarget(url) || isProxyUrl(url);\n  }\n\n  function isAuthHeader(name) {\n    return String(name || '').toLowerCase() === 'authorization';\n  }\n\n  function isKeyHeader(name) {\n    return KEY_HEADERS.indexOf(String(name || '').toLowerCase()) !== -1;\n  }\n\n  /**\n   * 把各种形态的 header 容器统一成 [[名字, 值], ...]。\n   * 支持: 普通对象 / Headers / 二维数组。认不出来就返回空数组。\n   */\n  function headersToPairs(headers) {\n    var out = [];\n    if (!headers) return out;\n    if (typeof Headers !== 'undefined' && headers instanceof Headers) {\n      headers.forEach(function (v, k) { out.push([k, v]); });\n      return out;\n    }\n    if (Array.isArray(headers)) {\n      headers.forEach(function (p) {\n        if (Array.isArray(p) && p.length >= 2) out.push([String(p[0]), String(p[1])]);\n      });\n      return out;\n    }\n    if (typeof headers === 'object') {\n      Object.keys(headers).forEach(function (k) { out.push([k, headers[k]]); });\n    }\n    return out;\n  }\n\n  /** 调用方是不是**已经**在某个 header 里带了 key（Bearer 也算）。 */\n  function hasKeyHeader(headers) {\n    return headersToPairs(headers).some(function (p) {\n      if (isKeyHeader(p[0])) return String(p[1] || '').trim() !== '';\n      if (isAuthHeader(p[0])) return /^bearer\\s+\\S+/i.test(String(p[1] || ''));\n      return false;\n    });\n  }\n\n  /** URL 的 query 里有没有 ?key=。 */\n  function hasKeyInQuery(url) {\n    try {\n      var u = new URL(url, 'https://placeholder.invalid');\n      var k = u.searchParams.get('key');\n      return !!(k && k.trim());\n    } catch (e) {\n      return false;\n    }\n  }\n\n  /**\n   * 决定要不要注入 key、怎么注入。\n   *\n   * forceKey=true  -> 无条件用我们的 key，并把调用方原来的 key 头**删掉**\n   *                   （不删的话有些服务端会优先读旧的那个，等于没换）\n   * forceKey=false -> 调用方自己带了就不动\n   */\n  function planKey(headers, url) {\n    var hasKey = hasKeyHeader(headers) || hasKeyInQuery(url);\n    if (!config.apiKey) return { inject: false, strip: false, hasKey: hasKey };\n    if (hasKey && !config.forceKey) return { inject: false, strip: false, hasKey: hasKey };\n    return { inject: true, strip: config.forceKey, hasKey: hasKey };\n  }\n\n  /**\n   * 对 header 列表执行注入/剥离，返回新的 [[名字, 值], ...]。\n   *\n   * ★ 输出统一用 `API-Key`（反代三种写法都收），并在浏览器里**换成 X-API-Key**\n   *   —— 见 buildFetchHeaders 的说明：跨域请求只有 CORS 白名单里的头才发得出去。\n   *\n   * strip=true 时会删掉: api-key / x-api-key / apikey 以及 Bearer 的 Authorization。\n   */\n  function applyKeyToPairs(pairs, plan, headerName) {\n    var name = headerName || 'API-Key';\n    var out = [];\n    pairs.forEach(function (p) {\n      if (plan.strip && (isKeyHeader(p[0]) || isAuthHeader(p[0]))) return;\n      out.push([p[0], p[1]]);\n    });\n    if (plan.inject) out.push([name, config.apiKey]);\n    return out;\n  }\n\n  // ---- fetch -------------------------------------------------------------\n\n  /**\n   * 浏览器里跨域请求想带自定义头，那个头必须在服务端\n   * Access-Control-Allow-Headers 白名单里，否则预检就过不去。\n   * 我们的反代白名单是 `Authorization, X-API-Key, Content-Type` ——\n   * **没有 `API-Key`**，所以浏览器场景要用 X-API-Key。\n   * Node 没有 CORS，用 API-Key 更贴近官方习惯，无差别。\n   */\n  function preferredHeaderName() {\n    var isBrowser = typeof window !== 'undefined' && typeof window.document !== 'undefined';\n    return isBrowser ? 'X-API-Key' : 'API-Key';\n  }\n\n  function buildFetchHeaders(original, url) {\n    var pairs = headersToPairs(original);\n    var plan = planKey(pairs, url);\n    if (!plan.inject && !plan.strip) return { headers: original, injected: false, hadKey: plan.hasKey };\n    var merged = applyKeyToPairs(pairs, plan, preferredHeaderName());\n    // fetch 的 header 参数用 Headers 实例最稳（普通对象无法表示同名多值）。\n    var h;\n    if (typeof Headers !== 'undefined') {\n      h = new Headers();\n      merged.forEach(function (p) { h.append(p[0], p[1]); });\n    } else {\n      h = {};\n      merged.forEach(function (p) { h[p[0]] = p[1]; });\n    }\n    return { headers: h, injected: plan.inject, hadKey: plan.hasKey };\n  }\n\n  function installFetch(target) {\n    target = target || (typeof globalThis !== 'undefined' ? globalThis : null);\n    if (!target || typeof target.fetch !== 'function') return false;\n    if (originals.fetch) return true;              // 已经装过\n    originals.fetch = target.fetch;\n\n    target.fetch = function (input, init) {\n      try {\n        var url, request = null;\n\n        if (typeof Request !== 'undefined' && input instanceof Request) {\n          request = input;\n          url = input.url;\n        } else if (input && typeof input === 'object' && typeof input.url === 'string') {\n          // 鸭子类型: 别的库造的类 Request 对象\n          request = input;\n          url = input.url;\n        } else {\n          url = String(input);\n        }\n\n        if (!needsHandling(url)) return originals.fetch.apply(this, arguments);\n\n        var newUrl = rewriteUrl(url);\n\n        if (request && typeof Request !== 'undefined') {\n          // ★ 用 Request 当 init 重建，再把 header 覆盖掉 —— 这是规范认可的写法，\n          //   能保住 method / body / signal / credentials。\n          //   自己手拼 init 很容易把 body 弄丢（尤其流式 body 还要 duplex）。\n          var rebuilt = new Request(newUrl, request);\n          var pairs = headersToPairs(rebuilt.headers)\n            .concat(headersToPairs(init && init.headers));\n          var plan = planKey(pairs, newUrl);\n          var finalReq = rebuilt;\n          if (plan.inject || plan.strip) {\n            var h = new Headers();\n            applyKeyToPairs(pairs, plan, preferredHeaderName())\n              .forEach(function (p) { h.append(p[0], p[1]); });\n            finalReq = new Request(rebuilt, { headers: h });\n          }\n          stats.intercepted++;\n          stats.lastUrl = newUrl;\n          if (plan.inject) stats.keyInjected++;\n          if (config.onIntercept) { try { config.onIntercept(url, newUrl); } catch (e) {} }\n          log('fetch (Request)', url, '->', newUrl);\n          // init 里剩下的字段（比如 signal）继续生效\n          var rest = Object.assign({}, init);\n          delete rest.headers;\n          return originals.fetch.call(this, finalReq, rest);\n        }\n\n        var opts = Object.assign({}, init);\n        var r = buildFetchHeaders(opts.headers, newUrl);\n        if (r.injected || r.headers !== opts.headers) opts.headers = r.headers;\n        if (r.injected) stats.keyInjected++;\n        stats.intercepted++;\n        stats.lastUrl = newUrl;\n        if (config.onIntercept) { try { config.onIntercept(url, newUrl); } catch (e) {} }\n        log('fetch', url, '->', newUrl);\n        return originals.fetch.call(this, newUrl, opts);\n      } catch (e) {\n        stats.errors++;\n        log('fetch 拦截出错, 原样放行:', e);\n        return originals.fetch.apply(this, arguments);\n      }\n    };\n    return true;\n  }\n\n  // ---- XMLHttpRequest ----------------------------------------------------\n\n  function installXHR(target) {\n    target = target || (typeof globalThis !== 'undefined' ? globalThis : null);\n    if (!target || typeof target.XMLHttpRequest !== 'function') return false;\n    var XHR = target.XMLHttpRequest;\n    if (originals.xhrOpen) return true;\n\n    originals.xhrOpen = XHR.prototype.open;\n    originals.xhrSetHeader = XHR.prototype.setRequestHeader;\n    originals.xhrSend = XHR.prototype.send;\n\n    XHR.prototype.open = function (method, url) {\n      this.__bskOriginalUrl = url;\n      this.__bskRewritten = rewriteUrl(String(url));\n      if (this.__bskRewritten !== url) {\n        stats.intercepted++;\n        stats.lastUrl = this.__bskRewritten;\n        if (config.onIntercept) { try { config.onIntercept(url, this.__bskRewritten); } catch (e) {} }\n        log('xhr', url, '->', this.__bskRewritten);\n      }\n      var args = Array.prototype.slice.call(arguments);\n      args[1] = this.__bskRewritten;\n      return originals.xhrOpen.apply(this, args);\n    };\n\n    XHR.prototype.setRequestHeader = function (name, value) {\n      // 先记下来再决定 —— 因为要等 send 时才知道用户到底带了哪些 key。\n      if (!this.__bskHeaders) this.__bskHeaders = [];\n      this.__bskHeaders.push([name, value]);\n      if (!needsHandling(this.__bskOriginalUrl || '')) {\n        return originals.xhrSetHeader.call(this, name, value);\n      }\n      // 目标是反代: 先什么都不发, 等 send 时统一按策略写。\n      var plan = planKey(this.__bskHeaders, this.__bskRewritten || '');\n      if (plan.strip && (isKeyHeader(name) || isAuthHeader(name))) return undefined;\n      return originals.xhrSetHeader.call(this, name, value);\n    };\n\n    XHR.prototype.send = function () {\n      if (needsHandling(this.__bskOriginalUrl || '')) {\n        var pairs = this.__bskHeaders || [];\n        var plan = planKey(pairs, this.__bskRewritten || '');\n        if (plan.strip) {\n          // setRequestHeader 已经丢掉了旧的 key 头；这里补上我们的。\n          if (plan.inject) {\n            try {\n              originals.xhrSetHeader.call(this, preferredHeaderName(), config.apiKey);\n              stats.keyInjected++;\n            } catch (e) { stats.errors++; }\n          }\n        } else if (plan.inject) {\n          try {\n            originals.xhrSetHeader.call(this, preferredHeaderName(), config.apiKey);\n            stats.keyInjected++;\n          } catch (e) { stats.errors++; }\n        }\n      }\n      return originals.xhrSend.apply(this, arguments);\n    };\n    return true;\n  }\n\n  // ---- 对外接口 ----------------------------------------------------------\n\n  /**\n   * 装上拦截器。\n   *\n   * options 可选；target 是\"要打补丁的那个全局对象\"。\n   *\n   * ★ 第二个参数是给**油猴脚本**用的: 带 @grant 的脚本跑在沙箱里，\n   *   直接打 this 的 fetch 是改不到页面本身的；必须把 unsafeWindow\n   *   传进来，补丁才落在页面真正用的那个 fetch 上。\n   *   普通网页/Node 不用传。\n   */\n  function install(options, target) {\n    if (options) Object.assign(config, options);\n    if (!target) target = (typeof globalThis !== 'undefined') ? globalThis : null;\n    var a = installFetch(target);\n    var b = installXHR(target);\n    installed = a || b;\n    if (!installed) log('没找到 fetch / XMLHttpRequest, 拦截器没装上');\n    return installed;\n  }\n\n  function uninstall() {\n    var target = (typeof globalThis !== 'undefined') ? globalThis : null;\n    if (originals.fetch && target) { target.fetch = originals.fetch; originals.fetch = null; }\n    if (originals.xhrOpen && target && target.XMLHttpRequest) {\n      target.XMLHttpRequest.prototype.open = originals.xhrOpen;\n      target.XMLHttpRequest.prototype.setRequestHeader = originals.xhrSetHeader;\n      target.XMLHttpRequest.prototype.send = originals.xhrSend;\n      originals.xhrOpen = originals.xhrSetHeader = originals.xhrSend = null;\n    }\n    installed = false;\n  }\n\n  function setConfig(patch) { Object.assign(config, patch || {}); }\n  function getConfig() { return Object.assign({}, config); }\n  function getStats() { return Object.assign({}, stats); }\n  function resetStats() { stats.intercepted = 0; stats.keyInjected = 0; stats.errors = 0; }\n  function isInstalled() { return installed; }\n  function maskKey(k) {\n    k = String(k || '');\n    return k.length <= 12 ? k : k.slice(0, 8) + '…' + k.slice(-4);\n  }\n\n  return {\n    install: install,\n    uninstall: uninstall,\n    setConfig: setConfig,\n    getConfig: getConfig,\n    getStats: getStats,\n    resetStats: resetStats,\n    isInstalled: isInstalled,\n    maskKey: maskKey,\n    // 纯函数也导出去，方便测试和二次封装\n    rewriteUrl: rewriteUrl,\n    isTarget: isTarget,\n    isProxyUrl: isProxyUrl,\n    needsHandling: needsHandling,\n    headersToPairs: headersToPairs,\n    applyKeyToPairs: applyKeyToPairs,\n    planKey: planKey,\n    buildFetchHeaders: buildFetchHeaders,\n    DEFAULTS: DEFAULTS,\n  };\n});\n";
    var boot = '\n;try{BSKHypixel.install(' + JSON.stringify({
      proxyBase: cfg.proxyBase,
      apiKey: cfg.enabled ? cfg.apiKey : '',
      forceKey: !!cfg.forceKey,
      targetHosts: ['api.hypixel.net'],
    }) + ', window);}catch(e){console.warn("[BSK反代] 注入失败",e);}';
    injectIntoPage(code + boot);
    injected = cfg;
  }

  // ---- 面板 UI -----------------------------------------------------------

  var shadow = null;
  var els = {};

  function buildUI() {
    if (shadow) return shadow;

    var host = document.createElement('div');
    host.id = 'bsk-hypixel-proxy-host';
    // 宿主元素本身不参与布局，样式全在 shadow 里，避免被网站 CSS 影响
    host.style.cssText = 'all:initial;position:fixed;z-index:2147483647;right:16px;bottom:16px;';
    shadow = host.attachShadow({ mode: 'open' });

    shadow.innerHTML = [
      '<style>',
      '  *{box-sizing:border-box;font-family:system-ui,-apple-system,"Microsoft YaHei",sans-serif}',
      '  .wrap{position:relative}',
      '  .fab{width:48px;height:48px;border-radius:50%;border:none;cursor:pointer;',
      '       background:linear-gradient(135deg,#3b82f6,#1d4ed8);color:#fff;font-size:13px;',
      '       font-weight:700;box-shadow:0 4px 14px rgba(29,78,216,.45);line-height:1.15}',
      '  .fab.off{background:linear-gradient(135deg,#9ca3af,#6b7280);box-shadow:none}',
      '  .panel{position:absolute;right:0;bottom:60px;width:300px;background:#fff;color:#111827;',
      '         border-radius:12px;box-shadow:0 10px 40px rgba(0,0,0,.22);padding:14px;display:none;',
      '         font-size:13px;line-height:1.6}',
      '  .panel.show{display:block}',
      '  h3{margin:0 0 10px;font-size:14px;display:flex;align-items:center;gap:6px}',
      '  .dot{width:8px;height:8px;border-radius:50%;background:#22c55e}',
      '  .dot.off{background:#9ca3af}',
      '  label{display:block;margin:8px 0 4px;color:#374151;font-size:12px}',
      '  input[type=text],input[type=password]{width:100%;padding:6px 8px;border:1px solid #d1d5db;',
      '         border-radius:7px;font-size:12px;font-family:ui-monospace,Consolas,monospace}',
      '  .row{display:flex;align-items:center;gap:6px;margin-top:8px}',
      '  .muted{color:#6b7280;font-size:11px;word-break:break-all}',
      '  .btns{display:flex;gap:8px;margin-top:12px}',
      '  button.act{flex:1;padding:7px;border-radius:7px;border:1px solid #d1d5db;background:#f9fafb;',
      '             cursor:pointer;font-size:12px}',
      '  button.primary{background:#1d4ed8;color:#fff;border-color:#1d4ed8}',
      '  .tip{margin-top:10px;padding:8px;background:#f3f4f6;border-radius:7px;color:#4b5563;font-size:11px;line-height:1.5}',
      '  .stat{margin-top:8px;font-size:11px;color:#6b7280}',
      '</style>',
      '<div class="wrap">',
      '  <div class="panel" id="panel">',
      '    <h3><span class="dot" id="dot"></span><span id="title">BSK 反代拦截器</span></h3>',
      '    <div class="muted" id="proxyLine"></div>',
      '    <label>API Key（你的 bsk_ 开头的那串）</label>',
      '    <input type="password" id="keyInput" placeholder="bsk_xxxxxxxx" spellcheck="false">',
      '    <div class="row"><input type="checkbox" id="forceKey"><label style="margin:0" for="forceKey">强制使用这个 Key（覆盖原有的）</label></div>',
      '    <div class="row"><input type="checkbox" id="enabled"><label style="margin:0" for="enabled">启用拦截</label></div>',
      '    <div class="btns">',
      '      <button class="act primary" id="save">保存并生效</button>',
      '      <button class="act" id="close">关闭</button>',
      '    </div>',
      '    <div class="tip">',
      '      没 Key？在 QQ 群里发 <b>/apikey 你的QQ号</b> 申请，或看 <b>/apikey help</b>。',
      '    </div>',
      '  </div>',
      '  <button class="fab" id="fab" title="BSK 反代拦截器">BSK</button>',
      '</div>',
    ].join('\n');

    (document.body || document.documentElement).appendChild(host);

    els.panel = shadow.getElementById('panel');
    els.fab = shadow.getElementById('fab');
    els.dot = shadow.getElementById('dot');
    els.title = shadow.getElementById('title');
    els.proxyLine = shadow.getElementById('proxyLine');
    els.keyInput = shadow.getElementById('keyInput');
    els.forceKey = shadow.getElementById('forceKey');
    els.enabled = shadow.getElementById('enabled');
    els.save = shadow.getElementById('save');
    els.close = shadow.getElementById('close');

    els.fab.addEventListener('click', function () {
      els.panel.classList.toggle('show');
    });
    els.close.addEventListener('click', function () {
      els.panel.classList.remove('show');
    });
    els.save.addEventListener('click', onSave);

    refresh();
    return shadow;
  }

  function refresh() {
    var cfg = loadCfg();
    if (!els.panel) return;
    els.keyInput.value = cfg.apiKey || '';
    els.forceKey.checked = !!cfg.forceKey;
    els.enabled.checked = !!cfg.enabled;
    els.proxyLine.textContent = 'api.hypixel.net → ' + cfg.proxyBase;
    var on = cfg.enabled && !!cfg.apiKey;
    els.dot.className = 'dot' + (on ? '' : ' off');
    els.fab.className = 'fab' + (on ? '' : ' off');
    els.title.textContent = on ? ('已拦截 ' + (window.__bskStats ? window.__bskStats() : '?') + ' 次') : '未启用';
  }

  function onSave() {
    var cfg = loadCfg();
    cfg.apiKey = els.keyInput.value.trim();
    cfg.forceKey = !!els.forceKey.checked;
    cfg.enabled = !!els.enabled.checked;
    saveCfg(cfg);
    applyToPage(cfg);
    refresh();
    els.title.textContent = '已保存 ✓';
    setTimeout(refresh, 1200);
  }

  // ---- 启动 --------------------------------------------------------------

  function boot() {
    var cfg = loadCfg();
    // 先无条件注入一次（哪怕没配 Key）—— 地址改写本身就很有用，
    // 而且用户等下填了 Key 不用刷新页面。
    applyToPage(cfg);
    buildUI();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }

  // 油猴菜单里也给一个入口（面板被网站遮住时能救命）
  try {
    if (typeof GM_registerMenuCommand === 'function') {
      GM_registerMenuCommand('打开 BSK 反代设置', function () {
        buildUI();
        els.panel.classList.add('show');
      });
    }
  } catch (e) {}
})();
