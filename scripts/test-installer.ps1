param([string]$InstallerPath)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
if (!$InstallerPath) { $InstallerPath = Join-Path $taskRoot 'verification/installer-build/Calendar-Setup-Test.exe' }
$taskInstaller = (Resolve-Path -LiteralPath $InstallerPath).Path
if ([IO.Path]::GetFileName($taskInstaller) -ne 'Calendar-Setup-Test.exe' -or
    (Get-Item -LiteralPath $taskInstaller).VersionInfo.ProductName -notlike '*安装验证*') {
    throw '只能运行-TestBuild生成的独立身份测试安装器。'
}
$taskUninstallKey = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/WarmCalendar.Planner.InstallerTest_is1'
if (Test-Path $taskUninstallKey) { throw '已有测试安装，请先卸载，避免覆盖其他测试目录。' }
$taskWork = Join-Path $taskRoot ('verification/installer-smoke-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$taskInstall = Join-Path $taskWork '程序 安装'
$taskDesktop = Join-Path $taskWork '自定义桌面'
$taskMenu = Join-Path $taskWork '自定义开始菜单'
$taskMenu2 = Join-Path $taskWork '更换开始菜单'
New-Item -ItemType Directory -Path $taskWork -Force | Out-Null
$taskRunKey = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Run'
function Read-StartupValue([string]$Name) {
    $taskProperties = Get-ItemProperty -LiteralPath $taskRunKey
    return $taskProperties.PSObject.Properties[$Name].Value
}
$taskBeforeRun = Read-StartupValue 'WarmCalendar'
$taskBeforeTestRun = Read-StartupValue 'WarmCalendarVerification'
$taskNode = (Get-Command node -ErrorAction Stop).Source
$taskResults = [Collections.Generic.List[string]]::new()
$taskApp = $null
$taskRelay = $null
$taskOtherNode = $null
function Assert-Installer($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
    $taskResults.Add($Message)
    Write-Output "PASS: $Message"
}
function Invoke-TestSetup([string]$Tasks, [string]$Menu, [string]$Log) {
    $taskArguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',
        ('/DIR="' + $taskInstall + '"'),('/DESKTOPDIR="' + $taskDesktop + '"'),
        ('/MENUDIR="' + $Menu + '"'),('/TASKS="' + $Tasks + '"'),('/LOG="' + (Join-Path $taskWork $Log) + '"'))
    $taskSetup = Start-Process -FilePath $taskInstaller -ArgumentList $taskArguments -WindowStyle Hidden -Wait -PassThru
    return $taskSetup.ExitCode
}
try {
    Assert-Installer ((Invoke-TestSetup 'desktopicon,startmenuicon,startup' $taskMenu 'install.log') -eq 0) '自定义中文及空格路径安装成功'
    Assert-Installer (Test-Path $taskUninstallKey) '当前用户卸载入口已注册'
    $taskShell = New-Object -ComObject WScript.Shell
    foreach ($taskFolder in @($taskDesktop,$taskMenu)) {
        $taskLink = $taskShell.CreateShortcut((Join-Path $taskFolder '日程表-安装验证.lnk'))
        Assert-Installer ($taskLink.TargetPath -eq (Join-Path $taskInstall 'warm_calendar.exe')) "快捷方式正确指向程序：$taskFolder"
        Assert-Installer ($taskLink.Arguments -eq '--verification') '测试快捷方式使用隔离身份'
    }
    $taskStartup = Get-ItemPropertyValue $taskRunKey 'WarmCalendarVerification'
    Assert-Installer ($taskStartup.Contains('"' + (Join-Path $taskInstall 'warm_calendar.exe') + '" --tray')) '开机启动路径已引用，包含托盘参数'
    Assert-Installer (@(Get-CimInstance Win32_Process -Filter "Name='warm_calendar.exe'" | Where-Object ExecutablePath -eq (Join-Path $taskInstall 'warm_calendar.exe')).Count -eq 0) '静默安装不会自动运行应用'
    foreach ($taskFile in @('warm_calendar.exe','flutter_windows.dll','data/app.so','sync-service/server.mjs','sync-service/node.exe')) {
        $taskExpected = Join-Path $taskRoot ('dist/日程表Windows-安装版/' + $taskFile)
        Assert-Installer ((Get-FileHash -LiteralPath (Join-Path $taskInstall $taskFile)).Hash -eq (Get-FileHash -LiteralPath $taskExpected).Hash) "安装文件完整：$taskFile"
    }
    # Check the real application reads the installer's selection into its SQLite preferences.
    $taskDatabase = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'warm_calendar_verification.sqlite'
    $taskReadStartup = Join-Path $taskWork 'read-startup.cjs'
    @'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.argv[2], {readOnly:true});
const row = db.prepare('SELECT payload FROM settings WHERE id=1').get();
console.log(row ? JSON.parse(row.payload).launchAtStartup : 'missing');
db.close();
'@ | Set-Content -LiteralPath $taskReadStartup -Encoding utf8
    $taskApp = Start-Process -FilePath (Join-Path $taskInstall 'warm_calendar.exe') -ArgumentList '--verification' -WorkingDirectory $taskInstall -WindowStyle Hidden -PassThru
    $taskObserved = ''
    for ($taskAttempt = 0; $taskAttempt -lt 20; $taskAttempt++) {
        Start-Sleep -Milliseconds 500
        if ($taskApp.HasExited) { throw "验证应用提前退出：$($taskApp.ExitCode)" }
        if (Test-Path -LiteralPath $taskDatabase) {
            $taskObserved = & $taskNode --disable-warning=ExperimentalWarning $taskReadStartup $taskDatabase
            if ($LASTEXITCODE -eq 0 -and $taskObserved -eq 'true') { break }
        }
    }
    Assert-Installer ($taskObserved -eq 'true') '真实桌面首次运行保留安装器的自启动选择'
    # The mutex should reject an upgrade while an application is running, preserving edits.
    Assert-Installer ((Invoke-TestSetup 'desktopicon,startmenuicon,startup' $taskMenu 'running-block.log') -ne 0) '应用运行期间阻止覆盖安装'
    Stop-Process -Id $taskApp.Id
    $taskApp.WaitForExit()
    $taskApp = $null
    # Exercise precise background-process matching without using the real LAN relay/database.
    $taskProbe = Join-Path $taskWork 'wait.cjs'
    'setInterval(() => {}, 1000);' | Set-Content -LiteralPath $taskProbe -Encoding utf8
    $taskOtherNode = Start-Process -FilePath $taskNode -ArgumentList ('"' + $taskProbe + '"') -WindowStyle Hidden -PassThru
    $taskRelay = Start-Process -FilePath (Join-Path $taskInstall 'sync-service/node.exe') -ArgumentList @('-e','"setInterval(() => {}, 1000)"','--',('"' + (Join-Path $taskInstall 'sync-service/server.mjs') + '"')) -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 500
    Assert-Installer (!$taskRelay.HasExited) '隔离后台服务探针正在运行'
    Assert-Installer ((Invoke-TestSetup 'startmenuicon' $taskMenu2 'upgrade.log') -eq 0) '升级可更换快捷方式位置并关闭自启动'
    Assert-Installer $taskRelay.HasExited '升级停止本安装目录的后台进程'
    $taskRelay = $null
    Assert-Installer (!$taskOtherNode.HasExited) '升级保留其他Node进程'
    Assert-Installer (!(Test-Path -LiteralPath (Join-Path $taskDesktop '日程表-安装验证.lnk'))) '取消桌面选项后移除旧安装快捷方式'
    Assert-Installer (!(Test-Path -LiteralPath (Join-Path $taskMenu '日程表-安装验证.lnk'))) '更换目录后移除旧开始菜单快捷方式'
    Assert-Installer (Test-Path -LiteralPath (Join-Path $taskMenu2 '日程表-安装验证.lnk')) '新开始菜单位置已生效'
    Assert-Installer ($null -eq (Read-StartupValue 'WarmCalendarVerification')) '升级取消自启动时删除启动项'
    $taskApp = Start-Process -FilePath (Join-Path $taskInstall 'warm_calendar.exe') -ArgumentList '--verification' -WorkingDirectory $taskInstall -WindowStyle Hidden -PassThru
    $taskObserved = ''
    for ($taskAttempt = 0; $taskAttempt -lt 20; $taskAttempt++) {
        Start-Sleep -Milliseconds 500
        $taskObserved = & $taskNode --disable-warning=ExperimentalWarning $taskReadStartup $taskDatabase
        if ($LASTEXITCODE -eq 0 -and $taskObserved -eq 'false') { break }
    }
    Assert-Installer ($taskObserved -eq 'false') '重新运行也不会恢复旧的开启偏好'
    Stop-Process -Id $taskApp.Id
    $taskApp.WaitForExit()
    $taskApp = $null
    $taskDatabaseHash = (Get-FileHash -LiteralPath $taskDatabase).Hash
    # A user may enable autostart after an install which originally left it off.
    Set-ItemProperty $taskRunKey 'WarmCalendarVerification' ('"' + (Join-Path $taskInstall 'warm_calendar.exe') + '" --tray --verification')
    $taskUninstaller = Join-Path $taskInstall 'unins000.exe'
    $taskUninstall = Start-Process -FilePath $taskUninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="' + (Join-Path $taskWork 'uninstall.log') + '"')) -WindowStyle Hidden -Wait -PassThru
    Assert-Installer ($taskUninstall.ExitCode -eq 0) '卸载成功'
    Assert-Installer (!(Test-Path -LiteralPath (Join-Path $taskInstall 'warm_calendar.exe'))) '卸载移除应用文件'
    Assert-Installer (!(Test-Path $taskUninstallKey)) '卸载移除应用列表入口'
    Assert-Installer (!(Test-Path -LiteralPath (Join-Path $taskMenu2 '日程表-安装验证.lnk'))) '卸载移除自定义位置快捷方式'
    Assert-Installer ($null -eq (Read-StartupValue 'WarmCalendarVerification')) '卸载移除后来开启的启动项'
    Assert-Installer ((Get-FileHash -LiteralPath $taskDatabase).Hash -eq $taskDatabaseHash) '卸载保留SQLite数据且内容不变'
    Assert-Installer (!$taskOtherNode.HasExited) '卸载保留其他Node进程'
    Assert-Installer ((Read-StartupValue 'WarmCalendar') -eq $taskBeforeRun) '正式桌面的开机启动项保持不变'
    $taskResults | Set-Content -LiteralPath (Join-Path $taskWork 'passed.txt') -Encoding utf8
    Write-Output "共$($taskResults.Count)项安装检查通过。日志：$taskWork"
} finally {
    foreach ($taskProcess in @($taskApp,$taskRelay,$taskOtherNode)) {
        if ($null -ne $taskProcess -and !$taskProcess.HasExited) { Stop-Process -Id $taskProcess.Id }
    }
    if ($null -ne $taskBeforeTestRun) {
        Set-ItemProperty $taskRunKey 'WarmCalendarVerification' $taskBeforeTestRun
    } else {
        Remove-ItemProperty $taskRunKey 'WarmCalendarVerification' -ErrorAction SilentlyContinue
    }
}
