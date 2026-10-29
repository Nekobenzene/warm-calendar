param([string]$WindowsInstaller, [string]$AndroidApk)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskVersionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $taskRoot 'pubspec.yaml') -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)')
if (!$taskVersionMatch.Success) { throw '无法读取版本。' }
$taskVersion = $taskVersionMatch.Groups[1].Value
if (!$WindowsInstaller) { $WindowsInstaller = Join-Path $taskRoot "dist/日程表-Setup-$taskVersion-x64.exe" }
if (!$AndroidApk) {
    $AndroidApk = Join-Path $taskRoot "dist/日程表-Android-$taskVersion.apk"
    if (!(Test-Path -LiteralPath $AndroidApk)) { $AndroidApk = Join-Path $taskRoot 'dist/日程表-Android.apk' }
}
$taskInstaller = Get-Item -LiteralPath $WindowsInstaller
$taskApk = Get-Item -LiteralPath $AndroidApk
$taskInstalledVersion = [version]$taskInstaller.VersionInfo.ProductVersion
if ("$($taskInstalledVersion.Major).$($taskInstalledVersion.Minor).$($taskInstalledVersion.Build)" -ne $taskVersion) { throw 'Windows安装包版本与pubspec.yaml不一致。' }
if ($taskApk.Extension -ne '.apk' -or $taskApk.Length -lt 1MB) { throw 'Android安装包无效。' }
$taskOutput = Join-Path $taskRoot "dist/releases/$taskVersion"
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskPairs = @(
    @{ Source = $taskInstaller.FullName; Name = "warm-calendar-$taskVersion-windows-x64-setup.exe" },
    @{ Source = $taskApk.FullName; Name = "warm-calendar-$taskVersion-android.apk" }
)
$taskChecksums = @(foreach ($taskPair in $taskPairs) {
    $taskDestination = Join-Path $taskOutput $taskPair.Name
    if (Test-Path -LiteralPath $taskDestination) {
        if ((Get-FileHash -LiteralPath $taskDestination).Hash -ne (Get-FileHash -LiteralPath $taskPair.Source).Hash) {
            throw "同版本附件内容不同，请增加版本或先检查：$($taskPair.Name)"
        }
    } else { Copy-Item -LiteralPath $taskPair.Source -Destination $taskDestination }
    "$((Get-FileHash -LiteralPath $taskDestination -Algorithm SHA256).Hash.ToLowerInvariant())  $($taskPair.Name)"
})
[IO.File]::WriteAllLines((Join-Path $taskOutput 'SHA256SUMS.txt'), $taskChecksums, [Text.UTF8Encoding]::new($false))
Write-Output "发布目录：$taskOutput"
$taskChecksums
