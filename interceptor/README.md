# BSK Hypixel API 反代拦截器

> 把代码里**所有发给 `api.hypixel.net` 的请求自动改道**到我们的反代
> `https://hyp-api.firebounce.today`，并自动填上你的 `bsk_` Key。
>
> **业务代码一行都不用改。** 拦截器在**网络层**动手。

---

## 为什么需要它

很多现成的 Hypixel 工具、网页、脚本把 API 地址**写死在代码深处**，
或者干脆是别人打包好的、你改不了。想换成反代就得一个个找、一个个改，
还容易漏。

这个拦截器直接在网络层拦下请求：

```
应用代码  →  api.hypixel.net/v2/player?uuid=xxx
                        ↓  拦截器改道（应用无感）
           →  hyp-api.firebounce.today/v2/player?uuid=xxx
                        ↓  自动带上你的 bsk_ Key
```

**为什么值得换到反代：**

- 国内直连 `api.hypixel.net` 经常超时/丢包，反代走的是能连通的线路
- 不用自己去 Hypixel 官网申请 Key（那个要排队审核）
- 反代是**透明转发**：端点、参数、返回格式跟官方**完全一致**，
  所以你原来的解析代码不用动

---

## 快速开始

### 1. 网页 / 油猴脚本（最省事）

装油猴脚本 [`userscript/bsk-hypixel-proxy.user.js`](./userscript/bsk-hypixel-proxy.user.js)，
装完页面右下角会出现一个 **BSK** 悬浮按钮，点开填上你的 Key 就行。

- 配置**在所有网站之间共享**（用 `GM_setValue` 存，不是 localStorage）
- 带开关，随时能关掉
- 核心代码是**内嵌**的，不依赖任何远程加载 —— 国内也能正常用

> 没有 Key？在 QQ 群里发 `/apikey 你的QQ号` 申请，群里也有：`519594836`

### 2. 浏览器 / Node（JS）

```html
<script src="bsk-hypixel-interceptor.js"></script>
<script>
  BSKHypixel.install({ apiKey: 'bsk_你的Key' });
  // 之后代码里照常写 api.hypixel.net，会被自动改道
</script>
```

```js
// Node / Electron
const BSKHypixel = require('./bsk-hypixel-interceptor.js');
BSKHypixel.install({ apiKey: process.env.BSK_KEY });
```

### 3. Python

```python
import bsk_hypixel_interceptor as bsk

bsk.install(api_key="bsk_你的Key")

import requests
requests.get("https://api.hypixel.net/v2/player", params={"uuid": "..."})
# ↑ 实际打到反代，并带上你的 Key
```

标准库 `urllib` 也拦：

```python
import urllib.request
urllib.request.urlopen("https://api.hypixel.net/v2/games")
```

也可以当上下文管理器，离开自动还原：

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
| `debug` | `false` | 打印每一步改写，排查问题时开 |
| `onIntercept`（仅 JS） | `null` | 拦到之后回调 `(原地址, 新地址)`，用来记账 |

**`forceKey` 说明**：开的时候不只是"加上我们的 Key"，还会把调用方
**原来带的 Key 头删掉**。不删的话有些实现会优先读旧的那个，等于没换。

---

## 拦截范围

| 方式 | 支持 | 说明 |
| --- | --- | --- |
| `fetch()` | ✅ | 字符串 URL 和 `Request` 对象两种形态都拦 |
| `XMLHttpRequest` | ✅ | 包括 `setRequestHeader` 的 Key 覆盖 |
| Python `requests` | ✅ | 含 `Session`，`requests.get/post` 全覆盖 |
| Python `urllib` | ✅ | 含字符串 URL 和 `Request` 对象 |
| Node 里的 `axios` | ❌ | 它走 `http`/`https` 模块，拦不到。请改用 `fetch`，或直接改 `baseURL` |
| 原生 socket / 别的语言 | ❌ | 请直接把 base URL 改成反代地址 |

---

## 工作原理

1. **判断目标**：只处理 host **精确等于** `api.hypixel.net` 的请求。
2. **改写地址**：只换 host，**path 和 query 原样保留** ——
   反代是透明转发，不需要任何路径映射。
3. **注入 Key**：按 `forceKey` 策略写入 `API-Key` 头
   （浏览器里自动改用 `X-API-Key`，见下面的说明）。

### 为什么浏览器里用 `X-API-Key` 而不是 `API-Key`

跨域请求想带自定义头，那个头必须在服务端的
`Access-Control-Allow-Headers` 白名单里，否则**预检就过不去**。

反代的白名单是 `Authorization, X-API-Key, Content-Type` ——
**没有 `API-Key`**。所以浏览器场景自动用 `X-API-Key`；
Node / Python 没有 CORS 这回事，就用更贴近官方习惯的 `API-Key`。
两种写法反代都认。

### 要改的两种情况都管

| 你的代码写的是 | 会做什么 |
| --- | --- |
| 官方 `api.hypixel.net` | 改写到反代 **+** 补 Key |
| 已经是反代地址 | 只补 Key（地址不用改） |

第二种很容易被漏掉：如果只在"地址变了"时才补 Key，那
*"我把 baseURL 直接写成反代，但想让拦截器自动填 Key"* 这个
完全合理的用法就会**静默失效**（Key 不补，请求 401）。

---

## 常见问题

**Q：装上了但请求还是 401？**
先看 `stats()` / 面板上的「已注入 Key」。401 通常是 Key 没填、
或填错了。`/apikey status` 可以查自己的 Key 状态。

**Q：会不会把我发往**别的**网站的 Key 泄漏出去？**
不会。目标判定是 **host 精确比较** —— `api.hypixel.net.evil.com`
这种钓鱼域名**不会**被当成目标（有专门的回归测试盯着这条）。

**Q：Key 存在哪？**
油猴脚本存在 Tampermonkey 的存储里；JS/Python 版本只在内存里，
你不传就不存。演示页 `demo.html` 用了 localStorage，那只是图方便，
**别在正式环境这么做**。

**Q：能不用 Key 吗？**
不行。反代**只认 `bsk_` 开头的 Key**，官方的 Hypixel Key 在这里没用。
这也是要申请 Key 的原因。

**Q：反代和官方返回的数据一样吗？**
是透明转发，格式完全一致。但请注意数据本身**不是 Hypixel 官方**发布的，
可能有延迟或偏差 —— 以 [Hypixel 官方文档](https://github.com/HypixelDev/PublicAPI) 为准。

---

## 目录结构

```
interceptor/
├── bsk-hypixel-interceptor.js   ← 核心（JS，浏览器 + Node）
├── bsk_hypixel_interceptor.py   ← 核心（Python）
├── demo.html                    ← 浏览器在线测试页（中文界面）
├── build_userscript.py          ← 打包油猴脚本
├── userscript/
│   ├── panel.js                 ← 油猴脚本的中文控制面板
│   └── bsk-hypixel-proxy.user.js← 成品（自动生成，可直接安装）
└── tests/
    ├── test_interceptor.mjs     ← JS 测试（node 跑）
    └── test_interceptor.py      ← Python 测试
```

> `bsk-hypixel-proxy.user.js` 是**自动生成**的，别直接改 ——
> 核心代码只有 `bsk-hypixel-interceptor.js` 一份真源，
> 改完核心跑一下 `python build_userscript.py` 重新生成。
> （之所以内嵌而不是油猴 `@require` 远程加载：国内拉 GitHub raw 经常失败，
> 拉不到就整个脚本不可用。）

---

## 跑测试

```bash
# JS（需要 Node 18+）
node tests/test_interceptor.mjs

# Python
python -m unittest discover -s tests -p "test_interceptor.py" -v
```

测试会**真起一个本地假反代**、真发请求 —— 只测纯函数会漏掉
"补丁压根没挂上"这种问题。

---

## 注意

- 你的 Key 等于你的身份，**别贴到群里、别提交进仓库**。
- 泄漏了找管理员 `/apikey revoke <你的Key>` 停用。
- 这个工具只是**转发层**，不改变数据来源；数据准确性以官方为准。
