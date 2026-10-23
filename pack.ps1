# 打包发布包（Windows / PowerShell 版，输出 zip）
# 用法：.\pack.ps1 [--public]

function Show-Usage {
  Write-Host '用法：.\pack.ps1 [--public]'
  Write-Host '  默认     打包为自用版（含 cookie）'
  Write-Host '  --public 打包为公开分发版（不含 cookie）'
}

$withCookie = $true
$suffix = 'selfuse'
foreach ($a in $args) {
  switch -Regex ([string]$a) {
    '^(?i)--public$'          { $withCookie = $false; $suffix = 'public'; continue }
    '^(?i)(-h|--help|help)$'  { Show-Usage; exit 0 }
    default                   { Write-Host "未知参数：$a"; exit 1 }
  }
}

$ErrorActionPreference = 'Stop'

$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$name = 'bilirec-kit-{0}-{1}.zip' -f (Get-Date -Format 'yyyy-MM-dd'), $suffix
$out = Join-Path $dist $name

$tmpBase = Join-Path ([System.IO.Path]::GetTempPath()) ('bilirec-pack-' + [guid]::NewGuid().ToString('N'))
$rootName = Split-Path $PSScriptRoot -Leaf
$stageRoot = Join-Path $tmpBase $rootName

$fail = 0
try {
  New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

  $excludeDirs = @('run', 'logs', 'dist', '.trae', '.git')
  Get-ChildItem -LiteralPath $PSScriptRoot -Force | ForEach-Object {
    $item = $_
    if ($item.Name -like 'BililiveRecorder-CLI-*') { return }
    if ($excludeDirs -contains $item.Name) { return }
    if ($item.Name -eq 'pack.ps1' -or $item.Name -eq 'pack.sh') { return }
    if (-not $withCookie -and $item.Name -eq 'cookie') { return }
    Copy-Item -LiteralPath $item.FullName -Destination $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  # 录制目录只保留配置文件，剔除视频与封面
  $stageRec = Join-Path $stageRoot 'recordings'
  if (Test-Path -LiteralPath $stageRec -PathType Container) {
    Get-ChildItem -LiteralPath $stageRec -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -in @('.flv', '.jpg') } |
      Remove-Item -Force -ErrorAction SilentlyContinue
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $out -PathType Leaf) {
    Remove-Item -LiteralPath $out -Force
  }
  [System.IO.Compression.ZipFile]::CreateFromDirectory(
    $tmpBase,
    $out,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
  )

  # ---- 校验 ----
  $zip = [System.IO.Compression.ZipFile]::OpenRead($out)
  try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
  }
  finally {
    $zip.Dispose()
  }

  if (@($names | Where-Object { $_ -match '\.(flv|jpg)$' }).Count -gt 0) {
    Write-Host '❌ 混入视频'; $fail = 1
  }
  if (@($names | Where-Object { $_ -match '/(run|logs|dist)/' }).Count -gt 0) {
    Write-Host '❌ 混入 run/logs/dist'; $fail = 1
  }
  if (@($names | Where-Object { $_ -match 'BililiveRecorder-CLI-[^/]+/' }).Count -gt 0) {
    Write-Host '❌ 混入程序本体'; $fail = 1
  }
  if (@($names | Where-Object { $_ -match '/pack\.(sh|ps1)$' }).Count -gt 0) {
    Write-Host '❌ 混入打包脚本'; $fail = 1
  }
  if (-not $withCookie -and @($names | Where-Object { $_ -match '(^|/)cookie/' }).Count -gt 0) {
    Write-Host '❌ --public 混入 cookie'; $fail = 1
  }

  $required = @(
    'README.md', 'LICENSE',
    'common.sh', 'start.sh', 'stop.sh', 'status.sh', 'restart.sh',
    'common.ps1', 'start.ps1', 'stop.ps1', 'status.ps1', 'restart.ps1'
  )
  foreach ($f in $required) {
    if (@($names | Where-Object { $_ -match ('/' + [regex]::Escape($f) + '$') }).Count -eq 0) {
      Write-Host "❌ 缺少 $f"
      $fail = 1
    }
  }

  Write-Host '--------------------------------------------------------------'
  $item = Get-Item -LiteralPath $out
  Write-Host ('{0}  （{1:N2} MB）' -f $item.FullName, ($item.Length / 1MB))
  Write-Host "文件数：$($names.Count)"
}
finally {
  Remove-Item -LiteralPath $tmpBase -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) {
  Write-Host "✅ 校验通过：$out"
}
else {
  Write-Host '❌ 校验失败'
  exit 1
}
