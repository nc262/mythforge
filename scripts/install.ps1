# install.ps1 — one-command setup for playing Mythforge on this machine.
#
# The game is the whole application: there is no server to install, no daemon to
# start and no account to make. All this does is put the files the game needs
# where it looks for them.
#
#   1. Reads the hardware (scripts\check-system.ps1).
#   2. Installs Git and Python 3.11+ if missing — for the tooling in scripts/,
#      which a player never runs. The GAME needs neither.
#   3. Fetches the NobodyWho GDExtension (the model runtime, ~145 MB).
#   4. Downloads the three models into user://models: the narrator (~4.6 GB),
#      the memory encoder (~80 MB) and the voice model (~75 MB).
#   5. Installs stable-diffusion.cpp and, if you want it, its checkpoint.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
#   flags: -Yes (no prompts)  -SkipImages (skip the art engine entirely)
param([switch]$Yes, [switch]$SkipImages)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot   # repo root
$sib  = Split-Path -Parent $root           # where the image engine lands (sibling dir)
Set-Location $root

function Step($m) { Write-Host "`n▸ $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  ✔ $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ⚠ $m" -ForegroundColor Yellow }
function Ask($q)  { if ($Yes) { return $true } (Read-Host "$q [y/N]") -match '^[yY]' }

# ── 1. Know the machine ──────────────────────────────────────────────────────
Step 'Checking your hardware'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-system.ps1')
$sys = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-system.ps1') -Json) | ConvertFrom-Json
if (-not $sys.textOK) {
  Warn 'This machine is below the comfortable minimum. It will run; turns will be slow.'
  if (-not (Ask 'Continue anyway?')) { exit 1 }
}
$imagePath = if ($SkipImages) { 'none' } else { $sys.imagePath }

# ── 2. Prerequisites ─────────────────────────────────────────────────────────
Step 'Installing prerequisites (Git, Python)'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget not found — update Windows App Installer from the Microsoft Store, then rerun.' }
if (-not (Get-Command git -ErrorAction SilentlyContinue))    { winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements | Out-Null; Ok 'Git installed' } else { Ok 'Git present' }
$py = Get-Command python -ErrorAction SilentlyContinue
$pyOK = $false
if ($py) { $v = (& python --version) -replace 'Python ', ''; $pyOK = [version]$v -ge [version]'3.11.0' }
if (-not $pyOK) { winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements | Out-Null; Ok 'Python 3.12 installed (open a NEW terminal if python is not found below)' } else { Ok "Python present ($v)" }

# ── 3. The model runtime ─────────────────────────────────────────────────────
# NobodyWho is a GDExtension: llama.cpp inside the game's own process, on Vulkan.
# Its binary is over GitHub's per-file limit and therefore gitignored, so a
# source checkout has the manifest but not the DLL — without this step the game
# opens and honestly reports that it has no narrator.
Step 'Fetching the model runtime (NobodyWho, ~145 MB)'
$nwDir = Join-Path $root 'godot\addons\nobodywho'
if (Get-ChildItem $nwDir -Filter *.dll -ErrorAction SilentlyContinue) {
  Ok 'Model runtime already present'
} else {
  python (Join-Path $PSScriptRoot 'fetch_nobodywho.py')
  if (Get-ChildItem $nwDir -Filter *.dll -ErrorAction SilentlyContinue) { Ok 'Model runtime installed' }
  else { Warn 'Model runtime did not install — the game will say it has no narrator.' }
}

# ── 4. The models ────────────────────────────────────────────────────────────
# Three files in one folder, matched BY NAME: the narrator is whatever is not an
# encoder or a whisper model, and both of those are found by filename hints. An
# 80 MB encoder loaded as the narrator would answer, badly, forever — exactly
# the kind of failure that never announces itself.
Step 'Downloading the Game Master (~4.6 GB — go get a coffee)'
$gguf = 'Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf'
$modelDir = Join-Path $env:APPDATA 'Godot\app_userdata\Mythforge\models'
New-Item -ItemType Directory -Force $modelDir | Out-Null
$target = Join-Path $modelDir $gguf
if (Test-Path $target) {
  Ok "Game Master already present ($gguf)"
} else {
  # Resumable, because a 4.6 GB download over a bad line should not start over.
  $url = "https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/$gguf"
  curl.exe -L --fail --retry 5 --retry-delay 3 -C - -o "$target" $url
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $target)) {
    Warn "Model download failed. The game will say so on the first turn."
    Warn "  Drop any .gguf into $modelDir and restart."
  } else {
    Ok "Game Master ready ($([math]::Round((Get-Item $target).Length/1GB,1)) GB)"
  }
}

# CAMPAIGN MEMORY embeds beats on the same Vulkan device as the narrator and
# searches them with cosine similarity — 228 ms to store three, 4 ms to recall.
# The filename must contain "embed"/"minilm"/"nomic"/"bge"/"gte".
Step 'Downloading the campaign memory encoder (~80 MB)'
$emb = 'nomic-embed-text-v1.5.Q4_K_M.gguf'
$embTarget = Join-Path $modelDir $emb
if (Test-Path $embTarget) {
  Ok "Encoder already present ($emb)"
} else {
  $embUrl = "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/$emb"
  curl.exe -L --fail --retry 5 --retry-delay 3 -C - -o "$embTarget" $embUrl
  if ($LASTEXITCODE -eq 0 -and (Test-Path $embTarget)) { Ok 'Campaign memory ready' }
  else { Warn 'Encoder download failed — recall returns nothing rather than guessing.' }
}

# VOICE INPUT (NobodyWhoSTT) wants its own whisper GGUF, matched by name for the
# same reason the encoder is.
Step 'Downloading the voice model (~75 MB)'
$stt = 'ggml-base.en.bin'
$sttTarget = Join-Path $modelDir $stt
if (Test-Path $sttTarget) {
  Ok "Voice model already present ($stt)"
} else {
  $sttUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$stt"
  curl.exe -L --fail --retry 5 --retry-delay 3 -C - -o "$sttTarget" $sttUrl
  if ($LASTEXITCODE -eq 0 -and (Test-Path $sttTarget)) { Ok 'Voice input ready' }
  else { Warn 'Voice model download failed — push-to-talk will say so; typing still works.' }
}

# ── 5. Image generation ──────────────────────────────────────────────────────
# ONE path, whatever the card: stable-diffusion.cpp on Vulkan. A 36 MB native
# binary, no Python env, no vendor SDK, no kernel compile. It serves the OpenAI
# image API itself, so the game POSTs to it directly.
#
# Known limits, deliberately accepted: no matting, no regional prompting, no
# character-reference adapters, and one checkpoint per launch. Item art has to
# be readable as painted, which is why every item prompt asks for a plain flat
# background.
if ($imagePath -eq 'none') {
  Step 'Art generation skipped — configuring text-only'
  Warn 'The full game works (story, combat, worlds, lorebook); the shipped worlds carry pre-baked art.'
} else {
  Step 'Installing the image engine (stable-diffusion.cpp, Vulkan)'
  $sdcpp = Join-Path $sib 'stable-diffusion.cpp'
  python (Join-Path $PSScriptRoot 'fetch_sdcpp.py') --dest $sdcpp
  if (Test-Path (Join-Path $sdcpp 'sd-server.exe')) { Ok 'Image engine installed (~106 MB)' }
  else { Warn 'Image engine did not install — the game still plays with pre-baked art.' }

  $ckptDir = Join-Path $sdcpp 'models'
  New-Item -ItemType Directory -Force $ckptDir | Out-Null
  $ckpt = Join-Path $ckptDir 'DreamShaperXL_Turbo_v2_1.safetensors'
  if (-not (Test-Path $ckpt) -and (Ask 'Download the SDXL art model now (~6.5 GB)?')) {
    Step 'Downloading DreamShaperXL Turbo (CC-friendly SDXL checkpoint)'
    curl.exe -L -o $ckpt 'https://huggingface.co/Lykon/dreamshaper-xl-v2-turbo/resolve/main/DreamShaperXL_Turbo_v2_1.safetensors'
    Ok 'Art model ready'
  }
}

# ── 6. Done ──────────────────────────────────────────────────────────────────
Step 'Install complete'
Write-Host ''
Write-Host '  To play:' -ForegroundColor Yellow
Write-Host '    1.  play-mythforge.cmd            (the game — that is the whole application)'
if ($imagePath -ne 'none') {
  Write-Host '    2.  pwsh scripts\start-image-sdcpp.ps1   (the art engine — optional but pretty)'
}
Write-Host ''
Write-Host '  No account, no server, no browser: it opens straight into the Hall.' -ForegroundColor DarkGray
