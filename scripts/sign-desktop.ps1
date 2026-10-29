param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [string]$CertificateThumbprint,
    [switch]$MachineCertificateStore,
    [string]$TimestampUrl = 'http://timestamp.digicert.com',
    [switch]$RequireTrustedSignature
)
$ErrorActionPreference = 'Stop'
$taskPackage = (Resolve-Path -LiteralPath $PackageDirectory).Path
if (!(Test-Path -LiteralPath (Join-Path $taskPackage 'warm_calendar.exe'))) { throw '请选择含warm_calendar.exe的完整分发目录。' }
$taskFiles = @(Get-ChildItem -LiteralPath $taskPackage -Recurse -File | Where-Object { $_.Extension -in '.exe','.dll' })
if ($CertificateThumbprint) {
    $taskThumbprint = $CertificateThumbprint.Replace(' ','')
    if ($taskThumbprint -notmatch '^[a-fA-F0-9]{40}$') { throw '证书指纹应为40位十六进制SHA1。' }
    $taskStore = if ($MachineCertificateStore) { 'LocalMachine' } else { 'CurrentUser' }
    $taskCertificate = Get-Item -LiteralPath "Cert:\$taskStore\My\$taskThumbprint"
    if (!$taskCertificate.HasPrivateKey -or $taskCertificate.NotAfter -le (Get-Date) -or
        $taskCertificate.NotBefore -gt (Get-Date) -or
        $taskCertificate.EnhancedKeyUsageList.ObjectId -notcontains '1.3.6.1.5.5.7.3.3') {
        throw '需要有效、具有私钥的代码签名证书。'
    }
    if ($taskCertificate.Subject -eq $taskCertificate.Issuer) { throw '自签名证书不能用于本项目的受信任发布流程。' }
    $taskSignTool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (!$taskSignTool) { throw '缺少Windows SDK SignTool。' }
    foreach ($taskFile in $taskFiles) {
        $taskBefore = Get-AuthenticodeSignature -LiteralPath $taskFile.FullName
        # Preserve valid upstream signatures (Node.js / Microsoft runtime).
        if ($taskBefore.Status -eq 'Valid') { continue }
        if ($taskBefore.Status -ne 'NotSigned') { throw "现有签名无效，停止处理：$($taskFile.Name) [$($taskBefore.Status)]" }
        $taskArguments = @('sign','/fd','SHA256','/tr',$TimestampUrl,'/td','SHA256','/sha1',$taskThumbprint,'/s','My')
        if ($MachineCertificateStore) { $taskArguments += '/sm' }
        & $taskSignTool @taskArguments $taskFile.FullName
        if ($LASTEXITCODE -ne 0) { throw "签名失败：$($taskFile.Name)" }
        & $taskSignTool verify /pa $taskFile.FullName
        if ($LASTEXITCODE -ne 0) { throw "签名验证失败：$($taskFile.Name)" }
    }
}
$taskReport = @($taskFiles | ForEach-Object {
    $taskSignature = Get-AuthenticodeSignature -LiteralPath $_.FullName
    [pscustomobject]@{
        file = [IO.Path]::GetRelativePath($taskPackage, $_.FullName)
        status = $taskSignature.Status.ToString()
        publisher = $taskSignature.SignerCertificate.Subject
        timestamped = $null -ne $taskSignature.TimeStamperCertificate
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
})
$taskReport | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $taskPackage 'windows-signatures.json') -Encoding utf8
if (($RequireTrustedSignature -or $CertificateThumbprint) -and @($taskReport | Where-Object {$_.status -ne 'Valid'}).Count -gt 0) {
    throw '分发包仍有未签名或签名无效的程序；未生成受信任发布包。'
}
$taskUnsigned = @($taskReport | Where-Object {$_.status -ne 'Valid'}).Count
Write-Output "签名检查：$($taskFiles.Count)个程序文件，其中${taskUnsigned}个未获有效签名。详情：windows-signatures.json"
