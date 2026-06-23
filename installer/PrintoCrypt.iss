#ifndef MyAppVersion
  #define MyAppVersion "1.0.1"
#endif

#define MyAppName "PrintoCrypt"
#define MyAppPublisher "PrintoCrypt"
#define MyAppExeName "PrintoCrypt.exe"
#define MyAppUrl "https://github.com/printocrypt/printocrypt"

[Setup]
AppId={{8F4E2A61-9C3D-4B15-9E7A-1D2F8C6B4A90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppSupportURL={#MyAppUrl}
AppUpdatesURL={#MyAppUrl}
DefaultDirName={autopf}\PrintoCrypt
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\artifacts
OutputBaseFilename=PrintoCrypt-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupLogging=yes
CloseApplications=force
CloseApplicationsFilter={#MyAppExeName}
AppMutex=PrintoCrypt_Broker
RestartApplications=no
UsePreviousAppDir=yes
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "czech"; MessagesFile: "compiler:Languages\Czech.isl"

[Files]
Source: "..\artifacts\PrintoCrypt-Setup\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\artifacts\PrintoCrypt-Setup\Install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\artifacts\PrintoCrypt-Setup\Uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\artifacts\PrintoCrypt-Setup\PrintoCrypt-Spooler.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\artifacts\PrintoCrypt-Setup\PrintoCrypt-Analytics.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\artifacts\PrintoCrypt-Setup\PrintoCrypt-UserLaunch.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; \
  Parameters: "{code:GetInstallPs1Params}"; \
  StatusMsg: "Configuring printer and settings..."; \
  Description: "Configure PrintoCrypt"; \
  Flags: runhidden waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Uninstall.ps1"" -InstallDir ""{app}"" -SkipAppRemoval -Quiet"; \
  Flags: runhidden waituntilterminated; \
  RunOnceId: "ConfigureUninstall"

[Code]
var
  AnalyticsAction: String;

const
  UninstallKeyInno = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{8F4E2A61-9C3D-4B15-9E7A-1D2F8C6B4A90}}_is1';
  UninstallKeyLegacy = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\PrintoCrypt';

function ExitProcess(uExitCode: UINT): BOOL;
  external 'ExitProcess@kernel32.dll stdcall';

function GetVersionPart(var VersionText: String): Integer;
var
  DotPos: Integer;
  PartText: String;
begin
  Result := 0;
  if VersionText = '' then
    Exit;

  DotPos := Pos('.', VersionText);
  if DotPos > 0 then
  begin
    PartText := Copy(VersionText, 1, DotPos - 1);
    Delete(VersionText, 1, DotPos);
  end
  else
  begin
    PartText := VersionText;
    VersionText := '';
  end;

  if PartText <> '' then
    Result := StrToIntDef(PartText, 0);
end;

function CompareVersionStrings(const Version1, Version2: String): Integer;
var
  LeftText: String;
  RightText: String;
  Index: Integer;
  LeftPart: Integer;
  RightPart: Integer;
begin
  LeftText := Version1;
  RightText := Version2;

  for Index := 1 to 4 do
  begin
    LeftPart := GetVersionPart(LeftText);
    RightPart := GetVersionPart(RightText);

    if LeftPart > RightPart then
    begin
      Result := 1;
      Exit;
    end;

    if LeftPart < RightPart then
    begin
      Result := -1;
      Exit;
    end;
  end;

  Result := 0;
end;

function GetFileVersionString(const FileName: String): String;
var
  VersionMS, VersionLS: Cardinal;
begin
  Result := '';
  if not GetVersionNumbers(FileName, VersionMS, VersionLS) then
    Exit;

  Result := IntToStr(VersionMS shr 16) + '.' +
            IntToStr(VersionMS and $FFFF) + '.' +
            IntToStr(VersionLS shr 16);
end;

function GetInstalledVersion(var Version: String): Boolean;
var
  RegistryVersion: String;
  InstallLocation: String;
  ExePath: String;
  ExeVersion: String;
begin
  Result := False;
  Version := '';
  RegistryVersion := '';

  if RegQueryStringValue(HKLM, UninstallKeyInno, 'DisplayVersion', RegistryVersion) then
    Version := RegistryVersion
  else if RegQueryStringValue(HKLM, UninstallKeyLegacy, 'DisplayVersion', RegistryVersion) then
    Version := RegistryVersion;

  InstallLocation := '';
  if not RegQueryStringValue(HKLM, UninstallKeyInno, 'InstallLocation', InstallLocation) then
    RegQueryStringValue(HKLM, UninstallKeyLegacy, 'InstallLocation', InstallLocation);

  if InstallLocation <> '' then
    ExePath := AddBackslash(InstallLocation) + '{#MyAppExeName}'
  else
    ExePath := ExpandConstant('{autopf}\PrintoCrypt\{#MyAppExeName}');

  if FileExists(ExePath) then
  begin
    ExeVersion := GetFileVersionString(ExePath);
    if ExeVersion <> '' then
    begin
      if Version = '' then
        Version := ExeVersion
      else if CompareVersionStrings(ExeVersion, Version) > 0 then
        Version := ExeVersion;
    end;
  end;

  Result := Version <> '';
end;

function ResolveInstallIntent(var ShouldSkip: Boolean): String;
var
  InstalledVersion: String;
begin
  ShouldSkip := False;
  Result := 'install';

  if not GetInstalledVersion(InstalledVersion) then
  begin
    Log('Install: PrintoCrypt is not installed. Proceeding with installation.');
    Exit;
  end;

  if CompareVersionStrings(InstalledVersion, '{#MyAppVersion}') >= 0 then
  begin
    Log(
      'Install skipped: installed version ' + InstalledVersion +
      ' is current (installer version {#MyAppVersion}).');
    ShouldSkip := True;
    Exit;
  end;

  Log(
    'Install: upgrading from version ' + InstalledVersion +
    ' to {#MyAppVersion}.');
  Result := 'update';
end;

procedure StopRunningPrintoCrypt;
var
  ResultCode: Integer;
begin
  { Avoid sc.exe "file not found" noise when the service/task never existed. }
  Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -Command "' +
    'Stop-Service -Name PrintoCryptBroker -Force -ErrorAction SilentlyContinue; ' +
    'Stop-Process -Name {#MyAppExeName} -Force -ErrorAction SilentlyContinue"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function GetInstallPs1Params(Param: String): String;
var
  SkipLaunchFlag: String;
  ResultFilePath: String;
begin
  if WizardSilent then
    SkipLaunchFlag := ' -SkipLaunch'
  else
    SkipLaunchFlag := '';

  ResultFilePath := ExpandConstant('{commonappdata}') + '\PrintoCrypt\install-result.json';

  Result :=
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
    ExpandConstant('{app}\Install.ps1') +
    '" -InstallDir "' + ExpandConstant('{app}') +
    '" -SkipAppCopy -Quiet -AnalyticsAction ' + AnalyticsAction +
    SkipLaunchFlag +
    ' -ResultFile "' + ResultFilePath + '"';

  Log('Install.ps1 params: ' + Result);
end;

function InitializeSetup: Boolean;
var
  ShouldSkip: Boolean;
begin
  AnalyticsAction := ResolveInstallIntent(ShouldSkip);

  if ShouldSkip then
  begin
    if WizardSilent then
      ExitProcess(0)
    else
    begin
      MsgBox(
        'The latest version of {#MyAppName} is already installed.',
        mbInformation, MB_OK);
      Result := False;
      Exit;
    end;
  end;

  StopRunningPrintoCrypt;
  Result := True;
end;

function InitializeUninstall: Boolean;
begin
  StopRunningPrintoCrypt;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usAppMutexCheck then
    StopRunningPrintoCrypt;
end;
