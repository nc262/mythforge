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
Step 'Pulling the AI models (~7 GB — go get a coffee)'
try { Start-Process ollama -ArgumentList 'serve' -WindowStyle Hidden -ErrorAction SilentlyContinue; Start-Sleep 3 } catch {}
ollama pull llama3.1:8b     # the Game Master's voice
ollama pull llama3.2:3b     # fast helper (quests, codex, worldsmith)
ollama pull all-minilm      # ~45 MB — embeddings for pinpoint campaign memory
Ok 'Models ready'

# ── 5. Image generation (per GPU) ────────────────────────────────────────────
# Custom nodes the art pipeline REQUIRES — not optional extras.
#   InSPyReNet Rembg (matting). The World Compiler composes item art: material
#   recolour, rarity treatments, per-region materials. Every one of those needs
#   a real alpha channel. Measured: asking the model for "a plain black
#   background" yields a usable cut-out only ~60% of the time; a matting model
#   is ~100%. Without this, loot can only be regenerated, never varied.
function Install-MythforgeComfyNodes([string]$comfyDir, [string]$py) {
  $nodes = Join-Path $comfyDir 'custom_nodes'
  New-Item -ItemType Directory -Force $nodes | Out-Null
  $rembg = Join-Path $nodes 'ComfyUI-Inspyrenet-Rembg'
  if (-not (Test-Path $rembg)) {
    Step 'Installing the matting node (InSPyReNet — clean cut-outs for item art)'
    git clone --depth 1 https://github.com/john-mnz/ComfyUI-Inspyrenet-Rembg $rembg
  }
  if (Test-Path $py) {
    & $py -m pip install "transparent-background>=1.2.4" -q
    Ok 'Matting node ready — item art can be recoloured and re-treated'
  } else {
    Warn "ComfyUI python not found at $py"
    Warn "  finish with: `"$py`" -m pip install transparent-background"
  }
}

switch ($imagePath) {
  'comfyui-cuda' {
    Step 'NVIDIA path: installing ComfyUI + CUDA'
    $comfy = Join-Path $sib 'ComfyUI'
    if (-not (Test-Path $comfy)) { git clone --depth 1 https://github.com/comfyanonymous/ComfyUI $comfy }
    if (-not (Test-Path "$comfy\venv")) { python -m venv "$comfy\venv" }
    & "$comfy\venv\Scripts\python.exe" -m pip install --upgrade pip -q
    & "$comfy\venv\Scripts\python.exe" -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124 -q
    & "$comfy\venv\Scripts\python.exe" -m pip install -r "$comfy\requirements.txt" -q
    Ok 'ComfyUI (CUDA) installed'
    Install-MythforgeComfyNodes $comfy "$comfy\venv\Scripts\python.exe"
    $ckptDir = Join-Path $comfy 'models\checkpoints'
    New-Item -ItemType Directory -Force $ckptDir | Out-Null
    $ckpt = Join-Path $ckptDir 'DreamShaperXL_Turbo_v2_1.safetensors'
    if (-not (Test-Path $ckpt) -and (Ask 'Download the SDXL art model now (~6.5 GB)?')) {
      Step 'Downloading DreamShaperXL Turbo (CC-friendly SDXL checkpoint)'
      curl.exe -L -o $ckpt 'https://huggingface.co/Lykon/dreamshaper-xl-v2-turbo/resolve/main/DreamShaperXL_Turbo_v2_1.safetensors'
      Ok 'Art model ready'
    }
  }
  'comfyui-zluda' {
    Step 'AMD path: installing ComfyUI-ZLUDA (guided)'
    $comfy = Join-Path $sib 'ComfyUI-Zluda'
    if (-not (Test-Path $comfy)) { git clone --depth 1 https://github.com/patientx/ComfyUI-Zluda $comfy }
    Ok 'ComfyUI-Zluda cloned'
    Warn 'AMD needs two manual steps (once):'
    Write-Host '    1. Install the AMD HIP SDK: https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html'
    Write-Host "    2. Run $comfy\install.bat, then (as admin) this repo's scripts\fix-zluda-elevated.ps1"
    Write-Host '    First image generation compiles kernels — expect ~10 quiet minutes.'
    Write-Host '    Then drop an SDXL checkpoint (e.g. DreamShaperXL_Turbo_v2_1.safetensors) into models\checkpoints.'
    # The venv only exists after install.bat, so add the node if it's there and
    # leave a clear instruction if it isn't yet.
    $zpy = Join-Path $comfy 'venv\Scripts\python.exe'
    if (Test-Path $zpy) {
      Install-MythforgeComfyNodes $comfy $zpy
    } else {
      Warn '    3. After install.bat, re-run this installer (or scripts\install-comfy-nodes.ps1)'
      Write-Host '       to add the matting node the item-art pipeline needs.'
    }
  }
  default {
    Step 'No capable GPU — configuring text-only'
    Warn 'The full game works (story, combat, worlds, lorebook); generated art is disabled on this machine.'
  }
}

# ── 6. Done ──────────────────────────────────────────────────────────────────
Step 'Install complete'
Write-Host ''
Write-Host '  To play:' -ForegroundColor Yellow
Write-Host '    1.  .\start-odysseus.ps1          (the game server → http://localhost:7000)'
if ($imagePath -ne 'none') {
  Write-Host '    2.  .\start-image-stack.cmd       (the art engine — optional but pretty)'
}
Write-Host '    3.  Open http://localhost:7000, create your account, press New Adventure.'
Write-Host ''
Write-Host '  Hosting for friends? Install Tailscale (https://tailscale.com), invite them,' -ForegroundColor DarkGray
Write-Host '  and share http://<your-tailscale-name>:7000 — they only need a browser.' -ForegroundColor DarkGray
