param(
    [string]$PackageDirectory,
    [string]$CompilerPath,
    [string]$CertificateThumbprint,
    [switch]$MachineCertificateStore,
    [switch]$RequireTrustedSignature,
    [switch]$TestBuild
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
if (!$PackageDirectory) { $PackageDirectory = Join-Path $taskRoot 'dist/日程表Windows' }
$taskPackage = (Resolve-Path -LiteralPath $PackageDirectory).Path
foreach ($taskRequired in @('warm_calendar.exe','flutter_windows.dll','data/app.so','sync-service/node.exe','sync-service/server.mjs')) {
    if (!(Test-Path -LiteralPath (Join-Path $taskPackage $taskRequired))) { throw "桌面包不完整：$taskRequired" }
}
if (!$CompilerPath) { $CompilerPath = & "$PSScriptRoot/prepare-installer-tools.ps1" }
if (!(Test-Path -LiteralPath $CompilerPath)) { throw '未找到 Inno Setup 编译器。' }
$taskVersionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $taskRoot 'pubspec.yaml') -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?)')
if (!$taskVersionMatch.Success) { throw '无法读取版本。' }
$taskVersion = $taskVersionMatch.Groups[1].Value
$taskPreview = $taskVersion.Contains('-preview')
$taskNumericVersion = $taskVersion -replace '-.*$', ''
$taskOutput = if ($TestBuild) { Join-Path $taskRoot 'verification/installer-build' } elseif ($taskPreview) { Join-Path $taskRoot "dist/previews/$taskVersion" } else { Join-Path $taskRoot 'dist' }
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskArguments = @('/Qp',"/DPackageDir=$taskPackage","/DAppVersion=$taskVersion","/DAppVersionNumeric=$taskNumericVersion","/DOutputDir=$taskOutput")
if ($TestBuild) { $taskArguments += '/DInstallerTest=1' }
elseif ($taskPreview) { $taskArguments += '/DPreviewBuild=1' }
# Sign application payload before embedding it. Never synthesize a self-signed publisher.
& "$PSScriptRoot/sign-desktop.ps1" -PackageDirectory $taskPackage -CertificateThumbprint $CertificateThumbprint -MachineCertificateStore:$MachineCertificateStore -RequireTrustedSignature:$RequireTrustedSignature
if ($CertificateThumbprint) {
    $taskSignTool = Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/bin" -Directory |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'x64/signtool.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (!$taskSignTool) { throw '缺少Windows SDK SignTool。' }
    $taskStoreArgument = if ($MachineCertificateStore) { ' /sm' } else { '' }
    $taskSignCommand = '$q' + $taskSignTool + '$q sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /sha1 ' + $CertificateThumbprint.Replace(' ','') + ' /s My' + $taskStoreArgument + ' $f'
    $taskArguments += @('/DSignInstaller=1',('/SCalendarSign=' + $taskSignCommand))
}
$taskArguments += (Join-Path $taskRoot 'installer/calendar.iss')
& $CompilerPath @taskArguments
if ($LASTEXITCODE -ne 0) { throw '安装向导编译失败。' }
$taskName = if ($TestBuild) { 'Calendar-Setup-Test.exe' } elseif ($taskPreview) { "warm-calendar-$taskVersion-windows-x64-setup.exe" } else { "日程表-Setup-$taskVersion-x64.exe" }
$taskInstaller = Join-Path $taskOutput $taskName
$taskSignature = Get-AuthenticodeSignature -LiteralPath $taskInstaller
if (($RequireTrustedSignature -or $CertificateThumbprint) -and $taskSignature.Status -ne 'Valid') { throw '安装程序未获得有效签名。' }
$taskHash = (Get-FileHash -LiteralPath $taskInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
"$taskHash  $taskName" | Set-Content -LiteralPath ($taskInstaller + '.sha256') -Encoding utf8
[pscustomobject]@{ File = $taskInstaller; SHA256 = $taskHash; Signature = $taskSignature.Status.ToString() } |
    ConvertTo-Json | Set-Content -LiteralPath ($taskInstaller + '.json') -Encoding utf8
Write-Output "安装程序：$taskInstaller"
Write-Output "签名：$($taskSignature.Status)"
