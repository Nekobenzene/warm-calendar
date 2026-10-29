param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskSdk = Join-Path $taskRoot '.tooling\flutter-stable\bin\flutter.bat'
if (!(Test-Path -LiteralPath $taskSdk)) {
    $taskSdk = (Get-Command flutter -ErrorAction Stop).Source
}
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
# This alias avoids an upstream Flutter LSP framing issue for non-ASCII paths.
$taskAlias = Join-Path $env:TEMP 'warm-calendar-01a1827b'
if (!(Test-Path -LiteralPath $taskAlias)) {
    New-Item -ItemType Junction -Path $taskAlias -Target $taskRoot | Out-Null
}
Push-Location -LiteralPath $taskAlias
try {
    if (Test-Path -LiteralPath (Join-Path $taskAlias '.tooling\flutter-stable\bin\flutter.bat')) {
        $taskSdk = Join-Path $taskAlias '.tooling\flutter-stable\bin\flutter.bat'
    }
    $env:PUB_CACHE = Join-Path $taskAlias '.tooling\pub-cache'
    $env:FLUTTER_ROOT = Join-Path $taskAlias '.tooling\flutter-stable'
    $taskConfig = Join-Path $taskAlias '.dart_tool\package_config.json'
    if (Test-Path -LiteralPath $taskConfig) {
        $sourceUri = ([System.Uri]($taskRoot.TrimEnd('\') + '\')).AbsoluteUri.TrimEnd('/')
        $aliasUri = ([System.Uri]($taskAlias.TrimEnd('\') + '\')).AbsoluteUri.TrimEnd('/')
        $configText = [System.IO.File]::ReadAllText($taskConfig)
        $updatedConfig = $configText.Replace($sourceUri, $aliasUri)
        if ($updatedConfig -ne $configText) {
            [System.IO.File]::WriteAllText($taskConfig, $updatedConfig)
        }
    }
    & $taskSdk --no-version-check --suppress-analytics @FlutterArgs
    $taskExit = $LASTEXITCODE
} finally { Pop-Location }
exit $taskExit
