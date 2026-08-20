<#
.SYNOPSIS
  Start the image engine: stable-diffusion.cpp on Vulkan.

.DESCRIPTION
  One native binary, one checkpoint, no Python. It serves the OpenAI image API
  directly on /v1/images/generations, so the game POSTs to it with no proxy in
  between.

  Idempotent: if something is already listening on the port, this returns.

.PARAMETER Exe
  sd-server.exe. Left unset it is found where scripts/fetch_sdcpp.py installs
  it — a sibling of the repo — which is also where install.ps1 puts it.

.PARAMETER Checkpoint
  An SDXL .safetensors. Left unset, the first of the known model folders that
  has one wins — install.ps1 downloads into the engine's own models/ directory,
  but a machine that already keeps a model library elsewhere should not have to
  download 6.5 GB twice.

.NOTES
  EVERY PATH HERE IS DERIVED, never hardcoded. This script used to default to
  one developer's home directory, so on any other machine it threw
  "sd-server not found" before doing anything — and it is the script the docs,
  the launcher and the README all tell a player to run.
#>
param(
  [string]$Exe        = "",
  [string]$Checkpoint = "",
  [int]$Port          = 8189,
  # Circular padding on both axes — what makes a texture actually tile. It is a
  # LAUNCH flag, not a request field, so a material pour needs its own server on
  # its own port: `-Port 8190 -Circular`. Off for the game, which wants pictures
  # with edges, not wallpaper.
  [switch]$Circular,
  # Where to record the PID of the engine THIS invocation starts. The game reads
  # it so it can stop the engine it spawned and never one the player was already
  # running (Services.gd). Nothing is written when the port was already live,
  # which is precisely how "we did not start it" is communicated.
  [string]$PidFile    = "",
  # The process whose death the engine should not outlive. The game passes its
  # own pid; a watchdog then waits on THAT and stops the engine when it goes,
  # however it went - clean quit, hard crash, or Task Manager. Left unset there
  # is no watchdog and the engine outlives everything, which is the right
  # behaviour for a developer starting one by hand.
  [int]$ParentPid     = 0
)

# <repo>/scripts/this.ps1 → <repo> → its parent, where fetch_sdcpp.py installs.
$repo = Split-Path -Parent $PSScriptRoot
$sib  = Split-Path -Parent $repo

if (-not $Exe) {
  $hunt = @(
    (Join-Path $sib 'stable-diffusion.cpp\sd-server.exe'),
    (Join-Path $repo 'stable-diffusion.cpp\sd-server.exe')
  )
  # SDCPP_DIR is the same override fetch_sdcpp.py honours. Guarded, because
  # Join-Path throws on a null path and an unset variable is the normal case.
  if ($env:SDCPP_DIR) { $hunt += (Join-Path $env:SDCPP_DIR 'sd-server.exe') }
  # A git WORKTREE sits two levels under the real checkout, so the sibling of
  # `$repo` is not the sibling of the clone. Walk up a few parents and try the
  # same layout — correct for a normal clone, and still right from a worktree.
  $up = $repo
  for ($i = 0; $i -lt 4 -and $up; $i++) {
    $up = Split-Path -Parent $up
    if ($up) { $hunt += (Join-Path $up 'stable-diffusion.cpp\sd-server.exe') }
  }
  foreach ($cand in $hunt) {
    if ($cand -and (Test-Path $cand)) { $Exe = $cand; break }
  }
}
if (-not $Exe -or -not (Test-Path $Exe)) {
  throw "sd-server not found. Run: python scripts/fetch_sdcpp.py   (or pass -Exe)"
}

if (-not $Checkpoint) {
  # The engine's own models/ first — that is where install.ps1 downloads to.
  # A pre-existing library is honoured through SD_MODEL_DIR so nobody
  # re-downloads 6.5 GB they already have, and so the path to somebody's
  # personal collection lives in their environment instead of in this file.
  $candidates = @()
  if ($env:SD_MODEL_DIR) { $candidates += $env:SD_MODEL_DIR }
  $candidates += @(
    (Join-Path (Split-Path $Exe -Parent) 'models'),
    (Join-Path $repo 'models'),
    (Join-Path $sib 'models')
  )
  # A SHARED LIBRARY NEXT DOOR. Nobody keeps 7 GB checkpoints twice, so on a box
  # that already runs ComfyUI or A1111 the model is in that tool's library and
  # nowhere this script used to look. SD_MODEL_DIR exists for exactly this and
  # has to be SET by someone - here that someone was a pm2 config carrying the
  # path, and when the pm2 stack was removed the checkpoint went with it while
  # the file sat untouched on disk. Find the library instead of being told about
  # it: every directory beside the checkout, and the same walk up the parents the
  # exe hunt does, looking for the layout these tools all share.
  $libRoots = @($sib)
  $upLib = $repo
  for ($i = 0; $i -lt 4 -and $upLib; $i++) {
    $upLib = Split-Path -Parent $upLib
    if ($upLib) { $libRoots += $upLib }
  }
  foreach ($root in ($libRoots | Select-Object -Unique)) {
    if (-not (Test-Path $root)) { continue }
    foreach ($peer in (Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)) {
      $candidates += @(
        (Join-Path $peer.FullName 'models\checkpoints'),   # ComfyUI
        (Join-Path $peer.FullName 'models\Stable-diffusion') # A1111
      )
    }
  }
  # PREFER THE CHECKPOINT THIS GAME WAS TUNED FOR. Sorting by name and taking
  # the first picked whatever sorted earliest — on a machine with a shared model
  # library that was an anime checkpoint, which would have restyled every item,
  # portrait and backdrop in the game without erroring once.
  $prefer = @('dreamshaper', 'juggernaut')
  foreach ($dir in $candidates) {
    if (-not $dir -or -not (Test-Path $dir)) { continue }
    $all = @(Get-ChildItem $dir -Filter *.safetensors -ErrorAction SilentlyContinue | Sort-Object Name)
    if (-not $all) { continue }
    $pick = $null
    foreach ($want in $prefer) {
      $pick = $all | Where-Object { $_.Name -match $want } | Select-Object -First 1
      if ($pick) { break }
    }
    if (-not $pick) { $pick = $all[0] }
    $Checkpoint = $pick.FullName
    break
  }
}
if (-not $Checkpoint -or -not (Test-Path $Checkpoint)) {
  throw "no .safetensors checkpoint found. Pass -Checkpoint, or run scripts/install.ps1 to fetch one."
}

if (-not $PidFile) { $PidFile = Join-Path $env:TEMP "mythforge-sd-$Port.pid" }
# A stale file from a previous run must never be mistaken for this one's child.
Remove-Item $PidFile -ErrorAction SilentlyContinue

$live = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($live) { Write-Host "already listening on :$Port" -ForegroundColor Green; return }

# Per-port, so a pour server on :8190 does not truncate the game server's log.
$log = Join-Path $env:TEMP "sd-server-$Port.log"
Remove-Item $log, "$log.err" -ErrorAction SilentlyContinue

# --diffusion-fa: flash attention in the diffusion model. Measured on an RX 7900
#   GRE this is the difference between comfortable and tight VRAM at SDXL 1024.
# --vae-tiling: do NOT drop this. Untiled, decoding a single 1024x1024 latent
#   asks for one Vulkan buffer past this device's limit, ggml logs "Failed to
#   allocate pinned memory ... ErrorOutOfDeviceMemory" and falls back to a slow
#   path: decode alone was 36.2s of a 50.4s image. Tiled it is 3.1s, for a
#   pixel-identical result at the same seed. 50.4s -> 19.9s per image.
$sdArgs = @("-m","`"$Checkpoint`"","--listen-port","$Port","--diffusion-fa","--vae-tiling")
if ($Circular) { $sdArgs += "--circular" }
$proc = Start-Process -FilePath $Exe -WindowStyle Minimized -PassThru `
  -ArgumentList $sdArgs `
  -RedirectStandardOutput $log -RedirectStandardError "$log.err"
# Written only on the path that actually spawned something, so the presence of
# this file IS the claim "this engine is ours to stop".
Set-Content -Path $PidFile -Value $proc.Id -Encoding ascii

# THE ENGINE MUST NOT OUTLIVE THE GAME, and a notification handler inside the
# game cannot promise that: the one failure that strands a 6.5 GB process is the
# one where the game never gets to run any code - llama.cpp aborting the process
# (seen: 0xC0000409), or the player reaching for Task Manager. So the guarantee
# lives OUTSIDE the game, in a detached watchdog that waits on the game's pid and
# stops the engine when it stops existing, by whatever means.
#
# On Windows the airtight version of this is a Job Object with
# JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, which the OS enforces even if every process
# involved is killed. Godot exposes no way to create one and PowerShell needs
# P/Invoke for it, so this is the 95 %: everything except someone killing the
# watchdog itself.
if ($ParentPid -gt 0) {
  $watch = "while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }; " +
           "Stop-Process -Id $($proc.Id) -Force -ErrorAction SilentlyContinue; " +
           "Remove-Item '$PidFile' -ErrorAction SilentlyContinue"
  Start-Process powershell -WindowStyle Hidden `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $watch) | Out-Null
  Write-Host "watchdog: the engine will stop when pid $ParentPid does" -ForegroundColor DarkGray
}

Write-Host "loading $(Split-Path $Checkpoint -Leaf) (~6.5 GB)..." -ForegroundColor Cyan
foreach ($i in 1..40) {
  Start-Sleep -Seconds 3
  if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    Write-Host "image engine up on http://127.0.0.1:$Port" -ForegroundColor Green
    return
  }
}
Write-Warning "did not come up in 2 minutes - check $log"
