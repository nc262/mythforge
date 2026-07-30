# install.ps1 — one-command setup for hosting Mythforge on this machine.
#
# What it does, in order:
#   1. Analyzes your hardware (scripts\check-system.ps1) and picks the right path:
#        nvidia → ComfyUI + CUDA torch      (fully automated)
#        amd    → ComfyUI-ZLUDA             (automated clone + guided finish)
#        none   → text-only game            (skips the image stack)
#   2. Installs prerequisites it can't find: Git, Python 3.11+, Ollama (via winget).
#   3. Creates the app venv + installs Python requirements.
#   4. Pulls the AI models (llama3.1:8b storyteller + llama3.2:3b helper).
#   5. Sets up the image stack for your GPU (optional download: SDXL model ~6.5 GB).
#   6. Leaves you one command from playing: .\start-odysseus.ps1
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
Step 'Installing prerequisites (Git, Python, Ollama)'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget not found — update Windows App Installer from the Microsoft Store, then rerun.' }
if (-not (Get-Command git -ErrorAction SilentlyContinue))    { winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements | Out-Null; Ok 'Git installed' } else { Ok 'Git present' }
$py = Get-Command python -ErrorAction SilentlyContinue
$pyOK = $false
if ($py) { $v = (& python --version) -replace 'Python ', ''; $pyOK = [version]$v -ge [version]'3.11.0' }
if (-not $pyOK) { winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements | Out-Null; Ok 'Python 3.12 installed (open a NEW terminal if python is not found below)' } else { Ok "Python present ($v)" }
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) { winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements | Out-Null; Ok 'Ollama installed' } else { Ok 'Ollama present' }

# ── 3. App environment ───────────────────────────────────────────────────────
Step 'Setting up the game server (Python venv + requirements)'
if (-not (Test-Path "$root\venv")) { python -m venv "$root\venv" }
& "$root\venv\Scripts\python.exe" -m pip install --upgrade pip -q
& "$root\venv\Scripts\python.exe" -m pip install -r "$root\requirements.txt" -q
Ok 'App environment ready'
if ((Test-Path "$root\.env.example") -and -not (Test-Path "$root\.env")) { Copy-Item "$root\.env.example" "$root\.env"; Ok '.env created from template' }

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

# Ollama is still used by the SIX studio helpers that have not moved in-process
# yet — worldsmith, worldtick, codex, quests, complete_json and campaign memory
# all still POST to the backend (see Backlog "the Odysseus carcass"). The small
# model and the embedder serve those, not the narrator.
Step 'Pulling the helper models (quests, codex, campaign memory)'
try { Start-Process ollama -ArgumentList 'serve' -WindowStyle Hidden -ErrorAction SilentlyContinue; Start-Sleep 3 } catch {}
ollama pull llama3.2:3b     # fast helper (quests, codex, worldsmith)
ollama pull all-minilm      # ~45 MB — embeddings for pinpoint campaign memory
Ok 'Helper models ready'

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
Write-Host '    1.  .\start-odysseus.ps1          (the game server → http://localhost:7000)'
if ($imagePath -ne 'none') {
  Write-Host '    2.  pwsh scripts\start-image-sdcpp.ps1   (the art engine — optional but pretty)'
}
Write-Host '    3.  Open http://localhost:7000, create your account, press New Adventure.'
Write-Host ''
Write-Host '  Hosting for friends? Install Tailscale (https://tailscale.com), invite them,' -ForegroundColor DarkGray
Write-Host '  and share http://<your-tailscale-name>:7000 — they only need a browser.' -ForegroundColor DarkGray
