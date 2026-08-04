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
; Everything heavy — the ~131 MB game, its six ~500 MB world packages, the
; ~4.6 GB narrator model and the ~6.5 GB art checkpoint — is fetched at first
; run from official sources, so this installer itself stays in the tens of MB.
;
; The worlds are SEPARATE downloads that land in {app}\baked, not cargo inside
; the exe. A bundled build was 3.02 GB, over GitHub's 2 GiB asset cap.

; Compiles with Inno Setup 6 or 7 — nothing here uses a 7-only directive.
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
; Excludes __pycache__: `recursesubdirs` otherwise sweeps compiled bytecode from
; whatever this dev box last ran into the installer a stranger downloads.
Source: "..\scripts\*"; DestDir: "{app}\scripts"; Flags: recursesubdirs createallsubdirs; Excludes: "__pycache__,*.pyc"
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
; {autodesktop}, not {commondesktop}: the all-users desktop needs admin, and this
; is a PrivilegesRequired=lowest install. {auto*} resolves to the per-user
; location when not elevated, which is the only one we can actually write.
Name: "{autodesktop}\Mythforge"; Filename: "powershell.exe"; \
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
; What the app fetched at runtime. Inno only removes what it installed itself, so
; every first-run download has to be named here or it is orphaned — the worlds
; alone are ~2.9 GB, which is a rude thing to leave on someone's disk.
; NOT the sibling image engine, and NOT the models under {userappdata}\Godot —
; the player may be using either for something else; leave those for them.
Type: files;          Name: "{app}\Mythforge.exe"
Type: files;          Name: "{app}\launcher.log"
Type: filesandordirs; Name: "{app}\baked"
