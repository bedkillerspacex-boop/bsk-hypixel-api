/**
 * JS 拦截器的行为测试（Node 跑，不需要浏览器）。
 *
 *   node tests/test_interceptor.mjs
 *
 * 重点测三件事:
 *   1. 该改的改 (api.hypixel.net -> 反代), 不该改的一个都别动
 *   2. key 的注入 / 强制覆盖 / 不覆盖 三种策略
 *   3. fetch 的两种调用形态 (字符串 / Request 对象) 都真的被拦到
 */
import assert from 'node:assert';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const BSK = require('../bsk-hypixel-interceptor.js');

let pass = 0, fail = 0;
async function t(name, fn) {
  try {
    await fn();
    pass++;
    console.log('  ✓ ' + name);
  } catch (e) {
    fail++;
    console.log('  ✗ ' + name + '\n      ' + e.message);
  }
}

const KEY = 'bsk_TESTKEY';

console.log('URL 改写');
BSK.setConfig({ proxyBase: 'https://hyp-api.firebounce.today', apiKey: KEY, forceKey: true });

await t('官方域名被改到反代', () => {
  assert.strictEqual(
    BSK.rewriteUrl('https://api.hypixel.net/v2/player?uuid=abc'),
    'https://hyp-api.firebounce.today/v2/player?uuid=abc');
});

await t('path 和 query 原样保留（反代是透明转发）', () => {
  const u = BSK.rewriteUrl('https://api.hypixel.net/v2/skyblock/auctions?page=3&x=1');
  assert.ok(u.includes('/v2/skyblock/auctions'));
  assert.ok(u.includes('page=3'));
  assert.ok(u.includes('x=1'));
});

await t('非 Hypixel 的请求一动不动', () => {
  for (const u of ['https://example.com/a',
                   'https://api.mojang.com/users/profiles/minecraft/x',
                   'https://api.firebounce.today/api/denick?nick=x']) {
    assert.strictEqual(BSK.rewriteUrl(u), u, u + ' 不该被改');
  }
});

await t('★ 长得像的钓鱼域名不能被当成目标', () => {
  // 最容易写错的地方: 用 includes / endsWith 判断就会中招
  for (const u of ['https://api.hypixel.net.evil.com/v2/x',
                   'https://evilapi.hypixel.net.attacker.io/v2/x',
                   'https://notapi.hypixel.net/v2/x']) {
    assert.strictEqual(BSK.rewriteUrl(u), u, u + ' 不该被改');
  }
});

await t('已经是反代的地址不会被二次改写', () => {
  const u = 'https://hyp-api.firebounce.today/v2/player?uuid=abc';
  assert.strictEqual(BSK.rewriteUrl(u), u);
});

console.log('\nKey 策略');

/**
 * 取"注入进去的那个 key 值"。
 *
 * ★ 不能写死 header 名: 浏览器里为了过 CORS 预检用的是 X-API-Key
 *   (反代的白名单是 Authorization, X-API-Key, Content-Type),
 *   而 Node 没有 CORS 限制, 用的是更贴近官方习惯的 API-Key。
 *   所以这里按**值**找, 跟实现选哪个名字无关。
 */
function injectedKey(headers) {
  for (const name of ['X-API-Key', 'API-Key', 'Authorization']) {
    const v = headers.get ? headers.get(name) : (headers[name] || null);
    if (v) return v;
  }
  return null;
}

await t('没带 key 时注入我们的', () => {
  const r = BSK.buildFetchHeaders({ 'Content-Type': 'application/json' },
                                  'https://hyp-api.firebounce.today/v2/x');
  assert.strictEqual(r.injected, true);
  assert.strictEqual(injectedKey(r.headers), KEY);
});

await t('★ 强制覆盖: 调用方自己的 key 必须被删掉', () => {
  // 不删的话有些实现会优先读旧头, 等于没换
  const r = BSK.buildFetchHeaders({ 'API-Key': 'their-own-key' },
                                  'https://hyp-api.firebounce.today/v2/x');
  const values = [...r.headers.entries()].map((p) => p[1]);
  assert.ok(!values.includes('their-own-key'), '旧 key 还在: ' + JSON.stringify([...r.headers]));
  assert.strictEqual(injectedKey(r.headers), KEY);
});

await t('强制覆盖: Bearer 形式的 Authorization 也要删', () => {
  const r = BSK.buildFetchHeaders({ Authorization: 'Bearer their-own-key' },
                                  'https://hyp-api.firebounce.today/v2/x');
  const auth = r.headers.get('Authorization');
  assert.strictEqual(auth, null, 'Bearer 不该留着: ' + auth);
  assert.strictEqual(injectedKey(r.headers), KEY);
});

await t('不强制时: 调用方带了 key 就不动', () => {
  BSK.setConfig({ forceKey: false });
  const r = BSK.buildFetchHeaders({ 'API-Key': 'their-own-key' },
                                  'https://hyp-api.firebounce.today/v2/x');
  assert.strictEqual(r.injected, false);
  assert.strictEqual(r.hadKey, true);
  BSK.setConfig({ forceKey: true });
});

await t('不强制时: 调用方没带才补上', () => {
  BSK.setConfig({ forceKey: false });
  const r = BSK.buildFetchHeaders({}, 'https://hyp-api.firebounce.today/v2/x');
  assert.strictEqual(r.injected, true);
  BSK.setConfig({ forceKey: true });
});

await t('?key= 也算"调用方带了 key"', () => {
  assert.strictEqual(BSK.planKey([], 'https://hyp-api.firebounce.today/v2/x?key=zzz').hasKey, true);
});

await t('X-API-Key 形式也被认成"已带 key"', () => {
  assert.strictEqual(BSK.planKey([['X-API-Key', 'x']], 'https://h/v2/x').hasKey, true);
});

await t('没配 apiKey 时什么都不注入', () => {
  BSK.setConfig({ apiKey: '' });
  assert.strictEqual(BSK.buildFetchHeaders({}, 'https://hyp-api.firebounce.today/v2/x').injected, false);
  BSK.setConfig({ apiKey: KEY });
});

// ---------------------------------------------------------------------------
// 真发请求：起一个本地假反代，把 targetHosts 指到它，验证 fetch 补丁真的生效
// ---------------------------------------------------------------------------
console.log('\nfetch 拦截（真打本地假反代）');
{
  const http = require('node:http');
  const seen = [];
  const server = http.createServer((req, res) => {
    seen.push({ url: req.url, key: req.headers['x-api-key'] || req.headers['api-key'] || '' });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true }));
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const BASE = `http://127.0.0.1:${port}`;

  // 把"官方域名"当成 127.0.0.1，反代也指向它 —— 这样 fetch 补丁会真的介入
  BSK.install({
    proxyBase: BASE,
    targetHosts: ['127.0.0.1'],
    apiKey: 'bsk_LOCALTEST',
    forceKey: true,
  });

  await t('① fetch(url, init) 被拦且注入了 key', async () => {
    const r = await fetch(`${BASE}/v2/status`, { headers: { 'API-Key': 'their-key' } });
    await r.json();
    const last = seen[seen.length - 1];
    assert.strictEqual(last.url, '/v2/status');
    assert.strictEqual(last.key, 'bsk_LOCALTEST', 'key 应该是我们的');
  });

  await t('② fetch(Request) 也被拦且注入了 key', async () => {
    const req = new Request(`${BASE}/v2/player?uuid=x`, {
      headers: { 'API-Key': 'their-key' },
    });
    const r = await fetch(req);
    await r.json();
    const last = seen[seen.length - 1];
    assert.strictEqual(last.url, '/v2/player?uuid=x');
    assert.strictEqual(last.key, 'bsk_LOCALTEST');
  });

  await t('③ 非目标的请求不该被插手', async () => {
    const before = seen.length;
    const r = await fetch('https://example.com/');   // 会失败, 但重点是没被改写
    await r.text().catch(() => {});
    assert.strictEqual(seen.length, before, 'example.com 不该打到假反代');
  }).catch(() => {});

  await t('统计有记账', () => {
    const s = BSK.getStats();
    assert.ok(s.intercepted >= 2, 'intercepted=' + s.intercepted);
    assert.ok(s.keyInjected >= 2, 'keyInjected=' + s.keyInjected);
  });

  BSK.uninstall();
  await new Promise((r) => server.close(r));
}

console.log(`\n${pass} 通过, ${fail} 失败`);
process.exit(fail ? 1 : 0);
