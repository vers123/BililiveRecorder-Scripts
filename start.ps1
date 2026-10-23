# 启动 BililiveRecorder（Windows / PowerShell 版）
# 用法：.\start.ps1 [-f | -b | -h]

function Show-Usage {
  Write-Host "用法：.\start.ps1 [-f|-b] [-h]"
  Write-Host ''
  Write-Host '  -f, --foreground  前台运行（Ctrl+C 停止）'
  Write-Host '  -b, --background  后台运行（日志：logs\recorder.log）'
  Write-Host '  -h, --help        显示帮助'
  Write-Host ''
  Write-Host '不带参数时交互式选择。'
}

$mode = ''
foreach ($a in $args) {
  switch -Regex ([string]$a) {
    '^(?i)(-b|--background|bg)$' { $mode = 'bg'; continue }
    '^(?i)(-f|--foreground|fg)$' { $mode = 'fg'; continue }
    '^(?i)(-h|--help|help)$'     { Show-Usage; exit 0 }
    default                      { Write-Host "未知参数：$a"; Show-Usage; exit 1 }
  }
}

if ([string]::IsNullOrEmpty($mode)) {
  Write-Host '请选择运行方式：'
  Write-Host '  1) 前台运行（Ctrl+C 停止）'
  Write-Host '  2) 后台运行（日志写入 logs\recorder.log）'
  $choice = Read-Host '输入 1 或 2 [默认 1]'
  if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
  switch ($choice) {
    '1' { $mode = 'fg' }
    '2' { $mode = 'bg' }
    default { Write-Host "无效选择：$choice"; exit 1 }
  }
}

. (Join-Path $PSScriptRoot 'common.ps1')

try {
  $bin = Resolve-BrecBin
}
catch {
  Write-Host $_.Exception.Message
  exit 1
}

# 已在运行则直接退出（PID 文件或进程扫描命中都算）
$runningPid = Get-RecorderPid
if ($runningPid) {
  Write-Host "已经在运行，PID=$runningPid"
  [System.IO.File]::WriteAllText($PidFile, [string]$runningPid)
  exit 0
}

$launcher = $bin.Cmd[0]
$launcherArgs = @()
if ($bin.Cmd.Count -gt 1) {
  $launcherArgs = @($bin.Cmd[1..($bin.Cmd.Count - 1)])
}

# 启动前处理 cookie（自动写入 config.json 或提示手动填写）
Invoke-CookieSetup

if ($mode -eq 'fg') {
  Write-Host '>>> 前台运行中，按 Ctrl+C 停止'
  & $launcher @launcherArgs run --bind $Bind $WorkDir
  exit $LASTEXITCODE
}

# 后台模式：独占打开锁文件防止并发双开
$lockStream = $null
try {
  $lockStream = [System.IO.File]::Open(
    $LockFile,
    [System.IO.FileMode]::OpenOrCreate,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
  )
}
catch {
  Write-Host '另一个 start.ps1 正在执行，请稍后重试'
  exit 1
}

# 拿到锁后再查一次，避免竞态
$runningPid = Get-RecorderPid
if ($runningPid) {
  Write-Host "已经在运行，PID=$runningPid"
  $lockStream.Dispose()
  exit 0
}

Rotate-Log
Write-Host ">>> 后台运行中，日志：$Log"

# Start-Process 不会自动为参数加引号，这里手工加引号以兼容含空格的路径
$argParts = @()
if ($bin.Cmd.Count -gt 1) {
  $argParts += ('"{0}"' -f $bin.Cmd[1])
}
$argParts += @('run', '--bind', ('"{0}"' -f $Bind), ('"{0}"' -f $WorkDir))
$argString = $argParts -join ' '

$process = Start-Process -FilePath $launcher `
  -ArgumentList $argString `
  -RedirectStandardOutput $Log `
  -RedirectStandardError $LogErr `
  -PassThru -WindowStyle Hidden

[System.IO.File]::WriteAllText($PidFile, [string]$process.Id)

# 最多等 10 秒：进程存活且 HTTP 就绪
$ready = $false
for ($i = 0; $i -lt 10; $i++) {
  if ($process.HasExited) { break }
  $code = Get-HttpCode
  if ($code -and $code -ne '000') {
    $ready = $true
    break
  }
  Start-Sleep -Seconds 1
}

$lockStream.Dispose()

if ($process.HasExited) {
  Write-Host '启动失败（进程已退出），最近日志：'
  Write-Host "[stdout] $Log"
  Write-LogTail -Path $Log -Lines 20
  Write-Host "[stderr] $LogErr"
  Write-LogTail -Path $LogErr -Lines 20
  Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
  exit 1
}

if ($ready) {
  Write-Host "PID=$($process.Id)，HTTP 已就绪，停止：.\stop.ps1"
}
else {
  Write-Host "PID=$($process.Id)，进程在运行但 HTTP 尚未响应（可能仍在初始化），日志：$Log"
}
