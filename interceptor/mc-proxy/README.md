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

## ★ Java 不认证书？两个都必须做

这是这个工具**最容易失败的地方**，而且失败时的报错跟"拦截器坏了"长得一模一样：

```
javax.net.ssl.SSLHandshakeException:
  PKIX path building failed: unable to find valid certification path to requested target
```

**浏览器一切正常、只有 Minecraft 挂** —— 因为 Java 完全不看 Windows 根证书库。
要做两件事，缺一不可：

### ① CA 证书必须有 `basicConstraints: CA:TRUE`

`New-SelfSignedCertificate -KeyUsage CertSign` **不会**自动加这个扩展。
没有它的时候：

| 谁 | 反应 |
| --- | --- |
| Windows 根证书库 | 不管，照用 —— 所以**很容易以为没问题** |
| 浏览器 | 不管，照常工作 |
| **Java 的 PKIX** | **直接拒绝**：`TrustAnchor with subject "..." is not a CA certificate` |

脚本现在会**主动检查**这条，发现旧 CA 不合规就自动重签（用
`-Type Custom -TextExtension '2.5.29.19={critical}{text}ca=1'`）。

> 顺便：`keyUsage` **不能**塞进 `-TextExtension` —— 那边不认
> `keyCertSign` 这种关键字，也不认数值位掩码（`86` / `160` / `a0` 全报
> `0x80070057`），必须用独立的 `-KeyUsage` 参数。

### ② CA 必须导进**每个 JRE 自己的** `cacerts`

Java 用的是 `<JRE>\lib\security\cacerts`，跟系统库毫无关系。
而且启动器会带**好几份** JRE —— 游戏用哪份是按版本挑的，
**只导一份的话换个版本玩就又挂了**。

`拦截.cmd` 会**全盘扫描**所有固定磁盘，找出每一个 `lib\security\cacerts` 并导入。

> **为什么必须全盘扫**：第一版只扫了固定几个位置（Program Files 和
> `%APPDATA%\.minecraft`），结果实测一台机器上有 **31 个** cacerts ——
> 国内玩家的机器通常装了好几个启动器 / 整合包 / 客户端，每个自带 JRE，
> 而且 `.minecraft` 经常在别的盘：
>
> ```
> E:\DESKTOP\mc\.minecraft\runtime\jre-legacy\...      ← 官方启动器 1.8.9 用的
> E:\DESKTOP\mc\.minecraft\runtime\java-runtime-*\...
> E:\DESKTOP\mc\ViaProxy 一键启动\jdk-1.8\jre\...
> D:\MCLDownload\ext\...   C:\MCLDownload\ext\...
> ```
>
> 只扫固定位置的话，**游戏真正在用的那几个一个都扫不到** ——
> 证书导了一堆没用的，游戏还是 PKIX 报错。

扫描结果缓存 **24 小时**（第一次全盘扫约 1~2 分钟，之后 2 秒）。
新装了启动器就 `.\bsk-proxy.ps1 拦截 -ForceRescan` 重扫。
自动扫不到的地方，在 `config.json` 里加 `extraJavaRoots`：

```json
"extraJavaRoots": ["E:\\某个启动器", "D:\\另一个整合包"]
```

改动前每个 `cacerts` 都会备份成 `cacerts.bsk-backup`。

> ⚠️ **必须用管理员身份跑「拦截」** —— `C:\Program Files\...` 里的需要管理员
> 权限才能写。脚本会自己弹 UAC，点「是」就行。哪个没导成功，收尾会列出来。

### ③ 有些客户端每次启动都会把 JRE **重铺一遍** —— 往它里面导证书永远是白干

**Lunar Client 就是这样。** 每次启动游戏，它都把自带的 JRE 重新铺开：
`<lunar>\jre\<hash>\zulu*\lib\security\` 整个目录（连 `cacerts` /
`blocked.certs` / `default.policy`）时间戳被刷成启动那一秒。实测时间线：

| 时间 | 事件 |
|---|---|
| 13:07 | 把 CA 导进 Lunar 的 zulu17 → `cacerts` 变成 123740 字节 |
| 13:08 | 用同一个 JRE 跑探针 → `HTTP 200`，PKIX 消失（**那时还没开游戏**） |
| 18:19 | Lunar 启动游戏 → 目录被重铺，`cacerts` 缩回 122913 字节、别名没了 |
| 18:20 | 游戏里 `PKIX path building failed` → `[Meow] Failed to fetch bedwars stats` |

也就是说 13:08 那次"成功"**只是因为游戏还没重启**。这条路走不通。

**解法：另建一个不会被重铺的信任库**，再用 `JAVA_TOOL_OPTIONS` 让所有 JVM 都用它。
`拦截.cmd` 现在会自动做这件事：

```
独立信任库 : C:\ProgramData\BSK-Hypixel\cacerts-jks     （109 个公共根 + 我们的 CA）
用户级环境 : JAVA_TOOL_OPTIONS = -Djavax.net.ssl.trustStore=<上面那个> \
                                 -Djavax.net.ssl.trustStorePassword=changeit \
                                 -Djavax.net.ssl.trustStoreType=JKS
```

不动 Lunar 的任何设置，**重启游戏就生效**。同时 `拦截` 会**跳过** Lunar 的 JRE
（导了也白导，省时间，也不再打印误导性的"已导入"）。

两个约束是实测踩出来的，别改：

- **路径必须纯 ASCII。** mc-proxy 本身常常装在中文路径下（这台机器上就是
  `E:\DESKTOP\新建文件夹\…`），而 `-Djavax.net.ssl.trustStore=<中文路径>`
  会因为代码页转换坏掉 —— `keytool` 已经被同一个坑坑过一次。`ProgramData`
  在 Windows 上恒为 ASCII，所以放那儿；要换位置就在 `config.json` 里加
  `javaTrustStore`。
- **格式必须 JKS。** Java 8 读不了新 JDK 生成的 PKCS12 默认库，
  实测报 `NoSuchAlgorithmException`。所以导入完还要 `-importkeystore` 转一次。

> **重启 Lunar 要连启动器一起退。** 游戏 JVM 继承的是**启动器**的环境变量；
> 启动器如果是在设 `JAVA_TOOL_OPTIONS` 之前打开的，它那份环境里没有这一项，
> 直接开游戏照样 PKIX。启动器含托盘/后台进程。

`拦截` 会把这件事的成败显示在收尾信息里，`状态.cmd` 也会单独报一行
（`Java信任库: 就绪 / 还没建`）。**下次游戏里再报 PKIX，先看这一行。**

### 验证 Java 那边到底通没通

仓库里带了两个直接用 JVM 发请求的工具：

- `tests/JavaTlsTest.java` —— Java 9+
- `tests/JavaTlsTest8.java` —— **只用 Java 8 的 API**（1.8.9 用的是 Java 8，
  `readAllBytes()` 是 Java 9+ 的，在它上面编译不过）

```bash
# Java 8 的要用 JDK 1.8 编译。★ 必须加 -encoding UTF-8，
# 否则它的 javac 按 GBK 读源码，中文注释直接报"编码GBK的不可映射字符"
"C:\Program Files\Java\jdk-1.8\bin\javac.exe" -encoding UTF-8 -d . tests/JavaTlsTest8.java

# 用**游戏实际用的那个** JRE 跑
"E:\...\.minecraft\runtime\jre-legacy\bin\java.exe" -cp . JavaTlsTest8 "https://api.hypixel.net/v2/resources/games" bsk_你的Key
```

通了就是：

```
HTTP 200
Java 1.8.0_51
服务端证书 subject : CN=api.hypixel.net
服务端证书 issuer  : CN=BSK Hypixel Local CA
BODY {"success":true,...}
```

失败会是 `PKIX path building failed`。

### 已知的坑：Cloudflare 会拦 `Java/*` 这个 UA

如果你的反代挂在 Cloudflare 后面、又开着 **Browser Integrity Check**，
那么把 User-Agent 设成 Java 默认的 `Java/1.8.0_51` 会被 **403 error code 1010**。

实测确认过（修好证书之后才暴露出来）：TLS 完全正常，纯粹是 CF 拦 UA。

修法是在 CF 里加一条 WAF 规则，**只对 API 域名**跳过 BIC：
`action = skip`，`products = ["bic"]`，
表达式 `http.host in {"hyp-api.firebounce.today" "api.firebounce.today"}`。
**别把整个 zone 的 BIC 关掉** —— 那是给浏览器站点用的保护，留着。

## 常见问题

**Q：装完没生效？**
重启 Minecraft。Java 有 DNS 缓存，不重启可能还在连旧地址。
还不行就跑 `状态.cmd` 看 hosts 和代理是不是都在。

**Q：Minecraft 报证书错误 / SSL 错误 / `PKIX path building failed`？**
看上面那节「★ Java 不认证书？两个都必须做」。
最常见的是：**没用管理员身份跑「拦截」**，导致 `C:\Program Files\Java\...`
那几个 JRE 的 cacerts 没导进去。

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

**Q：我把 `proxy.js` 换成新版本了，怎么好像没生效？**
代理是**常驻进程**，跑起来之后就把代码读进内存了 —— 只覆盖文件**不会**让它用上新代码。
判据是 `proxy.pid` 里那个进程的启动时间**早于** `proxy.js` 的修改时间：

```powershell
(Get-Process -Id (Get-Content .\proxy.pid)).StartTime
(Get-Item .\proxy.js).LastWriteTime
```

前者更早 = 正在跑的是旧代码。重跑一次 `拦截.cmd` 即可（它会先停掉旧进程再拉起新的；
`Ensure-Certs` / Java 信任库都有状态缓存，第二次基本是秒过）。
**另一个坑**：如果 `拦截.cmd` 里那句「本机 443 端口已被占用」出现，说明旧进程还活着 ——
因为它多半是**提权**启动的，任务管理器里普通权限也杀不掉，必须走 `拦截.cmd`（内部会 UAC 提权）。

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
- `?key=<别人自己的key>` 被**剥掉**、照样 200 ✓（见下面那条坑）
- 恢复：停进程 + 删 hosts 行 + 清 PID ✓

跑测试客户端：

```bash
node tests/test_client.mjs 8443 "/v2/player?uuid=<某个UUID>"
```

纯函数（不改 key / 注入 key 的规则）有单测，**不需要网络也不需要证书**：

```bash
node tests/test_stripkey.mjs     # 25 项
python tests/test_interceptor.py # 29 项（含 Windows 编码地雷的回归）
```

Lunar 那条链路真跑过（用模组那种 `?key=<真 key>&name=` 形态）：

| JRE | 结果 |
|---|---|
| Lunar 自带 `zulu17.64.17` | `HTTP 200`，签发者 `CN=BSK Hypixel Local CA` |
| 1.8.9 的 `jre-legacy`（Java 1.8.0_51） | `HTTP 200`，同上 |

两者都用**独立信任库**（JKS 格式，Java 8 也读得了），跟 Lunar 的 JRE 无关。

---

## 踩过的坑（都写了回归测试）

**`stripKeyFromQuery` 曾经完全没生效，而且是静默的。**
很多模组把 Key 拼在 URL 里：`/v2/player?key=<它自己的 Hypixel Key>&name=xxx`，
而反代**认 URL 参数优先于请求头** —— 不剥掉就是每次 401
（`Invalid API key. This key was not issued by ...`）。
当时写的是 `new URL(rawUrl)`，可 Node 的 http server 给的是**纯路径**
（`/v2/player?key=x`，没有 scheme/host），`new URL` 直接抛 `Invalid URL`，
外层 try/catch 一兜就 `return rawUrl` —— 于是"剥 key"从来没执行过。
更坑的是**日志看正常**（日志打的是剥离前的原始 URL），只有返回 401 才露馅。
现在改成按 `&` 逐段字符串处理，**不做 URLSearchParams 编解码**
（那会把空格变成 `+`、重排参数，就不是"原样透传"了）。

**`bsk-proxy.ps1` 发现 443 被占就直接放弃，却照样打印绿色的「拦截已开启」。**
代理是常驻进程，改了 `proxy.js` 之后重跑「拦截」本该自动换新，但它只是警告一句
"先跑一次恢复再试"，于是"我更新了代码怎么没生效"变成一个查不出来的坑。
现在：443 上那个进程如果**确认是我们上次拉的**（PID 文件对得上，或命令行里有
`proxy.js`）就自动停掉再拉新的；**不是我们的一律不动**，如实报错。
另外代理没起来时不再打印绿色的「已开启」—— hosts 确实改好了，可本机没人在听 443，
这期间的请求是直接失败的，界面必须说实话。

**提权启动的代理，非提权会话读不到它的命令行。**
`Get-ProxyProcess` 原本要求命令行里能看到 `proxy.js`，读不到就 `return $null` ——
于是「恢复」眼睁睁看着旧代理占着 443，却报"没有正在跑的代理"。
现在命令行**读不到**时改认 PID 文件（那是 `proxy.js` 自己写的，证据足够），
只有命令行**读得到且不匹配**才否定。

**客户端因为不信任证书而中止握手时，代理日志里一个字都没有。**
`tlsClientError` 没接 —— 握手失败就不会有 HTTP 请求，业务日志自然一片空白。
于是"游戏里 PKIX"在代理这边**完全看不到证据**，只能靠猜（Lunar 那次就是这么
查了一下午：日志干干净净，看起来像"拦截器根本没生效"）。
现在接了 `tlsClientError`，会打出 `★ TLS 握手失败 [<SNI>]: <原因>` 和一句怎么办。

**`Ensure-JavaTrustStore` 第一次跑必然失败：`别名 <bsk-hypixel-local-ca> 已经存在`。**
底料是从机器上随便一个 `cacerts` 拷的，而 `Sync-JavaTrustStores` 之前已经往
**所有** JRE 里导过我们的 CA。修法是**先 `-delete` 再 `-importcert`** ——
顺带也解决了 CA 轮换（旧 CA 会被换成新的）。

**含中文的 `.ps1` 一旦丢了 UTF-8 BOM，整份脚本语法错乱。**
Windows PowerShell 按 ANSI 读无 BOM 的文件，中文字节被解成别的字符，
只要解出一个引号，字符串就错位了。实测报 20+ 处语法错误、完全跑不起来。
编辑器/工具在改文件时很容易把 BOM 吃掉 —— 所以钉了回归测试
（`interceptor/tests/test_interceptor.py::FileEncodingTest`）看着它。
同理 `.cmd` 必须纯 ASCII：`cmd.exe` 按 OEM 代码页读，中文会乱码并可能拆坏命令。

---

## 注意

- 这东西会**改你的 hosts 文件**。不用时请跑 `恢复.cmd`。
- 根证书装进了「受信任的根证书颁发机构」—— 它只用于给
  `api.hypixel.net` 签证书。想删就 `.\bsk-proxy.ps1 恢复 -RemoveCa`。
- 数据来源仍然是反代，**不是 Hypixel 官方直发**；准确性以
  [官方文档](https://github.com/HypixelDev/PublicAPI) 为准。
