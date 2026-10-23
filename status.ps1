# 查看 BililiveRecorder 状态（Windows / PowerShell 版）

. (Join-Path $PSScriptRoot 'common.ps1')

$procId = Get-RecorderPid

Write-Host '==================== BililiveRecorder 状态 ===================='
if ($procId) {
  Write-Host '运行状态 : 正在运行 ✅'
  Write-Host "PID      : $procId"
  $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
  if ($p) {
    $cpu = 0
    try { if ($p.CPU) { $cpu = [math]::Round($p.CPU, 1) } } catch { }
    $memMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
    $startText = '未知'
    try { $startText = $p.StartTime.ToString('yyyy-MM-dd HH:mm:ss') } catch { }
    Write-Host ("  {0}({1})  CPU={2}s  内存={3}MB  启动={4}" -f $p.ProcessName, $procId, $cpu, $memMB, $startText)
  }
}
else {
  Write-Host '运行状态 : 未运行 ❌'
}

Write-Host '--------------------------------------------------------------'
Write-Host "平台     : $(Get-PlatformTag)"
try {
  $bin = Resolve-BrecBin
  Write-Host "程序本体 : $($bin.Display)"
}
catch {
  Write-Host '程序本体 : 未找到（把 BililiveRecorder-CLI-win-x64 解压到本目录）'
}
Write-Host "监听地址 : $Bind"
Write-Host "工作目录 : $WorkDir"
Write-Host "日志文件 : $Log"
Write-Host "错误日志 : $LogErr"
Write-Host "PID 文件 : $PidFile"
Write-Host '--------------------------------------------------------------'

$code = Get-HttpCode
switch ($code) {
  '000' { Write-Host 'HTTP 检测: 无法访问 ❌' }
  ''    { Write-Host 'HTTP 检测: 无法访问 ❌' }
  default { Write-Host "HTTP 检测: 可访问（HTTP $code）✅" }
}

Write-Host '--------------------------------------------------------------'
if (Test-Path -LiteralPath $WorkDir -PathType Container) {
  $sum = (Get-ChildItem -LiteralPath $WorkDir -Recurse -File -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
  if (-not $sum) { $sum = 0 }
  Write-Host "录制占用 : $(Format-Size ([double]$sum))"
}

$rootPath = [System.IO.Path]::GetPathRoot($WorkDir)
if ($rootPath) {
  $deviceId = $rootPath.TrimEnd('\')
  try {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $deviceId) -ErrorAction Stop
    if ($disk -and $disk.Size -gt 0) {
      $usedPct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100)
      Write-Host ("磁盘剩余 : {0} 可用 / {1}（已用 {2}%）" -f (Format-Size $disk.FreeSpace), (Format-Size $disk.Size), $usedPct)
    }
  }
  catch { }
}

Write-Host '--------------------------------------------------------------'
if (Test-Path -LiteralPath $Log -PathType Leaf) {
  Write-Host "最近 10 行日志（$Log）："
  Write-LogTail -Path $Log -Lines 10
}
else {
  Write-Host "日志文件不存在：$Log"
}
Write-Host '=============================================================='

if ($procId) { exit 0 } else { exit 1 }
