param([switch]$SkipBuild, [string]$ReleaseDirectory, [string]$PackageName = '日程表Windows',
    [string]$CertificateThumbprint, [switch]$MachineCertificateStore, [switch]$RequireTrustedSignature)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $taskRoot
try {
    if (!$SkipBuild) {
        & "$PSScriptRoot\flutter.ps1" pub get --offline
        if ($LASTEXITCODE -ne 0) {
            # Junctions work without changing Windows Developer Mode.
            $taskDependencyFile = Join-Path $taskRoot '.flutter-plugins-dependencies'
            if (!(Test-Path -LiteralPath $taskDependencyFile)) { throw '先运行 flutter pub get 下载依赖。' }
            $taskPlugins = Get-Content -LiteralPath $taskDependencyFile -Raw | ConvertFrom-Json
            $taskLinks = Join-Path $taskRoot 'windows\flutter\ephemeral\.plugin_symlinks'
            New-Item -ItemType Directory -Path $taskLinks -Force | Out-Null
            foreach ($taskPlugin in $taskPlugins.plugins.windows) {
                if ($taskPlugin.name -notmatch '^[a-z0-9_]+$') { throw '插件名称无效。' }
                $taskLink = Join-Path $taskLinks $taskPlugin.name
                if (!(Test-Path -LiteralPath $taskLink)) {
                    New-Item -ItemType Junction -Path $taskLink -Target $taskPlugin.path | Out-Null
                }
            }
            & "$PSScriptRoot\flutter.ps1" pub get --offline
            if ($LASTEXITCODE -ne 0) { throw '依赖准备失败。' }
        }
        & "$PSScriptRoot\flutter.ps1" build windows --release --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Windows构建失败。' }
    }
    $taskRelease = if ($ReleaseDirectory) {
        (Resolve-Path -LiteralPath $ReleaseDirectory).Path
    } else { Join-Path $taskRoot 'build\windows\x64\runner\Release' }
    if (!(Test-Path -LiteralPath "$taskRelease\warm_calendar.exe")) { throw '未找到构建产物。' }
    if ($PackageName -notmatch '^[\p{L}\p{N}_-]+$') { throw '打包名称只能包含文字、数字、下划线和连字符。' }
    $taskDestination = Join-Path (Join-Path $taskRoot 'dist') $PackageName
    New-Item -ItemType Directory -Path $taskDestination -Force | Out-Null
    Get-ChildItem -LiteralPath $taskRelease | Copy-Item -Destination $taskDestination -Recurse -Force
    $taskService = Join-Path $taskDestination 'sync-service'
    New-Item -ItemType Directory -Path $taskService -Force | Out-Null
    $taskNode = (Get-Command node -ErrorAction Stop).Source
    Copy-Item -LiteralPath $taskNode -Destination (Join-Path $taskService 'node.exe') -Force
    Copy-Item -LiteralPath (Join-Path $taskRoot 'sync-server/server.mjs') -Destination $taskService -Force
    Copy-Item -LiteralPath (Join-Path $taskRoot 'sync-server/NODE-LICENSE.txt') -Destination $taskService -Force
    Copy-Item -LiteralPath (Join-Path $taskRoot 'LINKING.md') -Destination (Join-Path $taskDestination '设备连接说明.md') -Force
    $taskVswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $taskVswhere) {
        $taskVs = & $taskVswhere -latest -products '*' -property installationPath
        $taskRedist = Join-Path $taskVs 'VC\Redist\MSVC'
        $taskRuntime = Get-ChildItem -LiteralPath $taskRedist -Directory |
            Where-Object { $_.Name -match '^\d' } | Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($taskRuntime) {
            Get-ChildItem -LiteralPath $taskRuntime -Filter '*.dll' | Copy-Item -Destination $taskDestination -Force
        }
    }
    Copy-Item -LiteralPath (Join-Path $taskRoot 'DESKTOP.md') -Destination (Join-Path $taskDestination '使用说明.md') -Force
    Copy-Item -LiteralPath (Join-Path $taskRoot 'SIGNING.md') -Destination (Join-Path $taskDestination '签名说明.md') -Force
    & "$PSScriptRoot\sign-desktop.ps1" -PackageDirectory $taskDestination -CertificateThumbprint $CertificateThumbprint -MachineCertificateStore:$MachineCertificateStore -RequireTrustedSignature:$RequireTrustedSignature
    Compress-Archive -LiteralPath $taskDestination -DestinationPath (Join-Path $taskRoot "dist\$PackageName.zip") -Force
    Write-Output "桌面版：$taskDestination\warm_calendar.exe"
} finally { Pop-Location }
