/*!
 * BSK Hypixel 本地反代中间人（MITM）—— Node 零依赖实现
 * ===========================================================================
 *
 * 干什么:
 *   hosts 把 api.hypixel.net 指到 127.0.0.1 之后, Minecraft（或任何程序）
 *   连过来时**以为自己在连 Hypixel**, 实际上连的是我们。本进程:
 *
 *     ① 用它自己那张（本地 CA 签的）api.hypixel.net 证书，把 TLS 拆开
 *     ② 读出里面的 HTTP 请求
 *     ③ 原样转发到反代 https://hyp-api.firebounce.today，并塞上你的 bsk_ Key
 *     ④ 把响应原封不动还回去
 *
 *   path / query / body / 状态码 / 响应头 全都不动 —— 对调用方完全透明。
 *
 * 为什么必须是 MITM:
 *   api.hypixel.net 的证书是 Hypixel 的, 我们没有。想改请求内容就必须在
 *   本地把 TLS 终止掉、用自己签的证书顶上 —— 所以**必须**在系统里信任
 *   一次本地根 CA（跟 mitmproxy / Charles 一个原理）。
 *
 * 为什么不用 CONNECT 代理:
 *   我们是靠 hosts 把域名指过来的, 客户端是**直连** TCP, 不会发 CONNECT。
 *   所以只要一个普通 HTTPS 服务器 + 一张对得上的证书就够了,
 *   不用写完整的代理协议 —— 简单很多, 也少很多出错空间。
 *
 * 用法:  node proxy.js <config.json 路径>
 *        （正常不用手敲, 由 bsk-proxy.ps1 拉起来）
 */

'use strict';

const fs = require('fs');
const path = require('path');
const https = require('https');
const tls = require('tls');
const util = require('util');

// ---- 参数 ----------------------------------------------------------------

const cfgPath = process.argv[2];
if (!cfgPath) {
  console.error('用法: node proxy.js <config.json>');
  process.exit(2);
}

let cfg;
try {
  let raw = fs.readFileSync(cfgPath, 'utf8');
  // ★ 去掉 UTF-8 BOM —— Windows PowerShell 的 `Set-Content -Encoding UTF8`
  //   会写 BOM, 而 JSON.parse 遇到 BOM 直接抛 "Unexpected token"。
  //   脚本那边已经改成不写 BOM 了, 这里再兜一层（用户手工编辑过也会中招）。
  if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
  cfg = JSON.parse(raw);
} catch (e) {
  console.error('读不到配置文件: ' + cfgPath + ' — ' + e.message);
  process.exit(2);
}

const CFG = Object.assign({
  proxyBase: 'https://hyp-api.firebounce.today',
  apiKey: '',
  forceKey: true,
  listenHost: '127.0.0.1',
  listenPort: 443,
  pfX: '',            // 叶子证书（含私钥）的 pfx 路径
  pfxPass: 'bsk',
  serverName: 'api.hypixel.net',
  logFile: '',
  pidFile: '',
}, cfg);

const target = new URL(CFG.proxyBase);

// ---- PID 文件 --------------------------------------------------------------
//
// ★ 由**代理自己**写 PID, 而不是让启动它的 PowerShell 写。
//   原因: 启动时为了让控制台正确显示中文, 是经 `cmd /c chcp 65001 && node ...`
//   拉起来的 —— 那样 Start-Process 拿到的是 cmd 的 PID, 不是 node 的,
//   拿那个 PID 去杀会留下没人管的 node 进程占着 443。
//   自己写就没有这个猜谜环节。
function writePid() {
  if (!CFG.pidFile) return;
  try {
    fs.mkdirSync(path.dirname(CFG.pidFile), { recursive: true });
    fs.writeFileSync(CFG.pidFile, String(process.pid), 'ascii');
  } catch (e) { /* 写不了也不该让代理起不来 */ }
}

function clearPid() {
  if (!CFG.pidFile) return;
  try {
    // 只删自己写的那份 —— 别把后来者的 PID 文件删掉
    if (fs.readFileSync(CFG.pidFile, 'ascii').trim() === String(process.pid)) {
      fs.unlinkSync(CFG.pidFile);
    }
  } catch (e) { /* 已经没了 */ }
}

// ---- 日志 ----------------------------------------------------------------
//
// 同时往控制台和文件写。文件那份是为了"代理早就关了但用户想看刚才发生了什么"
// —— 控制台窗口一关就什么都没了。

let logStream = null;
if (CFG.logFile) {
  try {
    fs.mkdirSync(path.dirname(CFG.logFile), { recursive: true });
    logStream = fs.createWriteStream(CFG.logFile, { flags: 'a' });
  } catch (e) { /* 日志写不了不该让代理起不来 */ }
}

function log() {
  // ★ 必须走 util.format —— 手写 join(' ') 的话 `%s %d` 这些占位符**根本不会
  //   被替换**, 日志会原样打出 "GET %s -> %d"（本地实测踩到）。
  const msg = util.format.apply(util, arguments);
  const line = '[' + new Date().toISOString().replace('T', ' ').slice(0, 19) + '] ' + msg;
  console.log(line);
  if (logStream) { try { logStream.write(line + '\n'); } catch (e) {} }
}

function mask(k) {
  k = String(k || '');
  return k.length <= 12 ? (k || '(空)') : k.slice(0, 8) + '…' + k.slice(-4);
}

// ---- 证书 ----------------------------------------------------------------

if (!CFG.pfX || !fs.existsSync(CFG.pfX)) {
  console.error('找不到证书文件: ' + CFG.pfX);
  console.error('请先用 bsk-proxy.ps1 生成（拦截开关会自动做）。');
  process.exit(3);
}

let secureCtx;
try {
  secureCtx = tls.createSecureContext({
    pfx: fs.readFileSync(CFG.pfX),
    passphrase: CFG.pfxPass,
  });
} catch (e) {
  console.error('加载证书失败: ' + e.message);
  process.exit(3);
}

// ---- 转发 ----------------------------------------------------------------

const HOP_BY_HOP = new Set([
  'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
  'te', 'trailer', 'transfer-encoding', 'upgrade',
]);

const KEY_HEADERS = new Set(['api-key', 'x-api-key', 'apikey']);
const stats = { total: 0, injected: 0, failed: 0, startedAt: Date.now() };

function buildHeaders(srcHeaders) {
  const out = {};
  let hadKey = false;

  for (const [k, v] of Object.entries(srcHeaders)) {
    const lk = k.toLowerCase();
    if (HOP_BY_HOP.has(lk)) continue;
    // Host 必须换成反代的，否则反代 / 上游可能按 Host 路由
    if (lk === 'host') continue;
    if (KEY_HEADERS.has(lk)) { hadKey = true; if (CFG.forceKey) continue; }
    if (lk === 'authorization' && /^bearer\s+/i.test(String(v))) {
      hadKey = true;
      if (CFG.forceKey) continue;
    }
    out[k] = v;
  }

  out['host'] = target.hostname;

  if (CFG.apiKey && (!hadKey || CFG.forceKey)) {
    // 反代认 API-Key / X-API-Key / Bearer 三种，这里用最贴近官方习惯的
    out['API-Key'] = CFG.apiKey;
    stats.injected++;
  }
  return out;
}

/**
 * 强制覆盖时, 把 URL 里的 `?key=` / `?apikey=` 也删掉。
 *
 * ★ 光删 header 不够（实测踩到）。很多模组把 Key 直接拼在 URL 里:
 *     /v2/player?key=<它自己的key>&name=xxx
 * 而反代**认 URL 参数优先于请求头**。于是:
 *     · 模组带的是 Hypixel 官方 Key -> 反代直接 401
 *       ("Invalid API key. This key was not issued by ...")
 *     · 或者两边不一致时行为完全不可预测
 * forceKey=true 的语义就是"我的 Key 说了算", 所以 URL 里的也必须清掉。
 */
function stripKeyFromQuery(rawUrl) {
  if (!CFG.forceKey) return rawUrl;
  try {
    const u = new URL(rawUrl);
    let changed = false;
    for (const name of ['key', 'apikey']) {
      if (u.searchParams.has(name)) {
        u.searchParams.delete(name);
        changed = true;
      }
    }
    return changed ? u.toString() : rawUrl;
  } catch (e) {
    return rawUrl;
  }
}

function forward(req, res) {
  stats.total++;
  const started = Date.now();
  const headers = buildHeaders(req.headers);
  const reqPath = stripKeyFromQuery(req.url);

  const options = {
    protocol: target.protocol,
    hostname: target.hostname,
    port: target.port || 443,
    method: req.method,
    path: reqPath,                 // ★ path + query（已剥掉 key=）
    headers,
  };

  const upstream = https.request(options, (up) => {
    // 状态码和响应头原样回传（除了 hop-by-hop）
    const outHeaders = {};
    for (const [k, v] of Object.entries(up.headers)) {
      if (HOP_BY_HOP.has(k.toLowerCase())) continue;
      outHeaders[k] = v;
    }
    try {
      res.writeHead(up.statusCode || 502, outHeaders);
    } catch (e) {
      log('写响应头失败: ' + e.message);
    }
    up.pipe(res);
    up.on('end', () => {
      log('%s %s -> %d (%dms)%s',
          req.method, reqPath, up.statusCode, Date.now() - started,
          headers['API-Key'] ? ' [已注入 Key ' + mask(headers['API-Key']) + ']' : ' [无 Key]');
    });
  });

  upstream.on('error', (e) => {
    stats.failed++;
    log('★ 转发失败: ' + e.message);
    if (!res.headersSent) {
      try {
        res.writeHead(502, { 'Content-Type': 'application/json' });
      } catch (err) { /* 已经断了 */ }
    }
    try {
      res.end(JSON.stringify({
        success: false,
        cause: '本地反代转发失败: ' + e.message,
      }));
    } catch (err) { /* 忽略 */ }
  });

  req.on('error', (e) => {
    stats.failed++;
    log('客户端连接出错: ' + e.message);
    upstream.destroy();
  });

  req.pipe(upstream);
}

// ---- 服务 ----------------------------------------------------------------

const server = https.createServer({
  // 单域名拦截：hosts 只把那一个域名指过来，所以固定用那张证书就行。
  // 用 SNICallback 再兜一层，别的 SNI 直接拒掉（不该出现，出现就是有人在探测）。
  SNICallback: (servername, cb) => {
    const want = String(CFG.serverName || '').toLowerCase();
    const got = String(servername || '').toLowerCase();
    if (got && got !== want) {
      log('★ 收到非目标 SNI: ' + got + ' —— 拒绝');
      return cb(new Error('unexpected SNI: ' + got));
    }
    return cb(null, secureCtx);
  },
}, forward);

server.on('clientError', (err, socket) => {
  // 探测/半开连接很常见，别刷屏
  if (socket.writable) {
    try { socket.end('HTTP/1.1 400 Bad Request\r\n\r\n'); } catch (e) {}
  }
});

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.error('端口 ' + CFG.listenPort + ' 已被占用 —— 是不是已经有一个在跑？');
    console.error('先跑「恢复.cmd」，或者去任务管理器结束 node.exe。');
  } else if (e.code === 'EACCES') {
    console.error('没有权限监听 ' + CFG.listenHost + ':' + CFG.listenPort +
                  ' —— 请用管理员身份运行。');
  } else {
    console.error('启动失败: ' + e.message);
  }
  process.exit(1);
});

server.listen(CFG.listenPort, CFG.listenHost, () => {
  log('==================================================');
  log('BSK 本地反代已启动');
  log('  监听    : ' + CFG.listenHost + ':' + CFG.listenPort);
  log('  拦截域名: ' + CFG.serverName + '  (由 hosts 指过来)');
  log('  转发到  : ' + CFG.proxyBase);
  log('  Key     : ' + mask(CFG.apiKey) + (CFG.forceKey ? '  (强制覆盖)' : ''));
  log('  证书    : ' + CFG.pfX);
  log('==================================================');
  log('保持这个窗口开着。关掉窗口 = 拦截停止（记得跑「恢复.cmd」改回 hosts）。');

  // ★ 就绪信号必须放在 listen 回调里 —— 放在外面的话它会在**真正开始监听之前**
  //   就打印出来, 上层脚本据此判断"起来了"就会误判（端口还没绑上）。
  writePid();
  process.stdout.write('BSK_PROXY_READY ' + JSON.stringify({
    port: CFG.listenPort, host: CFG.listenHost, pid: process.pid,
  }) + '\n');
});

function shutdown(sig) {
  log('收到 ' + sig + '，正在退出…');
  clearPid();
  try { server.close(); } catch (e) {}
  if (logStream) { try { logStream.end(); } catch (e) {} }
  process.exit(0);
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
// 正常退出（含被 Stop-Process 强杀前的清理机会）也把 PID 文件收掉
process.on('exit', clearPid);
