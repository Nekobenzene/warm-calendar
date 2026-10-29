$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskToolDirectory = Join-Path $taskRoot '.tooling/inno-6.7.4'
$taskCompiler = Join-Path $taskToolDirectory 'ISCC.exe'
if (Test-Path -LiteralPath $taskCompiler) {
    if ((Get-AuthenticodeSignature -LiteralPath $taskCompiler).Status -ne 'Valid') { throw '安装编译器签名无效。' }
    Write-Output $taskCompiler
    return
}
$taskDownload = Join-Path $taskRoot '.tooling/innosetup-6.7.4.exe'
New-Item -ItemType Directory -Path (Split-Path $taskDownload) -Force | Out-Null
if (!(Test-Path -LiteralPath $taskDownload)) {
    Invoke-WebRequest -Uri 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_4/innosetup-6.7.4.exe' -OutFile $taskDownload
}
if ((Get-FileHash -LiteralPath $taskDownload -Algorithm SHA256).Hash -ne 'A549929319F9120716677C685535CA4671E4B937B5FDC87E2585F32D8EB30E8C') { throw '官方编译器安装包哈希不匹配。' }
$taskSignature = Get-AuthenticodeSignature -LiteralPath $taskDownload
if ($taskSignature.Status -ne 'Valid' -or $taskSignature.SignerCertificate.Subject -notmatch 'Pyrsys B.V.') { throw '官方编译器签名无效。' }
$taskProcess = Start-Process -FilePath $taskDownload -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER','/PORTABLE=1',('/DIR="' + $taskToolDirectory + '"'),'/NOICONS','/TASKS=') -WindowStyle Hidden -Wait -PassThru
if ($taskProcess.ExitCode -ne 0 -or !(Test-Path -LiteralPath $taskCompiler)) { throw '准备便携安装编译器失败。' }
Write-Output $taskCompiler
