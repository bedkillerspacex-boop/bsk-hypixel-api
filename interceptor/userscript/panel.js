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
    var code = '__BSK_CORE__';
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
