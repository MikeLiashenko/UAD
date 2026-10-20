; The Windows installer of Ukraine Air Defense, built with Inno Setup 6 by make_installer.ps1:
;   ISCC /DSrcExe=<UAD.exe> /DAppVer=1.3.19 /DAppVer4=1.3.19.0 "/DAppLabel=v1.3.19 Alpha" /O<dir> /FUAD_Setup uad.iss
; Inno Setup instead of a home-made installer: antivirus programs know its setup program, while a
; small unknown .exe that unpacks another .exe looked to them like a virus dropper.
;
; Installs for the current user only (no administrator rights, no UAC prompt) into
; %LOCALAPPDATA%\Programs\Ukraine Air Defense: UAD.exe, a Start menu shortcut, a desktop shortcut and
; an entry in Settings -> Apps. Run again over an installed game it updates it in place (closing the
; running game first). Worlds and settings live in the game's own folder
; (%APPDATA%\Godot\app_userdata\...) and are never touched, not even by the uninstaller.
; An installation made by the old installer (v1.3.16 - v1.3.18) is taken over: the same folder,
; its uninstaller and its Settings -> Apps entry are removed.
; Silent: UAD_Setup.exe /VERYSILENT [/DIR="folder"] [/TASKS=""] (no desktop shortcut).

#ifndef SrcExe
  #define SrcExe "..\..\build\windows\UAD.exe"
#endif
#ifndef AppVer
  #define AppVer "1.0"
#endif
#ifndef AppVer4
  #define AppVer4 "1.0.0.0"
#endif
#ifndef AppLabel
  #define AppLabel "v" + AppVer
#endif
#define Name "Ukraine Air Defense"
#define OldKey "Software\Microsoft\Windows\CurrentVersion\Uninstall\UkraineAirDefense"

[Setup]
AppId=UkraineAirDefense
AppName={#Name}
AppVersion={#AppVer}
AppVerName={#Name} {#AppLabel}
AppPublisher=Mike Liashenko
AppPublisherURL=https://mikeliashenko.github.io/UAD/
AppSupportURL=https://github.com/MikeLiashenko/UAD/issues
AppUpdatesURL=https://github.com/MikeLiashenko/UAD/releases
AppCopyright=Mike Liashenko
VersionInfoVersion={#AppVer4}
VersionInfoProductName={#Name}
VersionInfoProductTextVersion={#AppLabel}
VersionInfoDescription={#Name} setup
PrivilegesRequired=lowest
DefaultDirName={code:DefaultDir}
DisableProgramGroupPage=yes
DisableReadyPage=yes
UsePreviousAppDir=yes
SetupIconFile=..\..\icon.ico
UninstallDisplayIcon={app}\UAD.exe
UninstallDisplayName={#Name}
WizardStyle=modern
WizardImageFile=wizard_164.bmp,wizard_328.bmp
WizardSmallImageFile=small_55.bmp,small_110.bmp
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=auto
LanguageDetectionMethod=uilanguage

[Languages]
Name: "uk"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SrcExe}"; DestDir: "{app}"; DestName: "UAD.exe"; Flags: ignoreversion

[InstallDelete]
; the old installer's uninstaller
Type: files; Name: "{app}\Uninstall UAD.exe"

[Icons]
Name: "{autoprograms}\{#Name}"; Filename: "{app}\UAD.exe"
Name: "{autodesktop}\{#Name}"; Filename: "{app}\UAD.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\UAD.exe"; Description: "{cm:LaunchProgram,{#Name}}"; Flags: nowait postinstall skipifsilent

[Code]
// The folder of a game the old installer put in, or the usual one.
function DefaultDir(Param: String): String;
var
  Dir: String;
begin
  if RegQueryStringValue(HKCU, '{#OldKey}', 'InstallLocation', Dir) and FileExists(AddBackslash(Dir) + 'UAD.exe') then
    Result := RemoveBackslash(Dir)
  else
    Result := ExpandConstant('{autopf}\{#Name}');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // one entry in Settings -> Apps: ours (UkraineAirDefense_is1), not the old installer's
  if CurStep = ssPostInstall then
    RegDeleteKeyIncludingSubkeys(HKCU, '{#OldKey}');
end;
