#Requires -Version 7.0
<#
verify-apk-plugins.ps1 — APK 插件完整性扫描（可重复回归件）

机制不变量（Flutter 3.47 实读 SDK 源码结论）：
  1. GeneratedPluginRegistrant.java 由 flutter tool（pub get / build）直接写入
     android/app/src/main/java/io/flutter/plugins/，是唯一写入者；内容一致时跳过重写
     （flutter_plugins.dart _renderTemplateToFile），mtime 不变 = up-to-date，非陈旧证据。
  2. .flutter-plugins-dependencies 中 native_build=true 的 android 插件集合
     必须与 registrant 注册的插件名集合一致（settings loader 与 javac 共用此清单）。
  3. registrant 声明的每个原生类必须真实存在于 APK 全部 dex 中。

边界：联邦纯 Dart 实现（如 path_provider_android 2.3.x 的 dartPluginClass）无 Java 类，
本就不应出现在 registrant/dex，不在检查范围。

退出码：0=全部通过；1=完整性破坏（缺注册/缺类/陈旧引用）；2=输入文件缺失。
#>
param(
    [string]$Apk = (Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-debug.apk'),
    [string]$ProjectRoot = (Join-Path $PSScriptRoot '..')
)
$ErrorActionPreference = 'Stop'

$registrantPath = Join-Path $ProjectRoot 'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'
$fpdPath = Join-Path $ProjectRoot '.flutter-plugins-dependencies'
foreach ($f in @($Apk, $registrantPath, $fpdPath)) {
    if (-not (Test-Path -LiteralPath $f)) { Write-Output "MISSING INPUT: $f"; exit 2 }
}

# 1) registrant 解析：插件名 + 类 FQN
$src = Get-Content -LiteralPath $registrantPath -Raw
$regNames = @([regex]::Matches($src, 'Error registering plugin ([A-Za-z0-9_]+),') | ForEach-Object { $_.Groups[1].Value })
$regClasses = @([regex]::Matches($src, 'add\(new ([A-Za-z0-9_.]+)\(\)\)') | ForEach-Object { $_.Groups[1].Value })

# 2) FPD native_build=true 插件名集合
$fpdNames = @((Get-Content -LiteralPath $fpdPath -Raw | ConvertFrom-Json).plugins.android |
    Where-Object { $_.native_build } | ForEach-Object { $_.name })

$fail = @()
$onlyFpd = @($fpdNames | Where-Object { $_ -notin $regNames })
$onlyReg = @($regNames | Where-Object { $_ -notin $fpdNames })
if ($onlyFpd) { $fail += "FPD native plugin not registered in registrant: $($onlyFpd -join ', ')" }
if ($onlyReg) { $fail += "registrant references plugin absent from FPD (stale registrant): $($onlyReg -join ', ')" }

# 3) dex 扫描：registrant 声明的每个类 + registrant 本体
Add-Type -AssemblyName System.IO.Compression.FileSystem
$patterns = @($regClasses | ForEach-Object { 'L' + ($_ -replace '\.', '/') + ';' })
$patterns += 'Lio/flutter/plugins/GeneratedPluginRegistrant;'
$found = @{}
foreach ($p in $patterns) { $found[$p] = $false }

$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Apk))
$dexCount = 0
foreach ($entry in $zip.Entries | Where-Object { $_.FullName -like '*.dex' }) {
    $dexCount++
    $ms = New-Object System.IO.MemoryStream
    $entry.Open().CopyTo($ms)
    $text = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($ms.ToArray())
    foreach ($p in $patterns) { if (-not $found[$p] -and $text.Contains($p)) { $found[$p] = $true } }
}
$zip.Dispose()

foreach ($p in $patterns) {
    Write-Output ("[{0}] {1}" -f $(if ($found[$p]) { 'OK' } else { 'MISSING' }), $p)
    if (-not $found[$p]) { $fail += "class not found in any dex: $p" }
}
Write-Output ("summary: registrant_classes={0} fpd_native_plugins={1} dex_files={2}" -f $regClasses.Count, $fpdNames.Count, $dexCount)

if ($fail.Count) { $fail | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
Write-Output 'PASS: APK plugin integrity verified'
exit 0
