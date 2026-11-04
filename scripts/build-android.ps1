param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskAlias = Join-Path $env:TEMP 'warm-calendar-01a1827b'
if (!(Test-Path -LiteralPath $taskAlias)) { New-Item -ItemType Junction -Path $taskAlias -Target $taskRoot | Out-Null }
$taskJava = Get-ChildItem -LiteralPath (Join-Path $taskRoot '.tooling/java') -Directory | Select-Object -First 1
if (!$taskJava) { throw '缺少项目内JDK，请先准备.tooling/java。' }
$env:JAVA_HOME = Join-Path $taskAlias ".tooling/java/$($taskJava.Name)"
$env:ANDROID_HOME = Join-Path $taskAlias '.tooling/android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_USER_HOME = Join-Path $taskAlias '.tooling/android-user'
# Kotlin DSL cannot reliably load its compiler libraries through a junction
# whose canonical path contains Chinese characters. Use a real ASCII cache.
$env:GRADLE_USER_HOME = Join-Path $env:TEMP 'warm-calendar-gradle-cache'
$taskSigningDirectory = Join-Path $taskRoot '.tooling/signing'
New-Item -ItemType Directory -Path $taskSigningDirectory -Force | Out-Null
$taskKeyFile = Join-Path $taskSigningDirectory 'calendar-release.jks'
$taskPropertiesFile = Join-Path $taskSigningDirectory 'key.properties'
if (!(Test-Path -LiteralPath $taskKeyFile)) {
    $taskSecret = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    & (Join-Path $env:JAVA_HOME 'bin/keytool.exe') -genkeypair -keystore $taskKeyFile -storetype JKS -alias calendar -keyalg RSA -keysize 3072 -validity 10000 -storepass $taskSecret -keypass $taskSecret -dname 'CN=Warm Calendar Local Build, OU=Development, O=Warm Calendar, L=Local, ST=Local, C=CN'
    if ($LASTEXITCODE -ne 0) { throw '生成本地签名失败。' }
    $taskKeyPath = (Join-Path $taskAlias '.tooling/signing/calendar-release.jks').Replace('\','/')
    [IO.File]::WriteAllText($taskPropertiesFile, "storeFile=$taskKeyPath`nstorePassword=$taskSecret`nkeyAlias=calendar`nkeyPassword=$taskSecret`n")
}
if (!(Test-Path -LiteralPath $taskPropertiesFile)) { throw '签名配置丢失，请恢复原签名配置以保留升级能力。' }
$taskSdkPath = $env:ANDROID_HOME.Replace('\','/')
$taskFlutterPath = (Join-Path $taskAlias '.tooling/flutter-stable').Replace('\','/')
[IO.File]::WriteAllText((Join-Path $taskRoot 'android/local.properties'), "sdk.dir=$taskSdkPath`nflutter.sdk=$taskFlutterPath`n")
& "$PSScriptRoot/flutter.ps1" build apk --release --no-pub
if ($LASTEXITCODE -ne 0) { throw '安卓安装包编译失败。' }
$taskDist = Join-Path $taskRoot 'dist'
New-Item -ItemType Directory -Path $taskDist -Force | Out-Null
$taskOutput = if ($OutputPath) { [IO.Path]::GetFullPath($OutputPath, $taskRoot) } else { Join-Path $taskDist '日程表-Android.apk' }
New-Item -ItemType Directory -Path (Split-Path -Parent $taskOutput) -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRoot 'build/app/outputs/flutter-apk/app-release.apk') -Destination $taskOutput -Force
Write-Output "安卓安装包：$taskOutput"
