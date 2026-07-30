# install.ps1 — one-command setup for hosting Mythforge on this machine.
#
# What it does, in order:
#   1. Analyzes your hardware (scripts\check-system.ps1) and picks the right path:
#        nvidia → ComfyUI + CUDA torch      (fully automated)
#        amd    → ComfyUI-ZLUDA             (automated clone + guided finish)
#        none   → text-only game            (skips the image stack)
#   2. Installs prerequisites it can't find: Git, Python 3.11+ (for the art
#      tooling in scripts/ only — the GAME needs neither).
#   4. Pulls the AI models (llama3.1:8b storyteller + llama3.2:3b helper).
#   5. Sets up the image stack for your GPU (optional download: SDXL model ~6.5 GB).
#   6. Leaves you one double-click from playing: play-mythforge.cmd
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
#   flags: -Yes (no prompts)  -SkipImages (text-only even with a good GPU)
param([switch]$Yes, [switch]$SkipImages)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot   # repo root
$sib  = Split-Path -Parent $root           # where ComfyUI lands (sibling dir)
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
  Warn 'This machine is below the comfortable minimum. You can continue, but joining a friend''s server will feel better.'
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

# ── 3. App environment ───────────────────────────────────────────────────────
# NO VENV, NO REQUIREMENTS, NO SERVER. There was a FastAPI backend here — the
# launcher called it "the game's brain" — and it is gone. Every LLM call, the
# save file, campaign memory, the chronicle and speech-to-text run inside the
# game; art goes straight to sd-server. Python survives only for the art tooling
# in scripts/, which a player never runs.
Ok 'No server to set up — the game is the whole application'

# ── 4. AI models (the storytellers) ──────────────────────────────────────────
# The NARRATOR is in-process now (NobodyWho / llama.cpp on Vulkan), so its model
# is a FILE THE GAME OWNS, not a service to talk to. This step used to be three
# `ollama pull`s, which meant every install depended on a background daemon and
# the in-process narrator was effectively dev-only — nothing ever put a .gguf on
# disk, so LocalGM.available() was false and every turn went over HTTP.
#
# Measured on this box, that mattered: 19.3s per turn through Ollama against
# 3.7s in-process (godot/docs/Architecture-InProcess.md).
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

# CAMPAIGN MEMORY is in-process too now (Stage 3). Beats are embedded on the same
# Vulkan device as the narrator and searched with cosine similarity — measured
# 228 ms to store three beats, 4 ms to recall. The beat never leaves the process.
#
# This is a SEPARATE model from the narrator's: LocalMemory matches it by name, so
# the filename must contain "embed"/"minilm"/"nomic"/"bge"/"gte". An 8 GB chat
# model loaded as an encoder would be a slow, silent mistake.
Step 'Downloading the campaign memory encoder (~80 MB)'
$emb = 'nomic-embed-text-v1.5.Q4_K_M.gguf'
$embTarget = Join-Path $modelDir $emb
if (Test-Path $embTarget) {
  Ok "Encoder already present ($emb)"
} else {
  $embUrl = "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/$emb"
  curl.exe -L --fail --retry 5 --retry-delay 3 -C - -o "$embTarget" $embUrl
  if ($LASTEXITCODE -eq 0 -and (Test-Path $embTarget)) { Ok 'Campaign memory ready' }
  else { Warn 'Encoder download failed — recall falls back to the server.' }
}

# VOICE INPUT is in-process too now (NobodyWhoSTT). Push-to-talk used to POST to
# /api/stt/transcribe, a multi-provider endpoint that 503'd without one
# configured — and none ever was, so speaking always answered "no speech provider
# is configured on the server". Matched by name like the encoder.
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

# Ollama is NOT installed any more. It served the backend's studio helpers —
# worldsmith, worldtick, codex, quests, complete_json — and every one of them
# moved into the game. Nothing on this machine speaks to :11434.

# ── 5. Image generation ──────────────────────────────────────────────────────
# ONE path, whatever the card. This used to branch three ways — ComfyUI+CUDA for
# NVIDIA, ComfyUI+ZLUDA for AMD, nothing otherwise — because ComfyUI wants CUDA
# and ZLUDA is a CUDA shim. stable-diffusion.cpp runs on Vulkan, which both
# vendors ship, so the branch collapses: a 36 MB native binary, no Python env,
# no HIP SDK, no kernel compile, no Defender exclusion.
#
# Known regression, deliberately taken: the ComfyUI graph included an InSPyReNet
# matting node, and the World Compiler used its alpha channel to recolour and
# re-treat item art (measured ~100% clean cut-outs against ~60% from asking the
# model for a black background). sd-server has no matting, so composed item
# variants fall back to regenerating rather than recolouring. IP-Adapter
# character references and regional prompting are gone with it.
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
