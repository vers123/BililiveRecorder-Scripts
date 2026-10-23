# 停止 BililiveRecorder（Windows / PowerShell 版）
# 默认模拟 Ctrl+C 优雅退出，超时或失败才强制结束

function Show-Usage {
  Write-Host '用法：.\stop.ps1 [-f]'
  Write-Host '  -f, --force  直接强制结束（可能损坏未收尾的录制文件）'
}

# 在独立子进程中向目标控制台发送 CTRL_C_EVENT
function Send-CtrlC {
  param([int]$TargetPid)

  $helperCode = @'
param([int]$TargetPid)

$source = @"
using System;
using System.Runtime.InteropServices;

public static class BrecConsole
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FreeConsole();

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool AttachConsole(uint dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GenerateConsoleCtrlEvent(uint dwCtrlEvent, uint dwProcessGroupId);
}
"@

Add-Type -TypeDefinition $source

[BrecConsole]::FreeConsole() | Out-Null
if (-not [BrecConsole]::AttachConsole([uint32]$TargetPid)) { exit 2 }
[BrecConsole]::GenerateConsoleCtrlEvent(0, 0) | Out-Null
Start-Sleep -Milliseconds 800
[BrecConsole]::FreeConsole() | Out-Null
exit 0
'@

  $helper = Join-Path ([System.IO.Path]::GetTempPath()) ('brec-ctrlc-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
  Set-Content -LiteralPath $helper -Value $helperCode -Encoding Ascii

  $exe = 'powershell'
  if (Get-Command pwsh -ErrorAction SilentlyContinue) { $exe = 'pwsh' }

  try {
    $hp = Start-Process -FilePath $exe `
      -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $helper), '-TargetPid', $TargetPid) `
      -WindowStyle Hidden -Wait -PassThru
    # 发送 Ctrl+C 后，helper 自己也会收到该信号并以 STATUS_CONTROL_C_EXIT
    # （0xC000013A / 十进制 3221225786）结束，这也算成功
    if ($hp.ExitCode -eq 0) { return $true }
    if ($hp.ExitCode -eq 3221225786) { return $true }
    if ($hp.ExitCode -eq -1073741510) { return $true }
    return $false
  }
  finally {
    Remove-Item -LiteralPath $helper -Force -ErrorAction SilentlyContinue
  }
}

$force = $false
foreach ($a in $args) {
  switch -Regex ([string]$a) {
    '^(?i)(-f|--force)$'     { $force = $true; continue }
    '^(?i)(-h|--help|help)$' { Show-Usage; exit 0 }
    default                  { Write-Host "未知参数：$a"; Show-Usage; exit 1 }
  }
}

. (Join-Path $PSScriptRoot 'common.ps1')

$procId = Get-RecorderPid
if (-not $procId) {
  Write-Host '没有在运行的 BililiveRecorder'
  Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
  exit 0
}

Write-Host "正在停止 PID=$procId ..."

if ($force) {
  Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
}
else {
  if (-not (Send-CtrlC -TargetPid $procId)) {
    Write-Host '发送 Ctrl+C 失败，将等待超时后强制结束'
  }

  for ($i = 1; $i -le $StopTimeout; $i++) {
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Seconds 1
    if (($i % 5) -eq 0) {
      Write-Host "  仍在退出中（${i}s）..."
    }
  }

  if (Get-Process -Id $procId -ErrorAction SilentlyContinue) {
    Write-Host "进程 ${StopTimeout}s 内未退出，强制结束（可能影响未收尾的录制）"
    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
  }
}

Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue

if (Get-Process -Id $procId -ErrorAction SilentlyContinue) {
  Write-Host "停止失败，请手动检查 PID=$procId"
  exit 1
}

Write-Host '已停止'
