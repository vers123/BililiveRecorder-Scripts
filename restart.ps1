# 重启 BililiveRecorder（Windows / PowerShell 版，等价于 stop.ps1 + start.ps1 -b）

& (Join-Path $PSScriptRoot 'stop.ps1')
& (Join-Path $PSScriptRoot 'start.ps1') '-b'
exit $LASTEXITCODE
