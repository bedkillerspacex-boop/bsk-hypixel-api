# BSK Hypixel 本地反代 —— 两个开关：拦截 / 恢复
#
#   .\bsk-proxy.ps1 拦截     装上并开始拦截
#   .\bsk-proxy.ps1 恢复     拆掉，恢复原样
#   .\bsk-proxy.ps1 状态     看现在什么情况
#
# 也可以直接双击 拦截.cmd / 恢复.cmd。
#
# ============================================================================
# 「可恢复」是硬要求，所以:
#   1. 改 hosts 之前**先整份备份**（带时间戳），恢复时优先用备份还原
#   2. 备份丢了也能恢复 —— 会按标记逐行删掉我们加的那行（双保险）
#   3. 恢复**不依赖代理还在跑** —— 代理早崩了、窗口早关了，照样能恢复
#   4. 我们的 hosts 行带显式标记，人工也能一眼认出来手动删
#   5. 拦截时会检查并清理上次残留，不会越积越多
# ============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('拦截', '恢复', '状态', 'install', 'restore', 'status')]
    [string]$Action = '状态',

    # 只想重新装证书 / 重新写 hosts，不动代理
    [switch]$NoStart,

    # 恢复时连根证书一起删掉
    [switch]$RemoveCa,

    # 拦截时**不**碰 Java 信任库（默认会导，因为不导 Java 程序就报证书错）
    [switch]$NoJava,

    # 恢复时把 CA 从 Java 信任库里也移出去
    [switch]$RemoveJava,

    # 忽略缓存, 重新全盘找一遍 Java 信任库
    # （新装了启动器 / 整合包之后用它）
    [switch]$ForceRescan
)

$ErrorActionPreference = 'Stop'

# ---- 路径 ------------------------------------------------------------------

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$CertDir   = Join-Path $Root 'certs'
$CfgPath   = Join-Path $Root 'config.json'
$PidFile   = Join-Path $Root 'proxy.pid'
$LogFile   = Join-Path $Root 'proxy.log'
$StateFile = Join-Path $Root 'state.json'
$BackupDir = Join-Path $Root 'hosts-backup'

$HOSTS = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'

# 我们往 hosts 里写的那一行带这个标记 —— 人工排查时一眼能认出来，
# 恢复时也靠它兜底删除（备份丢了也不怕）。
$MARK = '# BSK-HYPIXEL-PROXY'
$TARGET_HOST = 'api.hypixel.net'

$PfxPass = 'bsk-local-proxy'
$CaSubject = 'CN=BSK Hypixel Local CA'
$LeafSubject = "CN=$TARGET_HOST"

# ---- 输出小工具 ------------------------------------------------------------

function Info($t) { Write-Host "  $t" }
function Ok($t)   { Write-Host "  [OK] $t"   -ForegroundColor Green }
function Warn($t) { Write-Host "  [!]  $t"   -ForegroundColor Yellow }
function Bad($t)  { Write-Host "  [X]  $t"   -ForegroundColor Red }
function Step($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    <#
      需要管理员（要改 hosts）时, 自己弹一次 UAC 重新以管理员启动。

      放在脚本里而不是 .cmd 里: .cmd 那边要写 `%~f0` 重新拉起自己,
      路径里有中文时容易被代码页搞乱; 而且 UAC 弹窗后原窗口会立刻关掉,
      用户什么都看不到。这里用 -NoExit, 结果留在窗口里。
    #>
    if (Test-Admin) { return }
    Write-Host ''
    Write-Host '  这个操作需要管理员权限（要改 hosts 文件），正在请求提权…' -ForegroundColor Yellow
    Write-Host '  请在弹窗里点「是」。' -ForegroundColor Yellow
    $a = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit',
        '-File', ('"' + $PSCommandPath + '"'), $Action
    )
    if ($RemoveCa)   { $a += '-RemoveCa' }
    if ($NoStart)    { $a += '-NoStart' }
    if ($NoJava)     { $a += '-NoJava' }
    if ($RemoveJava) { $a += '-RemoveJava' }
    if ($ForceRescan){ $a += '-ForceRescan' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs | Out-Null
    exit
}

function Write-TextNoBom($path, $text) {
    <#
      写 UTF-8 **不带 BOM**。

      ★ 必须用这个, 不能用 `Set-Content -Encoding UTF8`:
        Windows PowerShell 的 UTF8 编码器会**加 BOM**, 而下游 Node 的
        JSON.parse 碰到 BOM 直接抛 "Unexpected token" —— 代理起不来。
        (这个坑是本地实测抓到的, 不是猜的。)
      也不能用 `-Encoding ASCII`: 用户把东西放在带中文的目录里时,
      路径里的中文会被写成问号。
    #>
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

# ---- hosts 操作 ------------------------------------------------------------

function Get-HostsBackupPath {
    Join-Path $BackupDir ("hosts." + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".bak")
}

function Backup-Hosts {
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $dst = Get-HostsBackupPath
    Copy-Item -LiteralPath $HOSTS -Destination $dst -Force
    Ok "hosts 已备份: $dst"
    return $dst
}

function Get-OurHostsLines {
    if (-not (Test-Path $HOSTS)) { return @() }
    @(Get-Content -LiteralPath $HOSTS -ErrorAction SilentlyContinue |
      Where-Object { $_ -like "*$MARK*" -or $_ -match "^\s*[\d\.]+\s+$([regex]::Escape($TARGET_HOST))\s*$" })
}

function Remove-OurHostsLines {
    <#
      删掉我们加的行。**按标记删**，不靠备份 —— 备份丢了、或者用户手工
      编辑过 hosts，这条路依然能把环境弄干净。
    #>
    if (-not (Test-Path $HOSTS)) { return 0 }
    $all = Get-Content -LiteralPath $HOSTS -ErrorAction SilentlyContinue
    $keep = @($all | Where-Object {
        -not ($_ -like "*$MARK*") -and
        -not ($_ -match "^\s*[\d\.]+\s+$([regex]::Escape($TARGET_HOST))\s*$")
    })
    $removed = $all.Count - $keep.Count
    if ($removed -gt 0) {
        Write-TextNoBom $HOSTS ($keep -join "`r`n")
    }
    return $removed
}

function Clear-DnsCache {
    try { ipconfig /flushdns | Out-Null; Ok 'DNS 缓存已清' }
    catch { Warn 'DNS 缓存没清成（不影响，但可能要等一会儿才生效）' }
}

# ---- 证书 ------------------------------------------------------------------

function Get-ExistingCert($subject, $store = 'Cert:\CurrentUser\My') {
    Get-ChildItem $store -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $subject } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
}

function Test-CaCompliant($cert) {
    <#
      这张证书**能不能当 CA 用**？

      ★ 判据就是 basicConstraints=CA:TRUE (OID 2.5.29.19)。
        没有这个扩展时:
          · 浏览器 / Windows 根库  -> 不管, 照用（所以很容易以为没问题）
          · Java 的 PKIX           -> 直接拒绝: "TrustAnchor with subject
                                      ... is not a CA certificate"
        实测就是被这个坑到: 证书在 Windows 根库里躺着、浏览器一切正常,
        只有 Minecraft（Java）全挂。所以必须显式检查。
    #>
    if (-not $cert) { return $false }
    $bc = $cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' }
    if (-not $bc) { return $false }
    # 格式化出来大概是 "Subject Type=CA\nPath Length Constraint=None"
    $txt = $bc.Format($false)
    return [bool]($txt -match 'CA')
}

function Ensure-Certs {
    <#
      生成（或复用）本地 CA + api.hypixel.net 的叶子证书，并把 CA 装进
      「受信任的根证书颁发机构」(CurrentUser)。

      为什么要装根证书: 浏览器/Java/系统要验证 api.hypixel.net 的证书链，
      而那张证书是我们自己签的。不装根证书 -> TLS 校验失败 -> 请求全挂。

      ★ 本函数**只允许返回证书路径这一个字符串**。
        PowerShell 里 .NET 方法的返回值会**泄漏进管道**成为函数输出 ——
        实测 `$chain.ChainPolicy.ExtraStore.Add($ca)` 返回索引 0，
        结果整个函数返回了 @(0, '路径')，写进 config.json 就成了
        "pfX": [0, "..."] ，Node 找不到证书直接退出，代理起不来。
        而且只在**第二次及以后**运行才触发（第一次不走那个分支），
        所以第一次测试是好的 —— 特别难查。
        下面所有可能产生输出的调用都显式吞掉了。
    #>
    if (-not (Test-Path $CertDir)) { $null = New-Item -ItemType Directory -Path $CertDir -Force }

    $leafPfx = Join-Path $CertDir 'api.hypixel.net.pfx'
    $caCer   = Join-Path $CertDir 'BSK-CA.cer'
    $caPfx   = Join-Path $CertDir 'BSK-CA.pfx'

    $ca = Get-ExistingCert $CaSubject
    if ($ca -and -not (Test-CaCompliant $ca)) {
        # ★ 老版本生成的 CA **没有 basicConstraints 扩展**, Java 的 PKIX 会直接
        #   拒绝它: "TrustAnchor with subject ... is not a CA certificate"。
        #   浏览器不看这条所以没事, JVM 一定挂 —— 实测被用户抓到了。
        #   检测到不合规就**丢掉重签**, 不能复用。
        Warn '现有 CA 缺 basicConstraints（Java 不认它当 CA），重新生成…'
        Remove-Item "Cert:\CurrentUser\My\$($ca.Thumbprint)" -Force -ErrorAction SilentlyContinue
        $ca = $null
    }

    if (-not $ca) {
        Info '生成本地根证书 (CA)…'
        # ★ 必须 -Type Custom + -TextExtension 手写 basicConstraints。
        #   `-KeyUsage CertSign` **不会**自动加 basicConstraints=CA:TRUE ——
        #   这是最容易漏的一步: Windows 根库里装了、浏览器也认,
        #   但 Java 的 PKIX 会判定"这不是 CA 证书"从而拒绝整条链:
        #     TrustAnchor with subject "CN=..." is not a CA certificate
        #
        #   keyUsage **别**塞进 -TextExtension: 那边不认 keyCertSign 这种关键字,
        #   也不认数值位掩码（86 / 160 / a0 全报 "参数错误" 0x80070057），
        #   必须用独立的 -KeyUsage 参数。（这几个值都实测过。）
        $ca = New-SelfSignedCertificate `
            -Type Custom `
            -Subject $CaSubject `
            -KeySpec Signature `
            -KeyUsage CertSign, CRLSign, DigitalSignature `
            -KeyExportPolicy Exportable `
            -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256 `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -NotAfter (Get-Date).AddYears(10) `
            -TextExtension @('2.5.29.19={critical}{text}ca=1')   # basicConstraints: CA:TRUE
        Ok ("CA 已生成: " + $ca.Thumbprint)
        if (-not (Test-CaCompliant $ca)) {
            Bad 'CA 生成后仍缺 basicConstraints —— 环境异常，中止'
            exit 1
        }
    } else {
        Ok ("复用已有 CA: " + $ca.Thumbprint + "  (basicConstraints 正常)")
    }

    # 叶子证书：换过 CA 就得重签
    $leaf = Get-ExistingCert $LeafSubject
    $needLeaf = $true
    if ($leaf) {
        # ★ 用 **Authority Key Identifier == CA 的 Subject Key Identifier** 判断,
        #   而不是 X509Chain。
        #
        #   为什么不用 X509Chain: 新旧 CA 的 Subject **完全一样**
        #   ("CN=BSK Hypixel Local CA"), 链构建按主题名就能配上 ——
        #   于是换了 CA 之后它照样报"能构建", 结果**复用了旧叶子**,
        #   签名其实对不上、链是断的。实测踩到: 新 CA 生成了,
        #   叶子却没重签, Java 依然报证书错。
        #   AKI/SKI 比的是**密钥标识**, 换了密钥就一定不相等, 这个才靠得住。
        $leafAki = $leaf.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.35' }
        $caSkid = $ca.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.14' }
        if ($leafAki -and $caSkid) {
            $a = ($leafAki.Format($false) -replace '[^0-9a-fA-F]', '').ToLower()
            $b = ($caSkid.Format($false) -replace '[^0-9a-fA-F]', '').ToLower()
            if ($a -and $b -and $a.Contains($b)) {
                $needLeaf = $false
                Ok ("复用已有叶子证书: " + $leaf.Thumbprint)
            } else {
                Info '叶子证书是**另一把 CA 密钥**签的，需要重签'
            }
        }
    }

    if ($needLeaf) {
        if ($leaf) {
            Info '叶子证书是旧 CA 签的，重新签一张…'
            Remove-Item "Cert:\CurrentUser\My\$($leaf.Thumbprint)" -Force -ErrorAction SilentlyContinue
        } else {
            Info "生成 $TARGET_HOST 的证书…"
        }
        # 叶子也手写扩展: 明确 CA:FALSE、限定 keyUsage、EKU 只要 serverAuth。
        # -DnsName 负责加 subjectAltName（现代 TLS 客户端只认 SAN, 不认 CN）。
        # keyUsage / EKU 同样走独立参数, 理由见上面 CA 那段。
        $leaf = New-SelfSignedCertificate `
            -Type Custom `
            -Subject $LeafSubject `
            -KeySpec KeyExchange `
            -KeyUsage DigitalSignature, KeyEncipherment `
            -DnsName $TARGET_HOST `
            -KeyExportPolicy Exportable `
            -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256 `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -NotAfter (Get-Date).AddYears(5) `
            -Signer $ca `
            -TextExtension @('2.5.29.19={critical}{text}ca=0')   # 它不是 CA
        Ok ("叶子证书已生成: " + $leaf.Thumbprint)

        # SAN 必须有 —— 少了它 JVM 会报 "No subject alternative names present"
        $san = $leaf.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' }
        if (-not $san) { Bad "叶子证书没有 SAN，中止"; exit 1 }
    }

    # 导出给 Node 用（Node 直接吃 pfx，省得转 PEM）
    $sec = ConvertTo-SecureString -String $PfxPass -Force -AsPlainText
    Export-PfxCertificate -Cert $leaf -FilePath $leafPfx -Password $sec -Force | Out-Null
    Export-PfxCertificate -Cert $ca   -FilePath $caPfx   -Password $sec -Force | Out-Null
    Export-Certificate   -Cert $ca    -FilePath $caCer   -Force | Out-Null
    Ok '证书已导出'

    # 信任 CA（首次会弹一个系统确认框，点「是」）
    $trusted = @(Get-ChildItem 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue |
                 Where-Object { $_.Thumbprint -eq $ca.Thumbprint })
    if ($trusted.Count -gt 0) {
        Ok 'CA 已在受信任根证书里'
    } else {
        Info '把 CA 装进「受信任的根证书颁发机构」（会弹一次确认框，点「是」）…'
        try {
            $null = Import-Certificate -FilePath $caCer -CertStoreLocation 'Cert:\CurrentUser\Root'
            Ok 'CA 已信任'
        } catch {
            # ★ 这里**不再 exit 1**。
            #   Windows 根库只有浏览器/系统在用; **Java 根本不看它**
            #   （走自己的 cacerts）。而 Java（Minecraft）才是这个工具的主场景,
            #   所以这一步失败不该把整件事拦下来 —— 警告 + 给手动办法就够了。
            #   顺便: 非交互式会话里 Import-Certificate 到 Root 会报
            #   "UI is not allowed in this operation", 属于正常现象。
            Warn "装进 Windows 根库没成功: $($_.Exception.Message)"
            Info "（不影响 Minecraft —— Java 走自己的 cacerts，下面会单独导）"
            Info "想让浏览器也认: 双击 $caCer → 安装证书 → 当前用户 → 受信任的根证书颁发机构"
        }
    }

    if (-not (Test-Path $leafPfx)) {
        # 走到这儿说明导出没成功 —— 早点炸, 别等 Node 报"找不到证书"
        Bad "证书导出失败，文件不存在: $leafPfx"
        exit 1
    }

    # 显式 return 一个字符串, 别让任何意外输出混进去（见函数头的说明）
    return [string]$leafPfx
}

# ---- Java 信任库 ------------------------------------------------------------
#
# ★ 光把 CA 装进 Windows 根库**不够** —— Java 用的是自己的 cacerts, 不看系统库。
#   所以还要把 CA 导进每个 JRE 的 lib\security\cacerts, 否则 Minecraft
#   （以及任何走 Java 访问 api.hypixel.net 的东西）都会报:
#       PKIX path building failed: unable to find valid certification path
#
#   为什么每个 JRE 都要导: 启动器会带**好几份** JRE（实测 Lunar 自带
#   Java 25/17/21 三份, Prism 一份）, 而游戏用哪份是按版本挑的 ——
#   只导一份的话换个版本玩就又挂了。

$JavaAlias = 'bsk-hypixel-local-ca'

function Invoke-Keytool($keytool, [string[]]$Arguments) {
    <#
      跑 keytool, 返回 @(退出码, 输出)。

      ★ 三个坑, 全是实测踩出来的。keytool 是**原生 exe**,
        跟 PowerShell 之间隔着命令行字符串和代码页, 特别容易坏。

      1) 含**空格**的参数要加引号, 而且得自己加。
         `-keystore C:\Program Files\...` 不加引号会被拆成两段。
         这就是为什么 `C:\Users\...\.lunarclient\...`（没空格）能成功,
         而 `C:\Program Files\...` 全失败 —— 命令一模一样。

      2) **参数里别出现中文**。我们的证书在
         `E:\DESKTOP\新建文件夹\...`, 传给 keytool.exe 时按代码页转换会乱,
         结果 keytool 把后面的路径当成"非法选项"报错。
         → 调用方负责先把证书复制到纯 ASCII 的临时路径（见 Sync-JavaTrustStores）。

      3) 用 **Start-Process + 单条参数串**, 别用 `& $exe $array`。
         `&` 的引号规则在 Windows PowerShell 5.1 和 PowerShell 7 下**不一样**
         （7 会自动加引号, 5.1 不会）, 同一份代码两边表现不同。
         Start-Process 收的是**一个字符串**, 引号完全由我们掌控, 版本无关。
         （用户的 .cmd 拉起的是 5.1, 我自测用的是 7 —— 必须两边都对。）
    #>
    $quoted = @($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    })
    $argLine = ($quoted -join ' ')

    $tmpOut = [IO.Path]::GetTempFileName()
    $tmpErr = [IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $keytool -ArgumentList $argLine `
                           -Wait -PassThru -NoNewWindow `
                           -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr `
                           -ErrorAction Stop
        $code = $p.ExitCode
        $out = [string](Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue) +
               [string](Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue)
    } catch {
        $code = -1
        $out = "$($_.Exception.Message)"
    } finally {
        Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
    }
    return @($code, $out)
}

# 扫描时要剪掉的目录 —— 这些底下不可能有游戏用的 JRE, 但会拖慢全盘扫描。
$JavaScanSkip = @(
    'Windows', '$Recycle.Bin', 'System Volume Information', 'ProgramData',
    'PerfLogs', 'Recovery', 'MSOCache', 'Config.Msi', '\node_modules\',
    '\.git\', '\AppData\Local\Temp\', '\AppData\Local\Microsoft\',
    '\AppData\Local\Packages\', '\$WinREAgent'
)

function Test-JavaScanSkip($path) {
    foreach ($s in $JavaScanSkip) {
        if ($path -like "*$s*") { return $true }
    }
    return $false
}

function Get-JavaTrustStores {
    <#
      找出这台机器上**所有**该打理的 cacerts。

      ★ 必须全盘扫, 不能只扫固定几个位置（第一版就是这么写的, 结果漏了）。
        实测用户机器上有 **30 个** cacerts —— 国内玩家的机器上通常装了好几个
        启动器 / 整合包 / 客户端, 每个都自带 JRE:
            E:\DESKTOP\mc\.minecraft\runtime\jre-legacy\...     (官方启动器, 1.8.9 用)
            E:\DESKTOP\mc\.minecraft\runtime\java-runtime-*\...
            E:\DESKTOP\mc\ViaProxy 一键启动\jdk-1.8\jre\...
            D:\MCLDownload\ext\...  C:\MCLDownload\ext\...       (各种启动器)
        只扫 Program Files 和 %APPDATA%\.minecraft 的话, **游戏真正在用的那几个
        一个都扫不到** —— 于是证书导了一堆没用的, 游戏还是 PKIX 报错。

      扫描结果会缓存到 java-stores.json（默认 1 天）, 免得每次拦截都全盘扫一遍。
      config.json 里的 `extraJavaRoots` 可以补扫自动发现够不到的地方。
    #>
    $cacheFile = Join-Path $Root 'java-stores.json'
    $cacheHours = 24
    if (-not $ForceRescan -and (Test-Path $cacheFile)) {
        try {
            $c = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $age = (Get-Date) - [datetime]$c.scannedAt
            if ($age.TotalHours -lt $cacheHours -and $c.stores) {
                $alive = @($c.stores | Where-Object { Test-Path $_ })
                if ($alive.Count -gt 0) {
                    Info "用缓存的 Java 信任库清单（$($alive.Count) 个, $([int]$age.TotalMinutes) 分钟前扫的）"
                    return $alive
                }
            }
        } catch { }
    }

    $found = @()

    # ① 已知位置（快, 先做掉）
    $roots = @(
        (Join-Path $env:USERPROFILE '.lunarclient'),
        (Join-Path $env:APPDATA '.minecraft\runtime'),
        (Join-Path $env:APPDATA 'PrismLauncher'),
        (Join-Path $env:APPDATA 'MultiMC'),
        (Join-Path $env:APPDATA 'com.modrinth.theseus'),
        (Join-Path $env:APPDATA 'gdlauncher_next'),
        (Join-Path $env:USERPROFILE 'curseforge'),
        (Join-Path $env:ProgramFiles 'Java'),
        (Join-Path ${env:ProgramFiles(x86)} 'Java'),
        (Join-Path $env:ProgramFiles 'Eclipse Adoptium'),
        (Join-Path $env:ProgramFiles 'Zulu'),
        (Join-Path $env:ProgramFiles 'BellSoft'),
        (Join-Path $env:ProgramFiles 'Amazon Corretto'),
        (Join-Path $env:ProgramFiles 'Microsoft')
    ) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($r in $roots) {
        Get-ChildItem $r -Recurse -Filter 'cacerts' -File -Depth 7 -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -like '*lib\security*' } |
            ForEach-Object { $found += $_.FullName }
    }

    # ② 用户手工补的根目录（自动发现够不到的地方）
    $cfg = $null
    if (Test-Path $CfgPath) {
        try { $cfg = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if ($cfg -and $cfg.extraJavaRoots) {
        foreach ($r in @($cfg.extraJavaRoots)) {
            if (-not $r -or -not (Test-Path $r)) { continue }
            Get-ChildItem $r -Recurse -Filter 'cacerts' -File -Depth 7 -ErrorAction SilentlyContinue |
                Where-Object { $_.DirectoryName -like '*lib\security*' } |
                ForEach-Object { $found += $_.FullName }
        }
    }

    # ③ 全盘扫（这才是能真正覆盖到的做法）
    $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                Where-Object { $_.Free -ne $null -and (Test-Path $_.Root) } |
                Select-Object -ExpandProperty Root)
    Info "全盘找 Java 信任库（$($drives.Count) 个盘, 可能要几十秒）…"
    foreach ($d in $drives) {
        Get-ChildItem $d -Recurse -Filter 'cacerts' -File -Depth 8 -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.DirectoryName -like '*lib\security') -and -not (Test-JavaScanSkip $_.FullName)
            } | ForEach-Object { $found += $_.FullName }
    }

    $stores = @($found | Sort-Object -Unique)
    Ok "找到 $($stores.Count) 个 Java 信任库"

    try {
        Write-TextNoBom $cacheFile (@{
            scannedAt = (Get-Date).ToString('o')
            stores    = $stores
        } | ConvertTo-Json -Depth 4)
    } catch { }
    return $stores
}

function Get-KeytoolFor($cacertsPath) {
    <# 找同一个 JRE 里的 keytool —— 别用 PATH 上那个（版本可能不匹配）。 #>
    $jre = Split-Path (Split-Path (Split-Path $cacertsPath -Parent) -Parent) -Parent
    $kt = Join-Path $jre 'bin\keytool.exe'
    if (Test-Path $kt) { return $kt }
    $g = Get-Command keytool -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    return $null
}

function Test-CaInJavaStore($keytool, $cacertsPath) {
    <# 用**退出码**判断别名在不在: keytool -list -alias 存在返回 0, 不存在返回 1。 #>
    $r = Invoke-Keytool $keytool @('-list', '-keystore', $cacertsPath,
                                  '-storepass', 'changeit', '-alias', $JavaAlias)
    return ($r[0] -eq 0)
}

function Get-JavaStoreState {
    <# 读「哪些 cacerts 已经导过了」的记录（按 CA 指纹 + 文件 mtime/大小 判定）。 #>
    $f = Join-Path $Root 'java-store-state.json'
    if (-not (Test-Path $f)) { return @{} }
    try {
        $d = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $out = @{}
        foreach ($p in $d.PSObject.Properties) {
            $out[$p.Name] = @{ thumb = $p.Value.thumb
                               mtime = $p.Value.mtime
                               size  = $p.Value.size }
        }
        return $out
    } catch { return @{} }
}

function Save-JavaStoreState($map) {
    $f = Join-Path $Root 'java-store-state.json'
    try {
        Write-TextNoBom $f ($map | ConvertTo-Json -Depth 4)
    } catch { }
}

function Sync-JavaTrustStores($ca, $remove = $false) {
    <#
      把我们的 CA 导入 / 移出所有 JRE 的 cacerts。返回 (成功数, 总数, 明细)。
      每个 cacerts 改动前会备份一份 .bsk-backup（只备一次, 不覆盖）。
    #>
    $stores = Get-JavaTrustStores
    if (-not $stores) {
        Info '没找到任何 Java 信任库（没装 Java？那就不需要这一步）'
        return @(0, 0, @())
    }

    # ★ 路径要自己从 $CertDir 推 —— $caCer 是 Ensure-Certs 里的**局部变量**,
    #   在这儿取不到（实测拿到空串, Copy-Item 报"参数是空值"）。
    $caCer = Join-Path $CertDir 'BSK-CA.cer'
    $caThumb = if ($ca) { [string]$ca.Thumbprint } else { '' }
    $jsDone = Get-JavaStoreState

    # ★ 再把 CA 复制到**纯 ASCII 的临时路径**喂给 keytool。
    #   证书本来在 `E:\DESKTOP\新建文件夹\...` —— 中文路径传给原生
    #   keytool.exe 时会按代码页转换, 转坏了它就把后面的参数当成"非法选项",
    #   报一堆看不懂的错。实测就是这么失败的。
    #   %TEMP% 通常是 `C:\Users\<名>\AppData\Local\Temp`, 用户名也可能是中文,
    #   所以再加一层检查。
    $asciiCer = Join-Path $env:TEMP 'bsk-hypixel-ca.cer'
    if ($asciiCer -match '[^\x00-\x7F]') {
        $asciiCer = Join-Path 'C:\Windows\Temp' 'bsk-hypixel-ca.cer'
    }
    try {
        Copy-Item $caCer $asciiCer -Force
    } catch {
        Info "证书复制到临时路径失败: $($_.Exception.Message)"
        return @(0, $stores.Count, @('★ 无法准备证书文件'))
    }

    $done = 0
    $skipped = 0
    $detail = @()
    $i = 0
    foreach ($cacerts in $stores) {
        $i++
        $short = $cacerts -replace [regex]::Escape($env:USERPROFILE), '~'

        # ★ 快速跳过已处理过的: 每次检查/导入都要起一个 JVM（约 0.5~1 秒）,
        #   30 个信任库就是半分钟。用 (CA 指纹 + 文件 mtime + 大小) 做标记,
        #   三者都没变就说明上次导过了, 直接跳过 —— 不碰 keytool。
        if (-not $remove) {
            $mark = $jsDone[$cacerts]
            if ($mark -and $mark.thumb -eq $caThumb) {
                try {
                    $fi = Get-Item $cacerts -ErrorAction Stop
                    if ([string]$fi.LastWriteTimeUtc.Ticks -eq $mark.mtime -and
                        [string]$fi.Length -eq $mark.size) {
                        $done++
                        $skipped++
                        continue
                    }
                } catch { }
            }
        }

        Write-Progress -Activity '安装证书到 Java 信任库' `
                       -Status "$i / $($stores.Count)  $short" `
                       -PercentComplete ([int](100 * $i / [Math]::Max(1, $stores.Count)))

        $kt = Get-KeytoolFor $cacerts
        if (-not $kt) {
            $detail += "跳过（找不到 keytool）: $short"
            continue
        }
        $exists = Test-CaInJavaStore $kt $cacerts

        if ($remove) {
            if (-not $exists) { $detail += "无需移除: $short"; continue }
            $r = Invoke-Keytool $kt @('-delete', '-alias', $JavaAlias,
                                      '-keystore', $cacerts, '-storepass', 'changeit')
            if ($r[0] -eq 0) { $done++; $detail += "已移除: $short" }
            else { $detail += "★ 移除失败: $short  $($r[1].Trim())" }
            continue
        }

        if ($exists) {
            $done++
            try {
                $fi = Get-Item $cacerts -ErrorAction Stop
                $jsDone[$cacerts] = @{ thumb = $caThumb
                                       mtime = [string]$fi.LastWriteTimeUtc.Ticks
                                       size  = [string]$fi.Length }
            } catch { }
            continue
        }

        # 备份（只备一次 —— 别把改动前的状态覆盖掉）
        $bak = "$cacerts.bsk-backup"
        if (-not (Test-Path $bak)) {
            try { Copy-Item $cacerts $bak -Force } catch { }
        }

        $r = Invoke-Keytool $kt @('-importcert', '-noprompt', '-trustcacerts',
                                  '-alias', $JavaAlias, '-file', $asciiCer,
                                  '-keystore', $cacerts, '-storepass', 'changeit')
        if ($r[0] -eq 0) {
            $done++
            $detail += "已导入: $short"
            try {
                $fi = Get-Item $cacerts -ErrorAction Stop
                $jsDone[$cacerts] = @{ thumb = $caThumb
                                       mtime = [string]$fi.LastWriteTimeUtc.Ticks
                                       size  = [string]$fi.Length }
            } catch { }
        } else {
            $detail += "★ 导入失败: $short  $($r[1].Trim())"
        }
    }
    Write-Progress -Activity '安装证书到 Java 信任库' -Completed
    Save-JavaStoreState $jsDone | Out-Null
    if ($skipped -gt 0) { $detail += "（其中 $skipped 个上次已处理过, 直接跳过）" }
    return @($done, $stores.Count, $detail)
}

# ---- 配置 ------------------------------------------------------------------

function Ensure-Config($leafPfx) {
    $cfg = @{
        proxyBase  = 'https://hyp-api.firebounce.today'
        apiKey     = ''
        forceKey   = $true
        listenHost = '127.0.0.1'
        listenPort = 443
        pfX        = $leafPfx
        pfxPass    = $PfxPass
        serverName = $TARGET_HOST
        logFile    = $LogFile
        # ★ pidFile 必须写进去 —— 代理靠它把 PID 报给上层（见 proxy.js 的
        #   writePid）。漏了不会报错, 但「恢复」就得靠命令行扫描兜底,
        #   属于静默失效。实测漏过一次。
        pidFile    = $PidFile
    }

    if (Test-Path $CfgPath) {
        try {
            # ★ 必须 -Encoding UTF8。配置是我们自己按 UTF-8 写的, 而
            #   Windows PowerShell 的 Get-Content 默认按 ANSI(GBK) 读 ——
            #   路径里的中文会先变乱码、再被原样写回去, 于是 logFile/pidFile
            #   指向一个不存在的目录: 日志永远不更新、PID 文件也生不出来。
            #   **这个坑实测炸过**（用户目录叫「新建文件夹」）。
            $old = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @('proxyBase', 'apiKey', 'forceKey', 'listenPort',
                             'logFile', 'pidFile')) {
                if ($null -ne $old.$k -and "$($old.$k)" -ne '') { $cfg[$k] = $old.$k }
            }
        } catch { Warn 'config.json 读不动，用默认值重建' }
    }

    # 没填 Key 就问 —— 不填的话代理能起，但请求会 401，用户会一头雾水
    #
    # ★ 必须校验格式。实测用户把终端里的整行（`PS E:\...> git clone ...`）
    #   粘进了输入框 —— 那种"Key"当然用不了，但脚本如果不拦就会存进配置，
    #   用户之后只会看到一堆 401，完全想不到是自己粘错了。
    $needAsk = -not $cfg.apiKey
    if ($cfg.apiKey -and -not (Test-ApiKey $cfg.apiKey)) {
        Warn "config.json 里那个 Key 不像是对的（必须是 bsk_ 开头的一串字符）"
        $needAsk = $true
    }

    while ($needAsk) {
        Write-Host ''
        Write-Host '  ------------------------------------------------------------' -ForegroundColor Yellow
        Write-Host '  需要一个 bsk_ 开头的 API Key 才能用反代。' -ForegroundColor Yellow
        Write-Host '  没有的话：QQ 群 519594836 里发  /apikey 你的QQ号  申请。' -ForegroundColor Yellow
        Write-Host '  只粘贴 Key 本身（形如 bsk_1a2b3c…），别把整行命令粘进来。' -ForegroundColor Yellow
        Write-Host '  ------------------------------------------------------------' -ForegroundColor Yellow
        Write-Host ''
        $k = (Read-Host '  请粘贴你的 API Key（直接回车 = 先跳过）').Trim()
        if (-not $k) {
            Warn '没填 Key —— 拦截会生效，但请求会返回 401'
            $cfg.apiKey = ''
            break
        }
        if (Test-ApiKey $k) {
            $cfg.apiKey = $k
            Ok ('Key 已记录: ' + $k.Substring(0, [Math]::Min(10, $k.Length)) + '…')
            break
        }
        Bad '这看起来不是 Key。应该只有 bsk_ 加一串字母数字，没有空格、没有其它符号。'
        Bad ('你输入的是: ' + $k.Substring(0, [Math]::Min(60, $k.Length)))
        # 循环再问一次 —— 不把明显错误的东西写进配置
    }

    $cfg.pfX = [string]$leafPfx
    Write-TextNoBom $CfgPath ($cfg | ConvertTo-Json -Depth 5)
    Ok "配置已写入: $CfgPath"
    return $cfg
}

function Test-ApiKey($k) {
    <# bsk_ 后面跟一串字母数字。宽松一点没关系，主要是挡住"粘错整行"这种。 #>
    return [bool]($k -match '^bsk_[0-9A-Za-z]{8,}$')
}

# ---- 代理进程 --------------------------------------------------------------

function Get-ProxyProcess {
    <#
      PID 文件是**代理自己写**的（见 proxy.js 的 writePid）。

      但光看 PID 不够 —— PID 会被系统回收, 文件也可能过期。所以还要核
      **命令行里有没有 proxy.js**: 否则可能杀掉一个碰巧拿到同一个 PID 的
      无关 node 进程。
    #>
    if (-not (Test-Path $PidFile)) { return $null }
    $p = (Get-Content $PidFile -Raw -ErrorAction SilentlyContinue)
    if (-not $p) { return $null }
    $pidNum = 0
    if (-not [int]::TryParse($p.Trim(), [ref]$pidNum)) { return $null }

    $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
    if (-not $proc -or $proc.ProcessName -ne 'node') { return $null }

    $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$pidNum" -ErrorAction SilentlyContinue
    if ($ci -and $ci.CommandLine -and $ci.CommandLine -like '*proxy.js*') { return $proc }
    return $null
}

function Get-StrayProxies {
    <# 按命令行找残留的 proxy.js 进程 —— PID 文件丢了也能清干净。 #>
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*proxy.js*' }
}

function Stop-Proxy {
    $stopped = $false

    $proc = Get-ProxyProcess
    if ($proc) {
        Info "停掉代理进程 (PID $($proc.Id))…"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        $stopped = $true
    }

    # 不管 PID 文件在不在, 都再按命令行扫一遍 —— 保证「恢复」真的干净。
    # (窗口被直接关掉、或代理异常退出时, 光靠 PID 文件会漏。)
    Start-Sleep -Milliseconds 300
    $stray = Get-StrayProxies
    if ($stray) {
        foreach ($s in $stray) {
            Info "清理残留代理进程 (PID $($s.ProcessId))…"
            Stop-Process -Id $s.ProcessId -Force -ErrorAction SilentlyContinue
            $stopped = $true
        }
    }

    if ($stopped) { Ok '代理已停止' } else { Info '没有正在跑的代理' }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

function Test-Port443Busy {
    $c = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    return [bool]$c
}

function Start-Proxy {
    if ($NoStart) { Info '（-NoStart：不启动代理）'; return }

    if (Test-Port443Busy) {
        $owner = (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue |
                  Select-Object -First 1).OwningProcess
        $name = (Get-Process -Id $owner -ErrorAction SilentlyContinue).ProcessName
        Warn "本机 443 端口已被占用（PID $owner / $name）—— 代理起不来"
        Info '如果是上次残留的 node，先跑一次「恢复」再试。'
        return
    }

    $node = (Get-Command node -ErrorAction SilentlyContinue)
    if (-not $node) {
        Bad '找不到 node —— 需要 Node.js 18 或更高版本'
        Info '装一个: https://nodejs.org/  （或者 winget install OpenJS.NodeJS.LTS）'
        exit 1
    }

    Info '启动本地反代（会新开一个窗口，别关它）…'
    $scriptPath = Join-Path $Root 'proxy.js'
    # ★ 经 `cmd /c chcp 65001` 拉起: Node 往控制台写的是 UTF-8, 而中文 Windows
    #   默认代码页是 GBK —— 不切的话代理窗口里所有中文都是乱码, 用户等于看不见日志。
    #   PID 由代理**自己**写文件（见 proxy.js 的 writePid）, 所以这里
    #   Start-Process 拿到的是 cmd 的 PID 也无所谓, 不会杀错/杀漏。
    $inner = 'chcp 65001 >nul && "' + $node.Source + '" "' + $scriptPath + '" "' + $CfgPath + '"'
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $inner) `
                          -WorkingDirectory $Root -PassThru
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue

    # 等它真的监听上再宣布成功 —— 不等的话会给用户"起来了"的假象
    for ($i = 0; $i -lt 48; $i++) {
        Start-Sleep -Milliseconds 250
        if (Test-Port443Busy) {
            $ownerPid = (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue |
                         Select-Object -First 1).OwningProcess
            Ok "代理已监听 127.0.0.1:443 (PID $ownerPid)"
            return
        }
        if ($proc.HasExited) { break }
    }

    # ---- 失败: 把**真正的原因**摆出来 ----
    #
    # ★ 以前这里只说"没监听上" + "常见原因: 端口被占/证书没生成好/Node 太老"，
    #   用户还得自己去翻日志才知道到底怎么回事（实测就是这么被卡住的）。
    #   现在直接把日志尾巴抄出来, 外加几个能自动判定的检查项。
    Bad '代理启动失败'
    Write-Host ''

    Write-Host '  自动检查:' -ForegroundColor Yellow

    # 证书文件在不在
    $c = $null
    if (Test-Path $CfgPath) {
        try { $c = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if ($c) {
        $pfxIsString = ($c.pfX -is [string])
        Write-Host ("    config.pfX 类型 : " + $(if ($pfxIsString) { '字符串 (正常)' } else { '★ ' + $c.pfX.GetType().Name + ' —— 配置写坏了, 删掉 config.json 重新来' }))
        if ($pfxIsString) {
            Write-Host ("    证书文件存在    : " + $(if (Test-Path $c.pfX) { '是' } else { '★ 否' }))
        }
        Write-Host ("    Key 格式        : " + $(if (Test-ApiKey $c.apiKey) { '正常' } else { '★ 不对 (应形如 bsk_xxxx)' }))
    }
    Write-Host ("    node 版本       : " + (& $node.Source --version 2>&1))
    $busy = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue
    Write-Host ("    443 端口        : " + $(if ($busy) { '被占 (PID ' + $busy[0].OwningProcess + ')' } else { '空闲' }))

    if (Test-Path $LogFile) {
        Write-Host ''
        Write-Host '  日志最后几行（通常直接写着原因）:' -ForegroundColor Yellow
        Get-Content $LogFile -Encoding UTF8 -Tail 8 -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    } else {
        Write-Host ''
        Warn "代理没写出日志（$LogFile）—— 说明它连启动都没走到"
    }
    Write-Host ''
    Info '改完再跑一次「拦截」即可；配置坏了就删掉 config.json 让它重建。'
}

# ---- 三个动作 --------------------------------------------------------------

function Do-拦截 {
    Invoke-SelfElevate

    Step '1/5 检查环境'
    Info "hosts: $HOSTS"
    if (-not (Test-Path $HOSTS)) { Bad "找不到 hosts 文件: $HOSTS"; exit 1 }
    Ok 'hosts 可读'

    # 上次残留先清掉，免得越积越多
    $resid = Get-OurHostsLines
    if ($resid.Count -gt 0) {
        Warn "发现上次残留的 $($resid.Count) 行，先清掉"
        $null = Remove-OurHostsLines
    }

    Step '2/5 准备证书'
    $leafPfx = Ensure-Certs

    Step '3/5 写配置'
    $cfg = Ensure-Config $leafPfx

    Step '4/6 导入 Java 信任库'
    #
    # ★ 光装进 Windows 根库是不够的 —— Java 用自己的 cacerts, 不看系统库。
    #   不导这一步, Minecraft 里所有打 api.hypixel.net 的 mod 都会报
    #   "PKIX path building failed"。这是"拦截装好了但游戏还是挂"的头号原因。
    if ($NoJava) {
        Info '（-NoJava：跳过。Java 程序会不信任我们的证书）'
    } else {
        $caCert = Get-ExistingCert $CaSubject
        $r = Sync-JavaTrustStores $caCert
        Info "JRE 信任库: $($r[0])/$($r[1]) 个已处理"
        foreach ($d in $r[2]) { Write-Host "    $d" -ForegroundColor DarkGray }
        if ($r[1] -gt 0 -and $r[0] -lt $r[1]) {
            Warn '有 JRE 没导成功 —— 那些 JRE 里的 Java 程序仍会报证书错误'
        }
    }

    Step '5/6 改 hosts'
    $bak = Backup-Hosts
    $lines = @(Get-Content -LiteralPath $HOSTS -ErrorAction SilentlyContinue)
    $lines += ''
    # ★ 注释行**故意用纯 ASCII**: hosts 文件会被各种工具按不同代码页读写,
    #   写中文进去迟早被搞成乱码。匹配也是靠 $MARK 这段 ASCII 前缀, 稳。
    $lines += "$MARK added by bsk-proxy.ps1 - run the restore script to remove"
    $lines += "127.0.0.1`t$TARGET_HOST"
    Write-TextNoBom $HOSTS ($lines -join "`r`n")
    Ok "$TARGET_HOST -> 127.0.0.1"
    Clear-DnsCache

    Step '6/6 启动代理'
    Start-Proxy

    Write-Host ''
    Write-Host '----------------------------------------------------------------' -ForegroundColor Green
    Write-Host '  拦截已开启' -ForegroundColor Green
    Write-Host '----------------------------------------------------------------' -ForegroundColor Green
    Info "$TARGET_HOST 现在指向本机，由本地代理转发到反代"
    if (-not $cfg.apiKey) { Warn '还没填 Key —— 编辑 config.json 里的 apiKey 再重启代理' }
    Info "hosts 备份: $bak"
    Write-Host ''
    Info '★ 记得**重启 Minecraft**（Java 有 DNS 缓存, 不重启可能还在连旧地址）'
    Info '要还原就双击「恢复.cmd」（或 .\bsk-proxy.ps1 恢复）'
    Write-Host ''
}

function Do-恢复 {
    Invoke-SelfElevate

    Step '1/5 停掉代理'
    Stop-Proxy

    Step '2/5 还原 hosts'
    if (-not (Test-Path $HOSTS)) {
        Warn "找不到 hosts: $HOSTS"
    } else {
        # 优先按标记删 —— 这比"拿最新备份覆盖"更安全:
        # 用户在拦截期间可能自己改过 hosts, 覆盖会把他后面的改动吞掉。
        $n = Remove-OurHostsLines
        if ($n -gt 0) {
            Ok "已从 hosts 移除 $n 行"
        } else {
            Ok 'hosts 里没有我们加的行（已经是干净的）'
        }
    }
    Clear-DnsCache

    Step '3/5 检查 hosts'
    $left = Get-OurHostsLines
    if ($left.Count -eq 0) {
        Ok "$TARGET_HOST 已不再指向本机"
    } else {
        Warn "还剩 $($left.Count) 行没清掉，请手动检查 $HOSTS"
    }

    Step '4/5 移出 Java 信任库'
    if ($RemoveJava) {
        $r = Sync-JavaTrustStores $null -remove $true
        Ok "Java 信任库: 处理了 $($r[0])/$($r[1]) 个"
        foreach ($d in $r[2]) { Write-Host "    $d" -ForegroundColor DarkGray }
    } else {
        Info 'Java 信任库里**保留**着（下次拦截就不用再导一遍）'
        Info '想彻底移出: .\bsk-proxy.ps1 恢复 -RemoveJava'
    }

    Step '5/5 根证书'
    if ($RemoveCa) {
        $ca = Get-ExistingCert $CaSubject
        if ($ca) {
            try {
                Get-ChildItem 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Thumbprint -eq $ca.Thumbprint } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                Remove-Item "Cert:\CurrentUser\My\$($ca.Thumbprint)" -Force -ErrorAction SilentlyContinue
                Remove-Item "Cert:\CurrentUser\My\$((Get-ExistingCert $LeafSubject).Thumbprint)" -Force -ErrorAction SilentlyContinue
                Ok '根证书和叶子证书已删除'
            } catch { Warn "删证书时出错: $($_.Exception.Message)" }
        } else { Info '没找到我们的 CA' }
    } else {
        Info '根证书**保留**着（下次拦截就不用再装一遍）'
        Info '想彻底删掉: .\bsk-proxy.ps1 恢复 -RemoveCa'
    }

    Write-Host ''
    Write-Host '----------------------------------------------------------------' -ForegroundColor Green
    Write-Host '  已恢复原样' -ForegroundColor Green
    Write-Host '----------------------------------------------------------------' -ForegroundColor Green
    Info "$TARGET_HOST 已指回 Hypixel 官方"
    Write-Host ''
}

function Do-状态 {
    Write-Host ''
    Write-Host '  BSK Hypixel 本地反代 —— 当前状态' -ForegroundColor Cyan
    Write-Host '  ------------------------------------------------------------'

    # hosts
    $n = (Get-OurHostsLines).Count
    if ($n -gt 0) { Write-Host "  hosts    : 已拦截 ($TARGET_HOST -> 127.0.0.1)" -ForegroundColor Green }
    else          { Write-Host "  hosts    : 未拦截（走官方）" -ForegroundColor Gray }

    # 代理
    $proc = Get-ProxyProcess
    if ($proc) { Write-Host "  代理进程 : 运行中 (PID $($proc.Id))" -ForegroundColor Green }
    else       { Write-Host "  代理进程 : 没在跑" -ForegroundColor Gray }

    # 端口
    if (Test-Port443Busy) {
        $owner = (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue |
                  Select-Object -First 1).OwningProcess
        Write-Host "  443 端口 : 被 PID $owner 占用" -ForegroundColor Green
    } else {
        Write-Host "  443 端口 : 空闲" -ForegroundColor Gray
    }

    # 证书
    $ca = Get-ExistingCert $CaSubject
    if ($ca) {
        $trusted = Get-ChildItem 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue |
                   Where-Object { $_.Thumbprint -eq $ca.Thumbprint }
        $t = if ($trusted) { '已信任' } else { '未信任（会 TLS 报错！）' }
        Write-Host "  根证书   : $t  ($($ca.Thumbprint.Substring(0,8))…)" -ForegroundColor $(if ($trusted) { 'Green' } else { 'Yellow' })
    } else {
        Write-Host "  根证书   : 还没生成" -ForegroundColor Gray
    }

    # 配置
    if (Test-Path $CfgPath) {
        try {
            $c = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $k = if ($c.apiKey) { $c.apiKey.Substring(0, [Math]::Min(10, $c.apiKey.Length)) + '…' } else { '(没填)' }
            Write-Host "  转发到   : $($c.proxyBase)"
            Write-Host "  Key      : $k"
        } catch { Write-Host "  配置     : 读不动 config.json" -ForegroundColor Yellow }
    } else {
        Write-Host "  配置     : 还没生成" -ForegroundColor Gray
    }

    # 最近日志
    if (Test-Path $LogFile) {
        Write-Host ''
        Write-Host '  最近日志:'
        # ★ 必须显式 -Encoding UTF8: 日志是 Node 按 UTF-8 写的, 而
        #   Windows PowerShell 的 Get-Content 默认按 ANSI(GBK) 读 ——
        #   不加这个参数中文全是乱码, 日志等于白看。
        Get-Content $LogFile -Encoding UTF8 -Tail 6 -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
    Write-Host ''
}

# ---- 分发 ------------------------------------------------------------------

switch ($Action) {
    { $_ -in '拦截', 'install' } { Do-拦截 }
    { $_ -in '恢复', 'restore' } { Do-恢复 }
    default                      { Do-状态 }
}
