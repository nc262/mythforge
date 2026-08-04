# bootstrap.ps1 — first-run "download and configure everything" step.
#
# Run once by the installer right after it lays down the app source. It reuses
# the project's own installer for the hard parts (GPU detection, the narrator /
# encoder / voice models, the image engine) and adds the Godot game client.
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

# Make a just-installed Python visible without opening a new terminal — the one
# wrinkle in the underlying installer's "new terminal" note.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

# 1. Models and the image engine, via the project's own installer. Detects the
#    GPU, downloads the narrator (~4.6 GB), the memory encoder and the voice
#    model, and installs stable-diffusion.cpp + a checkpoint.
Step 'Setting up the engine (GPU, models, image engine)'
$install = Join-Path $Root 'scripts\install.ps1'
if (-not (Test-Path $install)) { throw "scripts\install.ps1 missing — the install payload is incomplete." }
$installArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $install)
if ($Yes) { $installArgs += '-Yes' }
& powershell @installArgs
if ($LASTEXITCODE -ne 0) { throw "engine setup failed (exit $LASTEXITCODE) — see output above." }

# 2. The game itself — now a ~130 MB executable, because the worlds ship BESIDE
#    it rather than inside it (a bundled build was 3.02 GB, over GitHub's 2 GiB
#    asset cap). Which means step 3 is no longer optional: an exe on its own is
#    a game with nothing to play, and it looks completely normal until you click
#    New Adventure.
Step 'Downloading the game'
$client = Join-Path $Root 'Mythforge.exe'
if (Test-Path $client) {
    Write-Host "  already present ($([math]::Round((Get-Item $client).Length/1MB)) MB) — skipping"
} elseif (-not $ReleaseUrl) {
    Write-Warning "  no client URL given. Set -ReleaseUrl or `$env:MYTHFORGE_CLIENT_URL to the"
    Write-Warning "  Mythforge.exe release asset, then re-run this bootstrap."
} else {
    Write-Host "  from $ReleaseUrl"
    curl.exe -L --fail -o "$client.part" $ReleaseUrl
    if ($LASTEXITCODE -ne 0) { throw "client download failed." }
    Move-Item "$client.part" $client -Force
    Write-Host "  game ready ($([math]::Round((Get-Item $client).Length/1MB)) MB)"
}

# 3. THE WORLDS. Six ~500 MB packages, fetched from the same release as the exe
#    and dropped in `baked/` beside it. Resumable, because ~2.9 GB over a bad
#    line should not start over, and skipped individually if already present so
#    a re-run repairs one world rather than re-fetching all six.
Step 'Downloading the worlds (~2.9 GB)'
$worlds = @('embervale', 'neonspire', 'everyday', 'saltmarsh', 'fimbulreach', 'brasshaven')
$bakedDir = Join-Path $Root 'baked'
New-Item -ItemType Directory -Force $bakedDir | Out-Null
$base = if ($ReleaseUrl) { Split-Path $ReleaseUrl -Parent } else { '' }
$missing = @()
foreach ($w in $worlds) {
    $zip = Join-Path $bakedDir "$w.zip"
    if (Test-Path $zip) { Write-Host "  $w — already present"; continue }
    if (-not $base) { $missing += $w; continue }
    # Split-Path mangles the scheme's double slash; rebuild the URL by name.
    $url = ($ReleaseUrl -replace '/[^/]+$', "/$w.zip")
    Write-Host "  $w …"
    curl.exe -L --fail --retry 5 --retry-delay 3 -C - -o "$zip.part" $url
    if ($LASTEXITCODE -ne 0) { $missing += $w; continue }
    Move-Item "$zip.part" $zip -Force
}
if ($missing.Count -gt 0) {
    Write-Warning "  could not fetch: $($missing -join ', ')"
    Write-Warning "  download those .zip files from the release into: $bakedDir"
}

# 4. PROVE IT. An exe that finds no worlds boots, draws its menu, and offers an
#    empty New Adventure — the failure is invisible until someone plays. This is
#    the one check that catches it, so the installer runs it rather than hoping.
if (Test-Path $client) {
    Step 'Checking the game can see its worlds'
    & $client --headless --mf-worlds
    if ($LASTEXITCODE -ne 0) {
        Write-Warning '  the game found no playable worlds — see the list above.'
        Write-Warning "  Put the six .zip files in $bakedDir and run this again."
    }
}

Step 'Done'
Write-Host '  Launch from the Start Menu shortcut, or run installer\mythforge.ps1.' -ForegroundColor Green
