# BSK Hypixel API 反代工具

把发往 `api.hypixel.net` 的请求改成走我们的反代
`https://hyp-api.firebounce.today`，并自动带上你的 `bsk_` Key。

两种做法，按场景选：

| 你要拦的是 | 用哪个 | 怎么用 |
| --- | --- | --- |
| **Minecraft / 任意桌面程序** | [`mc-proxy/`](./mc-proxy/README.md) | 两个开关：双击「拦截」/「恢复」 |
| **你自己的脚本 / 网页代码** | 本页的 `bsk-hypixel-interceptor.js` / `bsk_hypixel_interceptor.py` | 一行 `install()` |

---

## 一、Minecraft / 桌面程序 → 用 `mc-proxy`

> 详细说明见 **[`mc-proxy/README.md`](./mc-proxy/README.md)**

双击 **`拦截.cmd`** 开始，双击 **`恢复.cmd`** 还原。

原理简述：改 hosts 把 `api.hypixel.net` 指到 `127.0.0.1`，本地一个
小代理用**自己签的证书**把 TLS 拆开、改写后转发到反代。

**必须在系统里装一次本地根证书** —— 因为 `api.hypixel.net` 的证书是
Hypixel 的、我们没有，不拆 TLS 就改不了请求。这跟 mitmproxy / Charles
一个原理，绕不过去。

「可恢复」是硬要求：hosts 改之前整份备份，恢复时按标记删我们的行
（不覆盖备份 —— 免得吞掉用户后来的改动），且**不依赖代理还活着**。

---

## 二、自己的代码 → 用拦截器库

### JavaScript（浏览器 / Node）

```html
<script src="bsk-hypixel-interceptor.js"></script>
<script>
  BSKHypixel.install({ apiKey: 'bsk_你的Key' });
  // 之后照常写 api.hypixel.net，会被自动改道
</script>
```

```js
// Node / Electron
const BSKHypixel = require('./bsk-hypixel-interceptor.js');
BSKHypixel.install({ apiKey: process.env.BSK_KEY });
```

支持 `fetch`（字符串和 `Request` 两种形态）和 `XMLHttpRequest`。
浏览器里打开 [`demo.html`](./demo.html) 可以现场试。

### Python

```python
import bsk_hypixel_interceptor as bsk
bsk.install(api_key="bsk_你的Key")

import requests
requests.get("https://api.hypixel.net/v2/player", params={"uuid": "..."})
# ↑ 实际打到反代，并带上你的 Key
```

`urllib` 也拦。也可以当上下文管理器：

```python
with bsk.intercept(api_key="bsk_..."):
    requests.get("https://api.hypixel.net/v2/games")
```

---

## 配置项

| 配置 | 默认值 | 说明 |
| --- | --- | --- |
| `proxyBase` / `proxy_base` | `https://hyp-api.firebounce.today` | 反代地址 |
| `targetHosts` / `target_hosts` | `['api.hypixel.net']` | 哪些域名算"原来的 Hypixel API" |
| `apiKey` / `api_key` | 空 | 你的 `bsk_` Key。留空 = 不改 Key |
| `forceKey` / `force_key` | `true` | **强制**用上面的 Key（覆盖调用方原有的） |
| `debug` | `false` | 打印每一步改写 |
| `onIntercept`（仅 JS） | `null` | 拦到之后回调 `(原地址, 新地址)` |

**`forceKey` 说明**：开的时候不只是"加上我们的 Key"，还会把调用方
**原来带的 Key 头删掉**。不删的话有些实现会优先读旧的那个，等于没换。

---

## 几个实现上的坑（都踩过，都留了测试）

**1. 目标判定必须用 host 精确比较。**
用 `includes` / `endswith` 的话，`api.hypixel.net.evil.com` 会被当成目标
—— 等于主动把你的 `bsk_` Key 送给钓鱼站。有专门的回归测试盯着这条。

**2. 浏览器里要用 `X-API-Key` 而不是 `API-Key`。**
跨域自定义头必须在服务端 `Access-Control-Allow-Headers` 白名单里，
否则**预检就过不去**。反代白名单是
`Authorization, X-API-Key, Content-Type` —— **没有 `API-Key`**。
所以浏览器自动用 `X-API-Key`，Node/Python 没有 CORS 就用官方习惯的
`API-Key`（反代两种都认）。

**3. 两种目标都要管。**
发给官方的 → 改写 + 补 Key；本来就发给反代的 → 只补 Key。
只在"地址变了"时才补 Key 的话，*"我把 baseURL 直接写成反代但想自动
填 Key"* 这个合理用法会**静默失效**（Key 不补，请求 401）。
这个是写测试时才发现的。

**4. Windows 上写 JSON 不能带 BOM。**
PowerShell 的 `Set-Content -Encoding UTF8` 会加 BOM，Node 的 `JSON.parse`
碰到 BOM 直接报错。`mc-proxy` 那边专门有个 `Write-TextNoBom`。
（**这个是真炸过**：配置写出来代理起不来。）

**5. Node 的 `console.log('a %s', b)` 不替换占位符。**
手写 `arguments.join(' ')` 的话日志会原样打出 `%s`。要走 `util.format`。
（也是实测发现的。）

---

## 边界

- 拦不到自己写死 IP、或者自己做 DoH/DoT 解析 DNS 的程序。
- Node 里用 `axios` 走的是 `http`/`https` 模块，`fetch` 补丁拦不到；
  请改用 `fetch`，或直接把 `baseURL` 改成反代。
- 反代是**透明转发**，格式和官方一致，但数据本身不是 Hypixel 官方直发，
  准确性以 [官方文档](https://github.com/HypixelDev/PublicAPI) 为准。
- 反代**只认 `bsk_` 开头的 Key**，官方申请的 Hypixel Key 在这里没用。

---

## 目录

```
interceptor/
├── mc-proxy/                    ← Minecraft / 桌面程序（含自己那份 README）
├── bsk-hypixel-interceptor.js   ← 核心（JS）
├── bsk_hypixel_interceptor.py   ← 核心（Python）
├── demo.html                    ← 浏览器在线测试页（中文界面）
└── tests/
    ├── test_interceptor.mjs     ← JS 测试（node 跑）
    └── test_interceptor.py      ← Python 测试
```

## 跑测试

```bash
node tests/test_interceptor.mjs                                  # JS
python -m unittest discover -s tests -p "test_interceptor.py" -v # Python
```

测试会**真起一个本地假反代**、真发请求 —— 只测纯函数会漏掉
"补丁压根没挂上"这种问题（这个也真踩到了）。

---

## 注意

- 你的 Key 等于你的身份，**别贴群里、别提交进仓库**。
- 泄漏了找管理员 `/apikey revoke <你的Key>` 停用。
- 没有 Key：QQ 群 **519594836**，或发 `/apikey help` 看流程。
