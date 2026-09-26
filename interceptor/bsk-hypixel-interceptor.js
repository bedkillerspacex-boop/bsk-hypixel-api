/*!
 * BSK Hypixel API 反代拦截器 (JavaScript)
 * ---------------------------------------------------------------
 * 把代码里所有发给 api.hypixel.net 的请求**自动改道**到
 * https://hyp-api.firebounce.today，并把 API Key 换成你自己的 bsk_ Key。
 *
 * 为什么需要它:
 *   很多现成的 Hypixel 工具/网页/脚本里把 base URL 写死在代码深处，
 *   一个个改太麻烦。这个拦截器在**网络层**动手 —— 应用代码一行都不用改。
 *
 * 支持的拦截点:
 *   · fetch()
 *   · XMLHttpRequest
 *
 * 用法（浏览器）:
 *   <script src="bsk-hypixel-interceptor.js"></script>
 *   <script>
 *     BSKHypixel.install({ apiKey: 'bsk_你的Key' });
 *   </script>
 *
 * 用法（Node / Electron）:
 *   const BSKHypixel = require('./bsk-hypixel-interceptor.js');
 *   BSKHypixel.install({ apiKey: process.env.BSK_KEY });
 *
 * ⚠️ Node 的 fetch 是全局的，能拦；但 Node 里如果用了 axios（走 http/https 模块）
 *    拦不到 —— 那种情况请用同目录的 Python 版思路，或者直接把 baseURL 改掉。
 */

(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.BSKHypixel = factory();
  }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // ---- 默认配置 ----------------------------------------------------------

  var DEFAULTS = {
    // 反代地址。所有命中目标的请求都会改到这里。
    proxyBase: 'https://hyp-api.firebounce.today',
    // 哪些域名算"原来的 Hypixel API"。
    targetHosts: ['api.hypixel.net'],
    // 你的 bsk_ Key。留空 = 不改 key（需要调用方自己带）。
    apiKey: '',
    // true = **强制**用上面的 Key（把调用方原本带的 key 丢掉）；
    // false = 调用方自己带了 key 就不动。
    forceKey: true,
    // 调试日志。
    debug: false,
    // 拦截到之后回调 (url, 改写后的 url)。想自己记账/上报可以用。
    onIntercept: null,
  };

  var config = Object.assign({}, DEFAULTS);
  var installed = false;
  var originals = { fetch: null, xhrOpen: null, xhrSetHeader: null, xhrSend: null };
  var stats = { intercepted: 0, keyInjected: 0, lastUrl: '', errors: 0 };

  // ---- 纯函数（可单独测试，不依赖 DOM）-----------------------------------

  function log() {
    if (!config.debug) return;
    try {
      var args = Array.prototype.slice.call(arguments);
      args.unshift('[BSK反代]');
      console.log.apply(console, args);
    } catch (e) { /* 忽略 */ }
  }

  /**
   * 这个 URL 是不是"原来的 Hypixel API"？
   * 用 host 精确比较 —— 不能用 indexOf/endswith，否则
   * `api.hypixel.net.evil.com` 也会被当成目标。
   */
  function isTarget(url) {
    var host;
    try {
      host = new URL(url, 'https://placeholder.invalid').hostname.toLowerCase();
    } catch (e) {
      return false;
    }
    return config.targetHosts.some(function (h) {
      return host === String(h).toLowerCase();
    });
  }

  /**
   * 把 URL 从 api.hypixel.net 改写到反代。
   *
   * 只改 **origin**，path / query **原样保留** —— 反代是透明转发，
   * 端点格式跟官方一模一样，所以不需要任何路径映射。
   * 不是目标的 URL 一律原样返回。
   */
  function rewriteUrl(url) {
    if (!url || typeof url !== 'string') return url;
    if (!isTarget(url)) return url;
    try {
      var u = new URL(url, 'https://placeholder.invalid');
      var base = new URL(config.proxyBase);
      u.protocol = base.protocol;
      u.host = base.host;
      return u.toString();
    } catch (e) {
      return url;
    }
  }

  var KEY_HEADERS = ['api-key', 'x-api-key', 'apikey'];

  /** 这个 URL 本来就是发给反代的吗？ */
  function isProxyUrl(url) {
    var host;
    try {
      host = new URL(url, 'https://placeholder.invalid').hostname.toLowerCase();
    } catch (e) {
      return false;
    }
    var base;
    try {
      base = new URL(config.proxyBase).hostname.toLowerCase();
    } catch (e) {
      return false;
    }
    return !!host && host === base;
  }

  /**
   * 这个请求需不需要我们插手（改写 + 补 key）？
   *
   * ★ 两种都要管:
   *   1. 发给**官方** api.hypixel.net 的 -> 改写到反代 + 补 key
   *   2. 本来就发给**反代**的             -> 只补 key（地址不用改）
   *
   * 第 2 种很容易漏: 如果只在"URL 变了"时才补 key, 那
   * "我直接把 baseURL 写成反代, 但想让拦截器自动填 key" 这个
   * 完全合理的用法会**静默失效**（key 不补, 请求 401）。
   */
  function needsHandling(url) {
    return isTarget(url) || isProxyUrl(url);
  }

  function isAuthHeader(name) {
    return String(name || '').toLowerCase() === 'authorization';
  }

  function isKeyHeader(name) {
    return KEY_HEADERS.indexOf(String(name || '').toLowerCase()) !== -1;
  }

  /**
   * 把各种形态的 header 容器统一成 [[名字, 值], ...]。
   * 支持: 普通对象 / Headers / 二维数组。认不出来就返回空数组。
   */
  function headersToPairs(headers) {
    var out = [];
    if (!headers) return out;
    if (typeof Headers !== 'undefined' && headers instanceof Headers) {
      headers.forEach(function (v, k) { out.push([k, v]); });
      return out;
    }
    if (Array.isArray(headers)) {
      headers.forEach(function (p) {
        if (Array.isArray(p) && p.length >= 2) out.push([String(p[0]), String(p[1])]);
      });
      return out;
    }
    if (typeof headers === 'object') {
      Object.keys(headers).forEach(function (k) { out.push([k, headers[k]]); });
    }
    return out;
  }

  /** 调用方是不是**已经**在某个 header 里带了 key（Bearer 也算）。 */
  function hasKeyHeader(headers) {
    return headersToPairs(headers).some(function (p) {
      if (isKeyHeader(p[0])) return String(p[1] || '').trim() !== '';
      if (isAuthHeader(p[0])) return /^bearer\s+\S+/i.test(String(p[1] || ''));
      return false;
    });
  }

  /** URL 的 query 里有没有 ?key=。 */
  function hasKeyInQuery(url) {
    try {
      var u = new URL(url, 'https://placeholder.invalid');
      var k = u.searchParams.get('key');
      return !!(k && k.trim());
    } catch (e) {
      return false;
    }
  }

  /**
   * 决定要不要注入 key、怎么注入。
   *
   * forceKey=true  -> 无条件用我们的 key，并把调用方原来的 key 头**删掉**
   *                   （不删的话有些服务端会优先读旧的那个，等于没换）
   * forceKey=false -> 调用方自己带了就不动
   */
  function planKey(headers, url) {
    var hasKey = hasKeyHeader(headers) || hasKeyInQuery(url);
    if (!config.apiKey) return { inject: false, strip: false, hasKey: hasKey };
    if (hasKey && !config.forceKey) return { inject: false, strip: false, hasKey: hasKey };
    return { inject: true, strip: config.forceKey, hasKey: hasKey };
  }

  /**
   * 对 header 列表执行注入/剥离，返回新的 [[名字, 值], ...]。
   *
   * ★ 输出统一用 `API-Key`（反代三种写法都收），并在浏览器里**换成 X-API-Key**
   *   —— 见 buildFetchHeaders 的说明：跨域请求只有 CORS 白名单里的头才发得出去。
   *
   * strip=true 时会删掉: api-key / x-api-key / apikey 以及 Bearer 的 Authorization。
   */
  function applyKeyToPairs(pairs, plan, headerName) {
    var name = headerName || 'API-Key';
    var out = [];
    pairs.forEach(function (p) {
      if (plan.strip && (isKeyHeader(p[0]) || isAuthHeader(p[0]))) return;
      out.push([p[0], p[1]]);
    });
    if (plan.inject) out.push([name, config.apiKey]);
    return out;
  }

  // ---- fetch -------------------------------------------------------------

  /**
   * 浏览器里跨域请求想带自定义头，那个头必须在服务端
   * Access-Control-Allow-Headers 白名单里，否则预检就过不去。
   * 我们的反代白名单是 `Authorization, X-API-Key, Content-Type` ——
   * **没有 `API-Key`**，所以浏览器场景要用 X-API-Key。
   * Node 没有 CORS，用 API-Key 更贴近官方习惯，无差别。
   */
  function preferredHeaderName() {
    var isBrowser = typeof window !== 'undefined' && typeof window.document !== 'undefined';
    return isBrowser ? 'X-API-Key' : 'API-Key';
  }

  function buildFetchHeaders(original, url) {
    var pairs = headersToPairs(original);
    var plan = planKey(pairs, url);
    if (!plan.inject && !plan.strip) return { headers: original, injected: false, hadKey: plan.hasKey };
    var merged = applyKeyToPairs(pairs, plan, preferredHeaderName());
    // fetch 的 header 参数用 Headers 实例最稳（普通对象无法表示同名多值）。
    var h;
    if (typeof Headers !== 'undefined') {
      h = new Headers();
      merged.forEach(function (p) { h.append(p[0], p[1]); });
    } else {
      h = {};
      merged.forEach(function (p) { h[p[0]] = p[1]; });
    }
    return { headers: h, injected: plan.inject, hadKey: plan.hasKey };
  }

  function installFetch(target) {
    target = target || (typeof globalThis !== 'undefined' ? globalThis : null);
    if (!target || typeof target.fetch !== 'function') return false;
    if (originals.fetch) return true;              // 已经装过
    originals.fetch = target.fetch;

    target.fetch = function (input, init) {
      try {
        var url, request = null;

        if (typeof Request !== 'undefined' && input instanceof Request) {
          request = input;
          url = input.url;
        } else if (input && typeof input === 'object' && typeof input.url === 'string') {
          // 鸭子类型: 别的库造的类 Request 对象
          request = input;
          url = input.url;
        } else {
          url = String(input);
        }

        if (!needsHandling(url)) return originals.fetch.apply(this, arguments);

        var newUrl = rewriteUrl(url);

        if (request && typeof Request !== 'undefined') {
          // ★ 用 Request 当 init 重建，再把 header 覆盖掉 —— 这是规范认可的写法，
          //   能保住 method / body / signal / credentials。
          //   自己手拼 init 很容易把 body 弄丢（尤其流式 body 还要 duplex）。
          var rebuilt = new Request(newUrl, request);
          var pairs = headersToPairs(rebuilt.headers)
            .concat(headersToPairs(init && init.headers));
          var plan = planKey(pairs, newUrl);
          var finalReq = rebuilt;
          if (plan.inject || plan.strip) {
            var h = new Headers();
            applyKeyToPairs(pairs, plan, preferredHeaderName())
              .forEach(function (p) { h.append(p[0], p[1]); });
            finalReq = new Request(rebuilt, { headers: h });
          }
          stats.intercepted++;
          stats.lastUrl = newUrl;
          if (plan.inject) stats.keyInjected++;
          if (config.onIntercept) { try { config.onIntercept(url, newUrl); } catch (e) {} }
          log('fetch (Request)', url, '->', newUrl);
          // init 里剩下的字段（比如 signal）继续生效
          var rest = Object.assign({}, init);
          delete rest.headers;
          return originals.fetch.call(this, finalReq, rest);
        }

        var opts = Object.assign({}, init);
        var r = buildFetchHeaders(opts.headers, newUrl);
        if (r.injected || r.headers !== opts.headers) opts.headers = r.headers;
        if (r.injected) stats.keyInjected++;
        stats.intercepted++;
        stats.lastUrl = newUrl;
        if (config.onIntercept) { try { config.onIntercept(url, newUrl); } catch (e) {} }
        log('fetch', url, '->', newUrl);
        return originals.fetch.call(this, newUrl, opts);
      } catch (e) {
        stats.errors++;
        log('fetch 拦截出错, 原样放行:', e);
        return originals.fetch.apply(this, arguments);
      }
    };
    return true;
  }

  // ---- XMLHttpRequest ----------------------------------------------------

  function installXHR(target) {
    target = target || (typeof globalThis !== 'undefined' ? globalThis : null);
    if (!target || typeof target.XMLHttpRequest !== 'function') return false;
    var XHR = target.XMLHttpRequest;
    if (originals.xhrOpen) return true;

    originals.xhrOpen = XHR.prototype.open;
    originals.xhrSetHeader = XHR.prototype.setRequestHeader;
    originals.xhrSend = XHR.prototype.send;

    XHR.prototype.open = function (method, url) {
      this.__bskOriginalUrl = url;
      this.__bskRewritten = rewriteUrl(String(url));
      if (this.__bskRewritten !== url) {
        stats.intercepted++;
        stats.lastUrl = this.__bskRewritten;
        if (config.onIntercept) { try { config.onIntercept(url, this.__bskRewritten); } catch (e) {} }
        log('xhr', url, '->', this.__bskRewritten);
      }
      var args = Array.prototype.slice.call(arguments);
      args[1] = this.__bskRewritten;
      return originals.xhrOpen.apply(this, args);
    };

    XHR.prototype.setRequestHeader = function (name, value) {
      // 先记下来再决定 —— 因为要等 send 时才知道用户到底带了哪些 key。
      if (!this.__bskHeaders) this.__bskHeaders = [];
      this.__bskHeaders.push([name, value]);
      if (!needsHandling(this.__bskOriginalUrl || '')) {
        return originals.xhrSetHeader.call(this, name, value);
      }
      // 目标是反代: 先什么都不发, 等 send 时统一按策略写。
      var plan = planKey(this.__bskHeaders, this.__bskRewritten || '');
      if (plan.strip && (isKeyHeader(name) || isAuthHeader(name))) return undefined;
      return originals.xhrSetHeader.call(this, name, value);
    };

    XHR.prototype.send = function () {
      if (needsHandling(this.__bskOriginalUrl || '')) {
        var pairs = this.__bskHeaders || [];
        var plan = planKey(pairs, this.__bskRewritten || '');
        if (plan.strip) {
          // setRequestHeader 已经丢掉了旧的 key 头；这里补上我们的。
          if (plan.inject) {
            try {
              originals.xhrSetHeader.call(this, preferredHeaderName(), config.apiKey);
              stats.keyInjected++;
            } catch (e) { stats.errors++; }
          }
        } else if (plan.inject) {
          try {
            originals.xhrSetHeader.call(this, preferredHeaderName(), config.apiKey);
            stats.keyInjected++;
          } catch (e) { stats.errors++; }
        }
      }
      return originals.xhrSend.apply(this, arguments);
    };
    return true;
  }

  // ---- 对外接口 ----------------------------------------------------------

  /**
   * 装上拦截器。
   *
   * options 可选；target 是"要打补丁的那个全局对象"。
   *
   * ★ 第二个参数是给**油猴脚本**用的: 带 @grant 的脚本跑在沙箱里，
   *   直接打 this 的 fetch 是改不到页面本身的；必须把 unsafeWindow
   *   传进来，补丁才落在页面真正用的那个 fetch 上。
   *   普通网页/Node 不用传。
   */
  function install(options, target) {
    if (options) Object.assign(config, options);
    if (!target) target = (typeof globalThis !== 'undefined') ? globalThis : null;
    var a = installFetch(target);
    var b = installXHR(target);
    installed = a || b;
    if (!installed) log('没找到 fetch / XMLHttpRequest, 拦截器没装上');
    return installed;
  }

  function uninstall() {
    var target = (typeof globalThis !== 'undefined') ? globalThis : null;
    if (originals.fetch && target) { target.fetch = originals.fetch; originals.fetch = null; }
    if (originals.xhrOpen && target && target.XMLHttpRequest) {
      target.XMLHttpRequest.prototype.open = originals.xhrOpen;
      target.XMLHttpRequest.prototype.setRequestHeader = originals.xhrSetHeader;
      target.XMLHttpRequest.prototype.send = originals.xhrSend;
      originals.xhrOpen = originals.xhrSetHeader = originals.xhrSend = null;
    }
    installed = false;
  }

  function setConfig(patch) { Object.assign(config, patch || {}); }
  function getConfig() { return Object.assign({}, config); }
  function getStats() { return Object.assign({}, stats); }
  function resetStats() { stats.intercepted = 0; stats.keyInjected = 0; stats.errors = 0; }
  function isInstalled() { return installed; }
  function maskKey(k) {
    k = String(k || '');
    return k.length <= 12 ? k : k.slice(0, 8) + '…' + k.slice(-4);
  }

  return {
    install: install,
    uninstall: uninstall,
    setConfig: setConfig,
    getConfig: getConfig,
    getStats: getStats,
    resetStats: resetStats,
    isInstalled: isInstalled,
    maskKey: maskKey,
    // 纯函数也导出去，方便测试和二次封装
    rewriteUrl: rewriteUrl,
    isTarget: isTarget,
    isProxyUrl: isProxyUrl,
    needsHandling: needsHandling,
    headersToPairs: headersToPairs,
    applyKeyToPairs: applyKeyToPairs,
    planKey: planKey,
    buildFetchHeaders: buildFetchHeaders,
    DEFAULTS: DEFAULTS,
  };
});
