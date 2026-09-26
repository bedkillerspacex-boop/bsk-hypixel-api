/**
 * `stripKeyFromQuery` / `buildHeaders` 的单位测试。
 *
 * 为什么单独测这两个: 它们是"看起来对、其实是坏的"重灾区 ——
 * `stripKeyFromQuery` 曾经写成 `new URL(rawUrl)`, 而 Node 的 http server 给的
 * `req.url` 是**纯路径**(`/v2/player?key=x`), `new URL` 直接抛 `Invalid URL`,
 * 外面裹的 try/catch 就 return 原串 —— 于是"剥 key"**从来没生效过**,
 * 而且完全静默: 日志里照打印原始 URL, 一切看起来正常, 只有返回 401 才露馅。
 * 实测就是这样把 `?key=<模组自己的key>` 原样送到了反代, 每次都 401。
 *
 *   node tests/test_stripkey.mjs
 */
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const proxy = require(path.join(here, '..', 'proxy.js'));

const { stripKeyFromQuery, buildHeaders, CFG } = proxy;

// buildHeaders 要注入的是 CFG.apiKey —— require 时没有配置文件, 所以要手动给一把。
CFG.apiKey = 'bsk_testtesttesttesttesttesttest';
CFG.forceKey = true;

let pass = 0;
const failures = [];

function eq(actual, expected, label) {
  if (actual === expected) {
    pass++;
  } else {
    failures.push(`${label}\n      实际: ${JSON.stringify(actual)}\n      期望: ${JSON.stringify(expected)}`);
  }
}

function ok(cond, label) {
  if (cond) { pass++; } else { failures.push(label); }
}

// ---- stripKeyFromQuery: 核心场景 ------------------------------------------

// ★ 回归: 纯路径 + 带 key。这条以前是失效的（new URL 抛异常 -> 原样返回）。
eq(stripKeyFromQuery('/v2/player?key=GARBAGE&uuid=abc'), '/v2/player?uuid=abc',
   '?key= 应该被剥掉（纯路径形态）');

eq(stripKeyFromQuery('/v2/player?apikey=GARBAGE&name=Notch'), '/v2/player?name=Notch',
   '?apikey= 也应该被剥掉');

// key 在中间 / 在最后，位置不该影响结果
eq(stripKeyFromQuery('/v2/player?a=1&key=X&b=2'), '/v2/player?a=1&b=2',
   'key 在中间');
eq(stripKeyFromQuery('/v2/player?a=1&b=2&key=X'), '/v2/player?a=1&b=2',
   'key 在末尾');

// 删干净了就不该留一个孤零零的 '?'
eq(stripKeyFromQuery('/v2/status?key=X'), '/v2/status', '只剩 key 时不该留下 ?');

// 大小写不敏感（模组写法五花八门）
eq(stripKeyFromQuery('/v2/player?KEY=X&uuid=abc'), '/v2/player?uuid=abc', 'KEY= 大写');
eq(stripKeyFromQuery('/v2/player?ApiKey=X&uuid=abc'), '/v2/player?uuid=abc', 'ApiKey= 混合大小写');

// 名字里带 key 的**不能**被误删
eq(stripKeyFromQuery('/v2/player?keyword=x&uuid=abc'), '/v2/player?keyword=x&uuid=abc',
   'keyword= 不能误伤');
eq(stripKeyFromQuery('/v2/player?monkey=x&uuid=abc'), '/v2/player?monkey=x&uuid=abc',
   'monkey= 不能误伤');

// 没有 key 时**必须字节级原样**返回（含各种编码），不能经 URLSearchParams 重排/重编码
const untouched = [
  '/v2/resources/games',
  '/v2/player?uuid=abc',
  '/v2/player?name=a%20b&x=1',
  '/v2/player?name=a+b&x=1',
  '/v2/player?q=%E4%B8%AD%E6%96%87',
  '/v2/player?a=1&a=2&b=&c',
];
for (const u of untouched) {
  eq(stripKeyFromQuery(u), u, `无 key 时必须原样返回: ${u}`);
}

// 空格不能被变成 '+'
eq(stripKeyFromQuery('/v2/player?name=a%20b&key=X'), '/v2/player?name=a%20b',
   '剥 key 不能顺手把 %20 重编码成 +');

// 参数顺序必须保持
eq(stripKeyFromQuery('/v2/x?c=3&key=X&a=1&b=2'), '/v2/x?c=3&a=1&b=2', '保留原有顺序');

// ---- buildHeaders ---------------------------------------------------------

const H = buildHeaders({
  host: 'api.hypixel.net',
  'api-key': 'SOMEONE_ELSES_KEY',
  authorization: 'Bearer ANOTHER_KEY',
  'user-agent': 'Java/1.8.0_51',
  'content-length': '0',
});

ok(H['API-Key'] && H['API-Key'].startsWith('bsk_'),
   'forceKey=true 时必须注入我们自己的 API-Key');
ok(H['api-key'] === undefined && H['apikey'] === undefined,
   '客户端自带的 api-key 头必须被丢掉');
ok(H['authorization'] === undefined, '客户端自带的 Bearer 必须被丢掉');
eq(H['host'], 'hyp-api.firebounce.today', 'Host 必须换成反代的');
eq(H['user-agent'], 'Java/1.8.0_51', '其它头要原样保留');

// hop-by-hop 不能透传
ok(buildHeaders({ host: 'x', connection: 'keep-alive', te: 'trailers' }).connection === undefined,
   'connection 是 hop-by-hop, 不该透传');

// 大写形态的 host 也要换掉（HTTP 头大小写不敏感）
eq(buildHeaders({ Host: 'api.hypixel.net' })['Host'], undefined,
   'Host 的大小写变体也必须被处理, 不能漏给上游');
eq(buildHeaders({ Host: 'api.hypixel.net' }).host, 'hyp-api.firebounce.today',
   '大写 Host 也要换成反代域名');

// ---- 结果 ----------------------------------------------------------------

if (failures.length) {
  console.error(`\n✗ ${failures.length} 项失败 (通过 ${pass} 项):\n`);
  for (const f of failures) console.error('  ✗ ' + f + '\n');
  process.exit(1);
}
console.log(`✓ test_stripkey: ${pass} 项全部通过`);
