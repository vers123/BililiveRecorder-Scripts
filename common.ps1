# 公共配置与函数，仅供 start/stop/status/restart 通过 dot-source 加载
# 不要直接执行本文件
# 编码要求：UTF-8 with BOM（兼容 Windows PowerShell 5.1 中文解析）

$RootDir = $PSScriptRoot
Set-Location -LiteralPath $RootDir

$Bind = 'http://localhost:2356'
$WorkDir = Join-Path $RootDir 'recordings'

$RunDir = Join-Path $RootDir 'run'
$LogDir = Join-Path $RootDir 'logs'
$PidFile = Join-Path $RunDir 'recorder.pid'
$LockFile = Join-Path $RunDir 'start.lock'
$Log = Join-Path $LogDir 'recorder.log'
$LogErr = Join-Path $LogDir 'recorder.err.log'

$CookieFile = Join-Path $RootDir 'cookie\bilibili.txt'
$ConfigPath = Join-Path $WorkDir 'config.json'

$LogMaxMB = 100        # 日志超过此大小，启动时自动轮转
$StopTimeout = 15      # 优雅停止最长等待秒数（录制收尾需要时间）

New-Item -ItemType Directory -Force -Path $RunDir, $LogDir | Out-Null

# 进程匹配模式：兼容原生 exe 与 dotnet any 版
$BinPattern = 'BililiveRecorder\.Cli(\.dll)?\s+run'

function Get-PlatformTag {
  $os = 'unknown'
  if ($PSVersionTable.PSVersion.Major -ge 6) {
    if ($IsWindows) { $os = 'windows' }
    elseif ($IsMacOS) { $os = 'osx' }
    else { $os = 'linux' }
  }
  elseif ($env:OS -eq 'Windows_NT') {
    $os = 'windows'
  }

  $arch = 'unknown'
  switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { $arch = 'x64' }
    'ARM64' { $arch = 'arm64' }
    'x86'   { $arch = 'x86' }
  }
  return ('{0}/{1}' -f $os, $arch)
}

function Get-BinScore {
  param([string]$Name)
  if ($Name -like '*win-*') { return 100 }
  if ($Name -like '*any*')  { return 10 }
  return 0
}

# 自动探测程序本体；可用 BREC_BIN 显式指定 exe 或 dll
function Resolve-BrecBin {
  $override = $env:BREC_BIN
  if ($override) {
    if (-not (Test-Path -LiteralPath $override -PathType Leaf)) {
      throw "错误：BREC_BIN 指向的文件不存在：$override"
    }
    $full = (Resolve-Path -LiteralPath $override).Path
    if ([System.IO.Path]::GetExtension($full) -eq '.dll') {
      if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw '错误：BREC_BIN 指向 any 版 dll，但 PATH 中没有 dotnet'
      }
      return [pscustomobject]@{ Cmd = @('dotnet', $full); Display = $full; Kind = 'dotnet' }
    }
    return [pscustomobject]@{ Cmd = @($full); Display = $full; Kind = 'native' }
  }

  $dirs = @(Get-ChildItem -LiteralPath $RootDir -Directory -Filter 'BililiveRecorder-CLI-*' -ErrorAction SilentlyContinue)
  $best = $null
  $bestScore = -1

  foreach ($d in $dirs) {
    $score = Get-BinScore -Name $d.Name
    if ($score -le 0) { continue }

    $exe = Join-Path $d.FullName 'BililiveRecorder.Cli.exe'
    $dll = Join-Path $d.FullName 'BililiveRecorder.Cli.dll'

    if (Test-Path -LiteralPath $exe -PathType Leaf) {
      $cmd = @($exe)
      $kind = 'native'
    }
    elseif ((Test-Path -LiteralPath $dll -PathType Leaf) -and (Get-Command dotnet -ErrorAction SilentlyContinue)) {
      $cmd = @('dotnet', $dll)
      $kind = 'dotnet'
    }
    else {
      continue
    }

    if ($score -gt $bestScore) {
      $bestScore = $score
      $best = [pscustomobject]@{
        Cmd     = $cmd
        Display = $cmd[$cmd.Count - 1]
        Kind    = $kind
      }
    }
  }

  if (-not $best) {
    $msg = '错误：未找到可用的 BililiveRecorder 程序本体'
    if ($dirs.Count -gt 0) {
      $msg += "`n已找到的目录：`n" + (($dirs | ForEach-Object { '  ' + $_.Name }) -join "`n")
    }
    $msg += "`n请从 https://github.com/BililiveRecorder/BililiveRecorder/releases 下载 win-x64 压缩包，"
    $msg += "解压到本目录，目录名保持 BililiveRecorder-CLI-win-x64。"
    throw $msg
  }

  return $best
}

function Test-RecorderProcess {
  param([System.Diagnostics.Process]$Process)
  if (-not $Process) { return $false }
  if ($Process.ProcessName -eq 'BililiveRecorder.Cli') { return $true }
  if ($Process.ProcessName -eq 'dotnet') {
    try {
      $ci = Get-CimInstance Win32_Process -Filter ('ProcessId = {0}' -f $Process.Id) -ErrorAction Stop
      if ($ci -and $ci.CommandLine -and $ci.CommandLine -match $BinPattern) { return $true }
    }
    catch { }
  }
  return $false
}

# 统一获取 PID：PID 文件优先（并校验进程身份，避免 PID 复用误杀），进程列表兜底
function Get-RecorderPid {
  if (Test-Path -LiteralPath $PidFile -PathType Leaf) {
    $raw = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    $procId = 0
    if ($raw -and [int]::TryParse(([string]$raw).Trim(), [ref]$procId)) {
      $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
      if ($p -and (Test-RecorderProcess -Process $p)) { return $procId }
    }
  }

  try {
    $candidates = Get-CimInstance Win32_Process -Filter "Name = 'BililiveRecorder.Cli.exe' OR Name = 'dotnet.exe'" -ErrorAction Stop
    foreach ($c in $candidates) {
      if ($c.CommandLine -and $c.CommandLine -match $BinPattern) { return [int]$c.ProcessId }
    }
  }
  catch { }

  return $null
}

function Test-RecorderRunning {
  return [bool](Get-RecorderPid)
}

# 返回 HTTP 状态码字符串；连接失败返回 000
function Get-HttpCode {
  try {
    $response = Invoke-WebRequest -Uri $Bind -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    return [string][int]$response.StatusCode
  }
  catch {
    $resp = $_.Exception.Response
    if ($resp -and $resp.StatusCode) {
      return [string][int]$resp.StatusCode
    }
    return '000'
  }
}

function Rotate-Log {
  foreach ($file in @($Log, $LogErr)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    $item = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
    if (-not $item) { continue }
    if (($item.Length / 1MB) -ge $LogMaxMB) {
      $target = '{0}.{1}' -f $file, (Get-Date -Format 'yyyyMMdd-HHmmss')
      try { Move-Item -LiteralPath $file -Destination $target -Force -ErrorAction Stop }
      catch { }
    }
  }
}

function Write-LogTail {
  param(
    [string]$Path,
    [int]$Lines = 10
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }

  # 程序把控制台输出重定向到文件时使用系统 OEM 代码页（中文 Windows 为 936），
  # 直接用 UTF-8 读取会乱码，这里按 OEM 代码页解码
  $encoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
  $text = ''
  $stream = $null
  try {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $length = $stream.Length
    $take = [Math]::Min([long]$length, [long]65536)
    if ($take -le 0) { return }
    $stream.Seek($length - $take, [System.IO.SeekOrigin]::Begin) | Out-Null
    $buffer = New-Object byte[] ([int]$take)
    $read = $stream.Read($buffer, 0, [int]$take)
    $text = $encoding.GetString($buffer, 0, $read)
  }
  catch {
    return
  }
  finally {
    if ($stream) { $stream.Dispose() }
  }

  $text -split "`r?`n" | Select-Object -Last $Lines | ForEach-Object { '  ' + $_ }
}

function Format-Size {
  param([double]$Bytes)
  if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
  if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
  if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
  return ('{0:N0} B' -f $Bytes)
}

# ---------- Cookie 导入 ----------
# 只接受 Cookie Editor 的 Header String（即 Cookie 请求头原文）：
#   SESSDATA=xxx; bili_jct=yyy; buvid3=zzz

function Get-NormalizedCookie {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "cookie 文件不存在：$Path"
  }

  $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
  $text = $text.TrimStart([char]0xFEFF).Trim()

  if ([string]::IsNullOrWhiteSpace($text)) {
    throw "cookie 文件为空：$Path"
  }

  if ($text.StartsWith('[') -or $text.StartsWith('{')) {
    throw "检测到 JSON 格式；请在 Cookie Editor 中改选 Header String 导出后覆盖 $Path"
  }

  if ($text -match 'Netscape HTTP Cookie File') {
    throw "检测到 Netscape 格式；请在 Cookie Editor 中改选 Header String 导出后覆盖 $Path"
  }

  $lines = @($text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  foreach ($line in $lines) {
    if (($line -split "`t").Count -ge 7) {
      throw "检测到 Netscape 格式（制表符分隔）；请在 Cookie Editor 中改选 Header String 导出后覆盖 $Path"
    }
  }

  $cookie = $lines -join '; '
  $cookie = $cookie -replace '^(?i)Cookie:\s*', ''
  $cookie = (@($cookie -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) -join '; '

  if ($cookie -match '["\\]') {
    throw 'cookie 中不允许出现双引号或反斜杠'
  }

  if ($cookie -match '[\x00-\x1F]') {
    throw 'cookie 中包含控制字符（制表符或换行）'
  }

  if ($cookie -notmatch '(^|;\s*)[^=;\s]+=') {
    throw 'cookie 格式不正确：未找到 name=value'
  }

  return $cookie
}

function Set-ConfigCookie {
  param([string]$Cookie)

  $directory = Split-Path -Parent $ConfigPath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
  }

  $backup = $ConfigPath + '.bak'
  if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    Copy-Item -LiteralPath $ConfigPath -Destination $backup -Force
    $raw = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8)
    $cfg = $raw | ConvertFrom-Json
  }
  else {
    $cfg = [pscustomobject]@{
      version = 3
      global  = [pscustomobject]@{}
      rooms   = @()
    }
  }

  if (-not $cfg.PSObject.Properties['global'] -or $null -eq $cfg.global) {
    $cfg | Add-Member -NotePropertyName global -NotePropertyValue ([pscustomobject]@{}) -Force
  }

  $cookieValue = [pscustomobject]@{
    HasValue = $true
    Value    = $Cookie
  }
  $cfg.global | Add-Member -NotePropertyName Cookie -NotePropertyValue $cookieValue -Force

  $json = $cfg | ConvertTo-Json -Depth 100 -Compress
  [System.IO.File]::WriteAllText($ConfigPath, $json, (New-Object System.Text.UTF8Encoding($false)))

  $check = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  if ($null -eq $check.global -or $null -eq $check.global.Cookie -or $check.global.Cookie.Value -ne $Cookie) {
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
      Copy-Item -LiteralPath $backup -Destination $ConfigPath -Force
    }
    throw '写入 config.json 后校验失败，已还原备份'
  }
}

function Invoke-CookieSetup {
  if (-not (Test-Path -LiteralPath $CookieFile -PathType Leaf)) { return }

  $cookie = $null
  try {
    $cookie = Get-NormalizedCookie -Path $CookieFile
  }
  catch {
    Write-Host ('cookie 未导入：' + $_.Exception.Message)
    Write-Host ('可继续启动，稍后在 Web 界面手动填写：' + $Bind)
    return
  }

  $count = @($cookie -split ';' | Where-Object { $_.Trim() }).Count
  if ($cookie -match '(^|;\s*)SESSDATA=') { $sess = '包含 SESSDATA' } else { $sess = '未包含 SESSDATA' }

  Write-Host ("检测到 cookie：$CookieFile（{0} 项，{1}）" -f $count, $sess)

  $answer = '1'
  if (-not [Console]::IsInputRedirected) {
    Write-Host '  1) 自动写入 recordings\config.json（推荐）'
    Write-Host '  2) 我自己填写（启动后在 Web 界面设置）'
    $choice = Read-Host '选择 [1]'
    if (-not [string]::IsNullOrWhiteSpace($choice)) { $answer = $choice.Trim() }
  }
  else {
    Write-Host '非交互模式：自动写入 recordings\config.json'
  }

  switch ($answer) {
    '1' {
      try {
        Set-ConfigCookie -Cookie $cookie
        Write-Host "Cookie 已写入 $ConfigPath"
      }
      catch {
        Write-Host ('Cookie 写入失败：' + $_.Exception.Message)
        Write-Host ('请在 Web 界面手动填写：' + $Bind)
      }
    }
    '2' {
      Write-Host "已跳过自动填写。启动后访问 $Bind → 设置 → 全局 → Cookie 粘贴并保存。"
    }
    default {
      Write-Host "无效选择：$answer（将跳过自动填写）"
    }
  }
}
