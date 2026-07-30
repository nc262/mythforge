; Mythforge-Setup.iss — the one-click installer.
;
; Compile with Inno Setup 6 (free: https://jrsoftware.org/isdl.php):
;     iscc /DClientUrl="https://github.com/<you>/mythforge/releases/download/vX/Mythforge.exe" installer\Mythforge-Setup.iss
; Output: installer\Output\Mythforge-Setup.exe — the single file a friend downloads.
;
; What the friend does: download this one .exe, double-click, click through.
; It lays down the launcher and the setup scripts; a first-run step then fetches
; the game, its models and the image engine for their machine.
;
; Everything heavy — the game (which carries the pre-baked worlds), the ~4.6 GB
; narrator model and the ~6.5 GB art checkpoint — is fetched at first run from
; official sources, so this installer itself stays in the tens of MB.

; NOTE: while the repo is PRIVATE, this URL needs an authenticated fetch — a
; plain download returns 404 for anyone without access. Make the repo public, or
; host the game somewhere the player can reach, before handing the installer to
; a friend. (Everything else it downloads is from public official sources.)
#ifndef ClientUrl
  #define ClientUrl "https://github.com/nc262/mythforge/releases/latest/download/Mythforge.exe"
#endif
#define AppVer "1.0.0"

[Setup]
AppName=Mythforge
AppVersion={#AppVer}
AppPublisher=Mythforge
DefaultDirName={localappdata}\Mythforge
DefaultGroupName=Mythforge
; Per-user install → no admin prompt, and the app dir is writable, which the
; first-run download needs.
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=Mythforge-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\icon.ico

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "setupnow";    Description: "Download & configure everything now (game, models, art engine — needs internet, ~10 GB)"; GroupDescription: "First-time setup:"

[Files]
; The launcher and the setup scripts, and nothing heavy. The Godot project is
; excluded because players get the exported exe, not the source — but its icon
; ships, because the shortcuts point at it.
Source: "..\scripts\*"; DestDir: "{app}\scripts"; Flags: recursesubdirs createallsubdirs
Source: "..\installer\*.ps1"; DestDir: "{app}\installer"
Source: "..\godot\icon.ico"; DestDir: "{app}"
Source: "..\LICENSE"; DestDir: "{app}"
Source: "..\NOTICE"; DestDir: "{app}"
Source: "..\ACKNOWLEDGMENTS.md"; DestDir: "{app}"
Source: "..\README.md"; DestDir: "{app}"

[Icons]
; The single thing a player ever runs. Hidden PowerShell window → the launcher
; starts the art engine if it is there, opens the game, and cleans up on exit.
Name: "{group}\Mythforge"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\installer\mythforge.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\icon.ico"
Name: "{commondesktop}\Mythforge"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\installer\mythforge.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\icon.ico"; Tasks: desktopicon
Name: "{group}\Uninstall Mythforge"; Filename: "{uninstallexe}"

[Run]
; First-run configure. Visible console so the friend sees the ~10 GB download
; progress. Skippable (untick the task) — the first launch does it anyway, since
; the launcher self-heals when the game is not there yet.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\bootstrap.ps1"" -Yes -ReleaseUrl ""{#ClientUrl}"""; \
  WorkingDir: "{app}"; StatusMsg: "Downloading & configuring (game, models, art engine)…"; \
  Flags: shellexec waituntilterminated; Tasks: setupnow
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\installer\mythforge.ps1"""; \
  Description: "Launch Mythforge now"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
; What the app fetched at runtime. NOT the sibling image engine — the player may
; be using it for something else; leave that for them to remove.
Type: files; Name: "{app}\Mythforge.exe"
Type: files; Name: "{app}\launcher.log"
