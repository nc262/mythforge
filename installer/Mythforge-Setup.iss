; Mythforge-Setup.iss — the one-click installer.
;
; Compile with Inno Setup 6 (free: https://jrsoftware.org/isdl.php):
;     iscc /DClientUrl="https://github.com/<you>/mythforge/releases/download/vX/Mythforge.exe" installer\Mythforge-Setup.iss
; Output: installer\Output\Mythforge-Setup.exe — the single file a friend downloads.
;
; What the friend does: download this one .exe, double-click, click through.
; The installer lays down the lean backend, then a first-run step downloads and
; configures Ollama + models + ComfyUI + the game client FOR THEIR machine
; (GPU auto-detected). Nothing else to install by hand.
;
; Everything heavy (the game client, the LLM model, the SDXL checkpoint) is
; fetched at first run from official sources / your GitHub release — so this
; installer itself stays small (tens of MB) and well under any asset-size cap.

#ifndef ClientUrl
  #define ClientUrl "https://github.com/YOURNAME/mythforge/releases/latest/download/Mythforge.exe"
#endif
#define AppVer "1.0.0"

[Setup]
AppName=Mythforge
AppVersion={#AppVer}
AppPublisher=Mythforge
DefaultDirName={localappdata}\Mythforge
DefaultGroupName=Mythforge
; Per-user install → no admin prompt, and the app dir is writable (venv, data,
; downloaded client all live here).
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=Mythforge-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The client is fetched at first run, so the installer footprint is the backend.
UninstallDisplayIcon={app}\godot\icon.ico

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "setupnow";    Description: "Download & configure everything now (Ollama, ComfyUI, models, game — needs internet, ~10 GB)"; GroupDescription: "First-time setup:"

[Files]
; The lean backend + the launcher/bootstrap scripts. Everything the game's brain
; needs; NONE of the multi-GB artifacts (those are fetched at first run).
Source: "..\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs; \
  Excludes: "\.git\*,\godot\*,\dist\*,\venv\*,\data\*,\node_modules\*,\.claude\*,\baked\*,*.zip,*.pyc,__pycache__\*,\installer\Output\*"

[Icons]
; The single thing a player ever runs. Hidden PowerShell window → the launcher
; brings up the services and the game, and tears them down on exit.
Name: "{group}\Mythforge"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\installer\mythforge.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\godot\icon.ico"
Name: "{commondesktop}\Mythforge"; Filename: "powershell.exe"; \
  Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\installer\mythforge.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\godot\icon.ico"; Tasks: desktopicon
Name: "{group}\Uninstall Mythforge"; Filename: "{uninstallexe}"

[Run]
; First-run configure. Visible console so the friend sees the ~10 GB download
; progress. Skippable (untick the task) — the first game launch will do it
; anyway, since the launcher self-heals when unconfigured.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\bootstrap.ps1"" -Yes -ReleaseUrl ""{#ClientUrl}"""; \
  WorkingDir: "{app}"; StatusMsg: "Downloading & configuring (Ollama, ComfyUI, models, game)…"; \
  Flags: shellexec waituntilterminated; Tasks: setupnow
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\installer\mythforge.ps1"""; \
  Description: "Launch Mythforge now"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
; Clean up what the app created at runtime (but not a sibling ComfyUI, which the
; friend may share with other tools — leave that for them to remove).
Type: filesandordirs; Name: "{app}\venv"
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\Mythforge.exe"
