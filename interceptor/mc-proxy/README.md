# BSK Hypixel 本地反代（Minecraft 进程拦截）

> 让 **Minecraft（或任何程序）** 里发往 `api.hypixel.net` 的请求，
> 自动走我们的反代 `hyp-api.firebounce.today`，并自动带上你的 `bsk_` Key。
>
> **不用改 mod，不用改配置，不用改 hosts 之外任何东西。**
> 两个开关：**拦截** / **恢复**。

---

## 为什么必须拆 TLS（先说清楚，这不是多此一举）

Minecraft 连的是 **`https://api.hypixel.net`**，证书是 Hypixel 的。

我们要把请求改道到 `hyp-api.firebounce.today`，中间就必须**在本地把 TLS
拆开**才能改请求内容 —— 而 `api.hypixel.net` 的证书我们**没有**。

所以只能：本地生成一张 `api.hypixel.net` 的证书，让系统信任签发它的
本地 CA。这跟 mitmproxy / Charles / Fiddler 是同一个原理，**绕不过去**。

> 换句话说：**只改 hosts 不改证书是没用的** —— Minecraft 会因为证书
> 不匹配直接报错。

---

## 前提

| 需要 | 说明 |
| --- | --- |
| Windows | 只在 Windows 上测过 |
| Node.js 18+ | 代理是 Node 写的（零第三方依赖）。没有就装：https://nodejs.org/ |
| 管理员权限 | 改 hosts 需要。脚本会自己弹 UAC，点「是」就行 |
| 装一次根证书 | 会弹一次系统确认框，点「是」 |

---

## 用之前：先填 Key

第一次运行会在 `config.json` 里留一个空的 `apiKey`，脚本会**当场问你**要。

没有 Key：在 QQ 群里发 `/apikey 你的QQ号` 申请，群号 **519594836**。

> 反代**只认 `bsk_` 开头的 Key**，Hypixel 官方自己申请的那种在这里没用。

---

## 两个开关

### 拦截 —— 双击 `拦截.cmd`

会依次做五件事（每一步都有中文提示）：

1. 检查环境、清掉上次残留的 hosts 行
2. 生成本地 CA + `api.hypixel.net` 证书，并把 CA 装进「受信任的根证书颁发机构」
3. 写 `config.json`
4. **备份 hosts** → 写入 `127.0.0.1 api.hypixel.net` → 清 DNS 缓存
5. 启动本地代理（监听 `127.0.0.1:443`，会新开一个窗口，**别关它**）

看到绿色的「拦截已开启」就成了。**然后重启 Minecraft**（Java 有 DNS 缓存，
不重启可能还在连旧地址）。

### 恢复 —— 双击 `恢复.cmd`

1. 停掉代理进程（含按命令行扫描的残留清理）
2. **从 hosts 里删掉我们加的那行**
3. 清 DNS 缓存并复查
4. 保留根证书（下次拦截就不用再装一遍；想删加 `-RemoveCa`）

### 状态 —— 双击 `状态.cmd`

一眼看清：hosts 有没有被改、代理在不在跑、443 端口谁占着、证书信不信、
Key 填没填、最近几条日志。

---

## 「可恢复」是硬要求，所以做了这些

改 hosts 是有风险的操作（改坏了那台机器就连不上 `api.hypixel.net` 了），
所以：

1. **改之前整份备份** hosts，带时间戳存到 `hosts-backup\`
2. **恢复不靠备份**：我们加的行带固定标记
   `# BSK-HYPIXEL-PROXY`，恢复时**按标记删**。
   为什么不用备份覆盖？因为用户在拦截期间可能自己改过 hosts，
   覆盖会把他后来的改动一起吞掉。按标记删只动我们自己加的东西。
3. **恢复不依赖代理还活着** —— 代理早崩了、窗口早关了，照样能恢复
4. **重复拦截不会堆积** —— 每次拦截前先清掉上次残留的行
5. **PID 文件由代理自己写**，而且停之前会核对命令行里确实有 `proxy.js`
   （PID 会被系统回收，只看数字可能杀错进程）
6. 就算全崩了，你也能**手动**打开
   `C:\Windows\System32\drivers\etc\hosts`，删掉那两行带标记的内容 ——
   它长这样：

   ```
   # BSK-HYPIXEL-PROXY 由 bsk-proxy.ps1 添加 —— 跑「恢复」即可移除
   127.0.0.1	api.hypixel.net
   ```

---

## 工作原理

```
Minecraft (mod)
   │  它以为自己在连 api.hypixel.net:443
   ▼
hosts: api.hypixel.net -> 127.0.0.1
   │
   ▼
本地代理 (proxy.js, 监听 127.0.0.1:443)
   │  ① 用本地 CA 签的 api.hypixel.net 证书终止 TLS
   │  ② 读出 HTTP 请求
   │  ③ 原样转发到 hyp-api.firebounce.today，并塞上你的 bsk_ Key
   │  ④ 响应原封不动还回去
   ▼
hyp-api.firebounce.today  →  Hypixel 官方 API
```

path、query、body、状态码、响应头**全都不动** —— 对调用方完全透明。

**为什么不用 CONNECT 代理**：我们是靠 hosts 把域名指过来的，客户端是
**直连** TCP，不会发 `CONNECT`。所以只要一个普通 HTTPS 服务器 + 一张对得上
的证书就够了，不用写完整代理协议 —— 简单很多，出错面也小得多。

---

## 常见问题

**Q：装完没生效？**
重启 Minecraft。Java 有 DNS 缓存，不重启可能还在连旧地址。
还不行就跑 `状态.cmd` 看 hosts 和代理是不是都在。

**Q：Minecraft 报证书错误 / SSL 错误？**
根证书没装成功。跑 `状态.cmd` 看「根证书」那行是不是「已信任」。
手动装：双击 `certs\BSK-CA.cer` → 安装证书 → 当前用户 →
「受信任的根证书颁发机构」。

**Q：443 端口被占？**
一般是上次的代理没退干净。先跑一次 `恢复.cmd` 再拦截。

**Q：能拦到所有程序吗？**
凡是走**系统 hosts 解析**的都能拦到（Minecraft、绝大多数程序）。
拦不到的：自己写死 IP 的、自己走 DoH/DoT 解析 DNS 的、
或者已经连好了长连接的。

**Q：安全吗？我的 Key 会不会泄漏？**
- 代理只监听 `127.0.0.1`，**外网连不进来**
- 只会把 Key 发给 `hyp-api.firebounce.today`，转发目标写死在 `config.json`
- 非目标 SNI（别的域名）直接拒绝
- Key 存在本地 `config.json` 里，**别把这个文件发给别人、别传网盘**

**Q：会不会影响我正常上 Hypixel 服务器？**
不会。只动了 `api.hypixel.net` 这一个域名，游戏本身的连接（
`*.hypixel.net` 的其它子域）没碰。

**Q：拦截期间电脑重启了怎么办？**
hosts 改动是持久的，重启后仍然指向本机，但**代理没在跑** →
那期间连 `api.hypixel.net` 会失败。所以不用的时候记得跑 `恢复.cmd`。

---

## 文件说明

```
mc-proxy/
├── 拦截.cmd            双击 = 开启拦截（自动提权）
├── 恢复.cmd            双击 = 恢复原样（自动提权）
├── 状态.cmd            双击 = 查看状态（不需要管理员）
├── bsk-proxy.ps1       主控脚本，三个动作都在这里
├── proxy.js            本地 MITM 代理（Node，零依赖）
├── tests/
│   └── test_client.mjs 模拟 Minecraft 连接方式的测试客户端
└── （运行后生成）
    config.json         配置：反代地址 / 你的 Key / 监听端口
    certs/              生成的证书
    hosts-backup/       hosts 备份
    proxy.log           代理日志
    proxy.pid           代理进程号
```

命令行也能用：

```powershell
.\bsk-proxy.ps1 拦截
.\bsk-proxy.ps1 恢复
.\bsk-proxy.ps1 状态
.\bsk-proxy.ps1 恢复 -RemoveCa     # 连根证书一起删
```

---

## 测试过什么

在 Windows 上真跑过一遍完整链路：

- 生成本地 CA + `api.hypixel.net` 证书 ✓
- 代理启动、监听、写 PID ✓
- 用 `test_client.mjs` 模拟 Minecraft 的连接方式（SNI 和 Host 都用
  `api.hypixel.net`）打过去 ✓
- `/v2/player?uuid=...` 返回 200，**query 原样保留** ✓
- 日志显示 `[已注入 Key bsk_efbb…b398]` ✓
- 恢复：停进程 + 删 hosts 行 + 清 PID ✓

跑测试客户端：

```bash
node tests/test_client.mjs 8443 "/v2/player?uuid=<某个UUID>"
```

---

## 注意

- 这东西会**改你的 hosts 文件**。不用时请跑 `恢复.cmd`。
- 根证书装进了「受信任的根证书颁发机构」—— 它只用于给
  `api.hypixel.net` 签证书。想删就 `.\bsk-proxy.ps1 恢复 -RemoveCa`。
- 数据来源仍然是反代，**不是 Hypixel 官方直发**；准确性以
  [官方文档](https://github.com/HypixelDev/PublicAPI) 为准。
