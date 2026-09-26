/**
 * 本地代理的端到端测试客户端。
 *
 * 模拟"hosts 把 api.hypixel.net 指到 127.0.0.1 之后, Minecraft 连过来"的情形:
 *   · 连 127.0.0.1:<port>
 *   · TLS SNI 用 api.hypixel.net
 *   · Host 头也用 api.hypixel.net
 *   · 证书不校验（测试用的临时 CA 没装进系统信任区）
 *
 * 验证: 响应能正常回来、path 原样、状态码原样、Key 被注入（看代理日志）。
 *
 *   node test_client.mjs <port> [path]
 *
 * ★ 默认端点用 /v2/resources/games —— 它是**合法**端点而且不需要 uuid。
 *   别用 /v2/games: 那个端点根本不存在, Hypixel 会回
 *   {"success":false,"cause":"Unknown endpoint"}, 看起来像代理坏了,
 *   其实只是路径写错了（实测误导过一次）。
 */
import https from 'node:https';

const port = parseInt(process.argv[2] || '8443', 10);
const path = process.argv[3] || '/v2/resources/games';

const req = https.request({
  host: '127.0.0.1',
  port,
  path,
  method: 'GET',
  servername: 'api.hypixel.net',       // SNI
  headers: { Host: 'api.hypixel.net' }, // 客户端以为自己在跟 Hypixel 说话
  rejectUnauthorized: false,           // 临时测试 CA，没装信任区
  timeout: 20000,
}, (res) => {
  let body = '';
  res.setEncoding('utf8');
  res.on('data', (c) => { body += c; });
  res.on('end', () => {
    console.log(JSON.stringify({
      ok: true,
      status: res.statusCode,
      contentType: res.headers['content-type'] || '',
      bodyLength: body.length,
      bodyHead: body.slice(0, 220),
    }, null, 2));
  });
});

req.on('timeout', () => { console.error(JSON.stringify({ ok: false, error: 'timeout' })); process.exit(1); });
req.on('error', (e) => {
  console.error(JSON.stringify({ ok: false, error: e.message, code: e.code || '' }));
  process.exit(1);
});
req.end();
