; Inzx for Windows: the installer, and the updater's way in.
;
; Built by scripts/package_windows_installer.ps1 (Inno Setup 6). Modelled on
; Nivio's, with one deliberate difference: it installs per user by default
; (%LOCALAPPDATA%\Programs\Inzx, no admin rights), so the in-app updater can
; upgrade it silently without a UAC prompt. Someone who wants it for every
; account can still pick that on the first page (it then needs admin, and so
; do its updates).
;
; Installing over an existing Inzx upgrades it in place. Only the program
; folder is ever written to: the library, settings, caches and downloads live
; in %APPDATA% / %LOCALAPPDATA% and are left alone by installs, updates and
; uninstalls alike.

#define MyAppName "Inzx"
#define MyAppPublisher "Inzx"
#define MyAppURL "https://inzx.nirmaleeswar.dev"
#define MyAppExeName "inzx.exe"

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist\windows"
#endif
; Never change this id: a different one installs next to the old version
; instead of upgrading it. (Tests pass their own, with their own name.)
#ifndef AppId
  #define AppId "{{D456CD5E-F982-467D-B685-0CEE43151362}"
#endif
#ifdef DisplayName
  #undef MyAppName
  #define MyAppName DisplayName
#endif

[Setup]
AppId={#AppId}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
VersionInfoVersion={#AppVersion}
; Per user unless the person chooses otherwise; never asks for admin by itself.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#MyAppName}
DisableDirPage=auto
DisableProgramGroupPage=yes
DefaultGroupName={#MyAppName}
OutputDir={#OutputDir}
OutputBaseFilename={#MyAppName}-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; A running Inzx is closed first (PrepareToInstall below); Windows' own
; restart manager is only the fallback, and never relaunches anything.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; The previous version's program files go first, so a library or asset a
; newer version no longer ships can't linger and clash with it. This is the
; program folder only.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.lib,*.exp,*.pdb,*.WebView2,*.WebView2\*"
#ifdef CrtDir
; The Visual C++ runtime, app-local: Inzx and its native libraries need it,
; and shipping it beside the exe means nothing is installed system-wide.
Source: "{#CrtDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
#endif

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
; In-app updates run this silently. "Update now" passes /RELAUNCH=1 to come
; back up in the new version; an update applied as Inzx closes doesn't.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait runasoriginaluser; Check: ShouldRelaunch

[UninstallDelete]
; Things Inzx itself may create in its program folder (the updater's marker,
; a WebView2 profile from older builds). User data elsewhere is kept.
Type: files; Name: "{app}\installed-by-setup"
Type: filesandordirs; Name: "{app}\{#MyAppExeName}.WebView2"

[Code]
// Stops Inzx processes running from this program folder (and only those: a
// development build elsewhere is left alone), so no file is locked and the
// new version doesn't find an old one still holding the window.
procedure StopRunningInzx(const Dir: String);
var
  ResultCode: Integer;
  Script, Quoted: String;
begin
  // A PowerShell single-quoted string: a quote in the path is doubled.
  Quoted := Dir;
  StringChangeEx(Quoted, '''', '''''', True);
  Script := 'Get-Process -Name inzx -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Path -and $_.Path.StartsWith(''' + Quoted + '\'', ' +
    '[System.StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force';
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' + Script + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(400);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopRunningInzx(ExpandConstant('{app}'));
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopRunningInzx(ExpandConstant('{app}'));
  Result := True;
end;

function ShouldRelaunch(): Boolean;
begin
  Result := WizardSilent() and (ExpandConstant('{param:RELAUNCH|0}') = '1');
end;

// Tells the in-app updater this copy came from the installer, so it may
// update itself. Builds run from anywhere else (a development checkout) never
// self-update.
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    SaveStringToFile(ExpandConstant('{app}\installed-by-setup'), '{#AppVersion}', False);
end;
