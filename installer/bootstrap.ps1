# bootstrap.ps1 — first-run "download and configure everything" step.
#
# Run once by the installer right after it lays down the app source. It reuses
# the project's existing, proven installer for the hard parts (GPU detection,
# Ollama + models, ComfyUI on the right backend for THIS machine, the app venv)
# and adds only what the desktop edition needs on top: the Godot game client.
#
# Everything here is idempotent — safe to re-run as a "repair".
#
#   powershell -ExecutionPolicy Bypass -File .\installer\bootstrap.ps1
#   -ReleaseUrl <url>   the Mythforge.exe game-client download (GitHub release asset)
#   -Yes                no prompts (installer passes this)
param(
    [string]$ReleaseUrl = $env:MYTHFORGE_CLIENT_URL,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot     # install dir = app source root
Set-Location $Root
function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

# Make a just-installed Python/Ollama visible without opening a new terminal —
# the one wrinkle in the underlying installer's "new terminal" note.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

# 1. The whole server-side stack, via the project's own installer. Detects the
#    GPU and takes the CUDA / ZLUDA / text-only path automatically; installs
#    Ollama + pulls the models; builds the app venv; sets up ComfyUI + SDXL.
Step 'Setting up the engine (GPU, Ollama, ComfyUI, models)'
$install = Join-Path $Root 'scripts\install.ps1'
if (-not (Test-Path $install)) { throw "scripts\install.ps1 missing — the install payload is incomplete." }
$installArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $install)
if ($Yes) { $installArgs += '-Yes' }
& powershell @installArgs
if ($LASTEXITCODE -ne 0) { throw "engine setup failed (exit $LASTEXITCODE) — see output above." }

# 2. The desktop game client — the one thing the server installer doesn't know
#    about. Ships with every world pre-baked, so it's the largest single file.
Step 'Downloading the game'
$client = Join-Path $Root 'Mythforge.exe'
if (Test-Path $client) {
    Write-Host "  already present ($([math]::Round((Get-Item $client).Length/1GB,2)) GB) — skipping"
} elseif (-not $ReleaseUrl) {
    Write-Warning "  no client URL given. Set -ReleaseUrl or `$env:MYTHFORGE_CLIENT_URL to the"
    Write-Warning "  Mythforge.exe release asset, then re-run this bootstrap."
} else {
    Write-Host "  from $ReleaseUrl"
    curl.exe -L --fail -o "$client.part" $ReleaseUrl
    if ($LASTEXITCODE -ne 0) { throw "client download failed." }
    Move-Item "$client.part" $client -Force
    Write-Host "  game ready ($([math]::Round((Get-Item $client).Length/1GB,2)) GB)"
}

Step 'Done'
Write-Host '  Launch from the Start Menu shortcut, or run installer\mythforge.ps1.' -ForegroundColor Green
