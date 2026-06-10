#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
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
CloseApplications=yes
CloseApplicationsFilter={#MyAppExeName}
AppMutex=PrintoCrypt_SingleInstance
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

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Install.ps1"" -InstallDir ""{app}"" -SkipAppCopy -Quiet"; \
  StatusMsg: "Configuring printer and settings..."; \
  Description: "Configure PrintoCrypt"; \
  Flags: runhidden waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Uninstall.ps1"" -InstallDir ""{app}"" -Quiet"; \
  Flags: runhidden waituntilterminated
