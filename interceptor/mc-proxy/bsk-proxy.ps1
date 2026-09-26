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
    [switch]$RemoveCa
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
    if ($RemoveCa) { $a += '-RemoveCa' }
    if ($NoStart)  { $a += '-NoStart' }
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
    if (-not $ca) {
        Info '生成本地根证书 (CA)…'
        $ca = New-SelfSignedCertificate `
            -Subject $CaSubject `
            -KeyUsage CertSign, CRLSign, DigitalSignature `
            -KeyExportPolicy Exportable `
            -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256 `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -NotAfter (Get-Date).AddYears(10)
        Ok ("CA 已生成: " + $ca.Thumbprint)
    } else {
        Ok ("复用已有 CA: " + $ca.Thumbprint)
    }

    # 叶子证书：换过 CA 就得重签
    $leaf = Get-ExistingCert $LeafSubject
    $needLeaf = $true
    if ($leaf) {
        try {
            # 校验这张叶子是不是当前 CA 签的 —— CA 重建过就必须重签
            $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
            $chain.ChainPolicy.RevocationMode = 'NoCheck'
            $chain.ChainPolicy.VerificationFlags = 'AllowUnknownCertificateAuthority'
            # ★ 这一行的返回值必须吞掉 —— 它就是那个泄漏出 0 的元凶
            $null = $chain.ChainPolicy.ExtraStore.Add($ca)
            $null = $chain.Build($leaf)
            $issuerOk = ($chain.ChainElements.Count -gt 1)
            if ($issuerOk) {
                $needLeaf = $false
                Ok ("复用已有叶子证书: " + $leaf.Thumbprint)
            }
        } catch { $needLeaf = $true }
    }

    if ($needLeaf) {
        if ($leaf) {
            Info '叶子证书是旧 CA 签的，重新签一张…'
            Remove-Item "Cert:\CurrentUser\My\$($leaf.Thumbprint)" -Force -ErrorAction SilentlyContinue
        } else {
            Info "生成 $TARGET_HOST 的证书…"
        }
        $leaf = New-SelfSignedCertificate `
            -Subject $LeafSubject `
            -DnsName $TARGET_HOST `
            -KeyExportPolicy Exportable `
            -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256 `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -NotAfter (Get-Date).AddYears(5) `
            -Signer $ca
        Ok ("叶子证书已生成: " + $leaf.Thumbprint)
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
            Bad "装根证书失败: $($_.Exception.Message)"
            Info "也可以手动装: 双击 $caCer → 安装证书 → 本地计算机/当前用户 → 受信任的根证书颁发机构"
            exit 1
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

    Step '4/5 改 hosts'
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

    Step '5/5 启动代理'
    Start-Proxy

    Write-Host ''
    Write-Host '----------------------------------------------------------------' -ForegroundColor Green
    Write-Host '  拦截已开启' -ForegroundColor Green
    Write-Host '----------------------------------------------------------------' -ForegroundColor Green
    Info "$TARGET_HOST 现在指向本机，由本地代理转发到反代"
    if (-not $cfg.apiKey) { Warn '还没填 Key —— 编辑 config.json 里的 apiKey 再重启代理' }
    Info "hosts 备份: $bak"
    Write-Host ''
    Info '要还原就双击「恢复.cmd」（或 .\bsk-proxy.ps1 恢复）'
    Write-Host ''
}

function Do-恢复 {
    Invoke-SelfElevate

    Step '1/4 停掉代理'
    Stop-Proxy

    Step '2/4 还原 hosts'
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

    Step '3/4 检查结果'
    $left = Get-OurHostsLines
    if ($left.Count -eq 0) {
        Ok "$TARGET_HOST 已不再指向本机"
    } else {
        Warn "还剩 $($left.Count) 行没清掉，请手动检查 $HOSTS"
    }

    Step '4/4 根证书'
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
