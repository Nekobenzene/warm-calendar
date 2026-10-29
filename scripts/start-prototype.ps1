$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $taskRoot
try { & node (Join-Path $PSScriptRoot 'serve.mjs') }
finally { Pop-Location }
