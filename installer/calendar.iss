; Build using scripts/build-installer.ps1. User data is deliberately outside {app}.
#ifndef PackageDir
  #error PackageDir is required
#endif
#ifndef AppVersion
  #define AppVersion "0.4.0"
#endif
#ifndef AppVersionNumeric
  #define AppVersionNumeric AppVersion
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif
#ifdef InstallerTest
  #define ProductId "WarmCalendar.Planner.InstallerTest"
  #define ProductName "日程表 · 安装验证"
  #define ShortcutName "日程表-安装验证"
  #define StartupName "WarmCalendarVerification"
  #define AppArguments "--verification"
  #define DesktopMutex "Local\WarmCalendar.Planner.Verification"
  #define NotificationId "WarmCalendar.Planner.Verification"
  #define OutputName "Calendar-Setup-Test"
#elif defined(PreviewBuild)
  #define ProductId "WarmCalendar.Planner.Preview"
  #define ProductName "日程表 · 本地预览"
  #define ShortcutName "日程表-本地预览"
  #define StartupName "WarmCalendarPreview"
  #define AppArguments ""
  #define DesktopMutex "Local\WarmCalendar.Planner.Preview"
  #define NotificationId "WarmCalendar.Planner.Preview"
  #define OutputName "warm-calendar-" + AppVersion + "-windows-x64-setup"
#else
  #define ProductId "WarmCalendar.Planner.Desktop"
  #define ProductName "日程表"
  #define ShortcutName "日程表"
  #define StartupName "WarmCalendar"
  #define AppArguments ""
  #define DesktopMutex "Local\WarmCalendar.Planner.Desktop"
  #define NotificationId "WarmCalendar.Planner.Desktop"
  #define OutputName "日程表-Setup-" + AppVersion + "-x64"
#endif

[Setup]
AppId={#ProductId}
AppName={#ProductName}
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersionNumeric}
AppPublisher=Warm Calendar
VersionInfoDescription={#ProductName} 安装程序
#ifdef InstallerTest
DefaultDirName={localappdata}\Programs\WarmCalendarInstallerTest
#elif defined(PreviewBuild)
DefaultDirName={localappdata}\Programs\WarmCalendarPreview
#else
DefaultDirName={localappdata}\Programs\WarmCalendar
#endif
DisableDirPage=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\warm_calendar.exe
UninstallDisplayName={#ProductName}
WizardStyle=modern
WizardSizePercent=110
ShowLanguageDialog=no
Compression=lzma2/normal
SolidCompression=yes
AppMutex={#DesktopMutex}
CloseApplications=no
RestartApplications=no
SetupLogging=yes
UsePreviousTasks=yes
#ifdef SignInstaller
SignTool=CalendarSign
SignedUninstaller=yes
#endif

[Languages]
Name: "zhcn"; MessagesFile: "ChineseSimplified.isl"

[Messages]
WelcomeLabel1=安装{#ProductName}
WelcomeLabel2=选择安装位置、快捷方式和启动选项。升级会保留日程与设备连接数据。
FinishedLabel=安装已完成。
SetupAppRunningError=日程表仍在运行。请保存编辑中的日程，从托盘右键选择“退出”，再继续安装。
UninstallAppRunningError=日程表仍在运行。请保存编辑中的日程，从托盘右键选择“退出”，再继续卸载。
ConfirmUninstall=确定卸载%1吗？日程、设置和设备连接数据会保留。

[Tasks]
Name: "desktopicon"; Description: "桌面快捷方式"; GroupDescription: "快捷方式："
Name: "startmenuicon"; Description: "开始菜单快捷方式"; GroupDescription: "快捷方式："
Name: "startup"; Description: "开机自启动（托盘运行）"; GroupDescription: "启动："; Flags: unchecked

[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Dirs]
Name: "{code:DesktopShortcutDir}"; Tasks: desktopicon
Name: "{code:MenuShortcutDir}"; Tasks: startmenuicon

[Icons]
Name: "{code:DesktopShortcutDir}\{#ShortcutName}"; Filename: "{app}\warm_calendar.exe"; Parameters: "{#AppArguments}"; WorkingDir: "{app}"; AppUserModelID: "{#NotificationId}"; Tasks: desktopicon
Name: "{code:MenuShortcutDir}\{#ShortcutName}"; Filename: "{app}\warm_calendar.exe"; Parameters: "{#AppArguments}"; WorkingDir: "{app}"; AppUserModelID: "{#NotificationId}"; Tasks: startmenuicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#StartupName}"; ValueData: """{app}\warm_calendar.exe"" --tray {#AppArguments}"; Tasks: startup; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "{#StartupName}"; Tasks: not startup; Flags: deletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "{#StartupName}"; ValueType: none; Flags: uninsdeletevalue dontcreatekey

[InstallDelete]
Type: files; Name: "{code:OldDesktopShortcut}"; Check: DeleteOldDesktopShortcut
Type: files; Name: "{code:OldMenuShortcut}"; Check: DeleteOldMenuShortcut

[Run]
Filename: "{app}\warm_calendar.exe"; Parameters: "{#AppArguments}"; WorkingDir: "{app}"; Description: "立即运行日程表"; Flags: postinstall nowait skipifsilent runasoriginaluser
Filename: "{app}\warm_calendar.exe"; Parameters: "{#AppArguments}"; WorkingDir: "{app}"; Flags: nowait runasoriginaluser; Check: IsUpdateInstall

[Code]
var
  ShortcutPage: TInputDirWizardPage;

function IsUpdateInstall: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:UPDATE|0}') = '1');
end;

function DesktopShortcutDir(Param: String): String;
begin
  Result := ShortcutPage.Values[0];
end;

function MenuShortcutDir(Param: String): String;
begin
  Result := ShortcutPage.Values[1];
end;

function OldDesktopShortcut(Param: String): String;
begin
  Result := GetPreviousData('DesktopShortcutDir', '') + '\{#ShortcutName}.lnk';
end;

function OldMenuShortcut(Param: String): String;
begin
  Result := GetPreviousData('MenuShortcutDir', '') + '\{#ShortcutName}.lnk';
end;

function DeleteOldDesktopShortcut: Boolean;
begin
  Result := (GetPreviousData('DesktopShortcutDir', '') <> '') and
    ((not WizardIsTaskSelected('desktopicon')) or
     (CompareText(GetPreviousData('DesktopShortcutDir', ''), DesktopShortcutDir('')) <> 0));
end;

function DeleteOldMenuShortcut: Boolean;
begin
  Result := (GetPreviousData('MenuShortcutDir', '') <> '') and
    ((not WizardIsTaskSelected('startmenuicon')) or
     (CompareText(GetPreviousData('MenuShortcutDir', ''), MenuShortcutDir('')) <> 0));
end;

procedure InitializeWizard;
var
  Tasks: String;
begin
  ShortcutPage := CreateInputDirPage(wpSelectTasks, '快捷方式位置',
    '选择快捷方式所在的文件夹', '', False, '');
  ShortcutPage.Add('桌面快捷方式位置：');
  ShortcutPage.Add('开始菜单快捷方式文件夹：');
  ShortcutPage.Values[0] := ExpandConstant('{param:DESKTOPDIR|}');
  if ShortcutPage.Values[0] = '' then
    ShortcutPage.Values[0] := GetPreviousData('DesktopShortcutDir', ExpandConstant('{userdesktop}'));
  ShortcutPage.Values[1] := ExpandConstant('{param:MENUDIR|}');
  if ShortcutPage.Values[1] = '' then
    ShortcutPage.Values[1] := GetPreviousData('MenuShortcutDir', ExpandConstant('{userprograms}\{#ProductName}'));
  if (ExpandConstant('{param:TASKS|__unset__}') = '__unset__') and
     (ExpandConstant('{param:MERGETASKS|__unset__}') = '__unset__') then begin
    Tasks := '';
    if WizardIsTaskSelected('desktopicon') then Tasks := 'desktopicon,';
    if WizardIsTaskSelected('startmenuicon') then Tasks := Tasks + 'startmenuicon,';
    if RegValueExists(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#StartupName}') then
      Tasks := Tasks + 'startup';
    WizardSelectTasks(Tasks);
  end;
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
begin
  SetPreviousData(PreviousDataKey, 'DesktopShortcutDir', DesktopShortcutDir(''));
  SetPreviousData(PreviousDataKey, 'MenuShortcutDir', MenuShortcutDir(''));
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = ShortcutPage.ID) and
    (not WizardIsTaskSelected('desktopicon')) and
    (not WizardIsTaskSelected('startmenuicon'));
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = ShortcutPage.ID then begin
    ShortcutPage.Edits[0].Enabled := WizardIsTaskSelected('desktopicon');
    ShortcutPage.Buttons[0].Enabled := WizardIsTaskSelected('desktopicon');
    ShortcutPage.Edits[1].Enabled := WizardIsTaskSelected('startmenuicon');
    ShortcutPage.Buttons[1].Enabled := WizardIsTaskSelected('startmenuicon');
  end;
end;

function ValidFolder(Path: String): Boolean;
begin
  Result := (Length(Path) > 2) and
    (((Path[2] = ':') and (Path[3] = '\')) or (Copy(Path, 1, 2) = '\\'));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = ShortcutPage.ID then begin
    if (WizardIsTaskSelected('desktopicon') and not ValidFolder(DesktopShortcutDir(''))) or
       (WizardIsTaskSelected('startmenuicon') and not ValidFolder(MenuShortcutDir(''))) then begin
      MsgBox('请选择完整的文件夹路径。', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := MemoDirInfo;
  if WizardIsTaskSelected('desktopicon') then
    Result := Result + NewLine + NewLine + '桌面快捷方式：' + NewLine + Space + DesktopShortcutDir('');
  if WizardIsTaskSelected('startmenuicon') then
    Result := Result + NewLine + NewLine + '开始菜单快捷方式：' + NewLine + Space + MenuShortcutDir('');
  if WizardIsTaskSelected('startup') then
    Result := Result + NewLine + NewLine + '开机自启动（托盘运行）：开启'
  else
    Result := Result + NewLine + NewLine + '开机自启动（托盘运行）：关闭';
end;

{ The GUI must be closed by the user; only this installation's detached relay
  is stopped. Never touch other Node processes or any AppData databases. }
function StopInstalledRelay: Boolean;
var
  Locator, Services, Processes, Process: Variant;
  I, Code: Integer;
  ExePath, ScriptPath, ProcessPath, ProcessCommand: String;
begin
  Result := True;
  ExePath := ExpandConstant('{app}\sync-service\node.exe');
  ScriptPath := ExpandConstant('{app}\sync-service\server.mjs');
  if not FileExists(ExePath) then Exit;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Services := Locator.ConnectServer('', 'root\CIMV2');
    Processes := Services.ExecQuery('SELECT * FROM Win32_Process WHERE Name=''node.exe''');
    for I := 0 to Processes.Count - 1 do begin
      Process := Processes.ItemIndex(I);
      if (not VarIsNull(Process.ExecutablePath)) and (not VarIsNull(Process.CommandLine)) then begin
        ProcessPath := Process.ExecutablePath;
        ProcessCommand := Process.CommandLine;
        if (CompareText(ProcessPath, ExePath) = 0) and
           (Pos(Lowercase(ScriptPath), Lowercase(ProcessCommand)) > 0) then begin
          Code := Process.Terminate(0);
          if Code <> 0 then Result := False;
        end;
      end;
    end;
    Sleep(300);
  except
    Log('Cannot check installed relay: ' + GetExceptionMessage);
    Result := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not StopInstalledRelay then
    Result := '无法关闭安装目录中的同步服务。请退出该服务后重试，或选择新的安装目录。';
end;

function InitializeUninstall: Boolean;
begin
  Result := not CheckForMutexes('{#DesktopMutex}');
  if not Result then
    MsgBox('请先保存日程，并从托盘右键选择“退出”，再卸载。', mbError, MB_OK);
end;

function UninstallNeedRestart: Boolean;
begin
  Result := False;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    if not StopInstalledRelay then
      Log('The relay could not be stopped; locked files may require a restart.');
end;
