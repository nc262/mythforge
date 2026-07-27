# mythforge.ps1 — the one launcher a player ever runs.
#
# Brings up EVERYTHING the desktop game needs, in the right order, on private
# loopback ports, then launches the game and tears it all down on exit. The
# player double-clicks the Start-Menu shortcut; they never see or manage a
# service. This is the whole of "nothing on localhost you deal with — it's all
# internal to the game".
#
#   backend  : uvicorn app:app            → 127.0.0.1:7000   (the game's brain)
#   llm      : ollama serve               → 127.0.0.1:11434  (the Game Master)
#   image    : ComfyUI + bridge           → 127.0.0.1:8101   (optional; art)
#   client   : Mythforge.exe (Godot)      → talks to :7000
#
# The image stack is best-effort: pre-baked worlds ship all their art, so the
# game is fully playable if ComfyUI never comes up (a player with no GPU, or
# while ZLUDA compiles kernels on first run). Only the LLM is load-bearing.

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot                       # install dir: app source + venv + client live here
$Client = Join-Path $Root 'Mythforge.exe'
$Log = Join-Path $Root 'launcher.log'
function Log($m) { $line = "$(Get-Date -Format u)  $m"; Write-Host $line; Add-Content -Path $Log -Value $line }

# Track only the processes WE start, so we only stop those on exit — never a
# service the player was already running for something else.
$started = @()
function Start-Bg($file, $args, $workdir) {
    Log "start: $file $args"
    $p = Start-Process -FilePath $file -ArgumentList $args -WorkingDirectory $workdir -WindowStyle Hidden -PassThru
    $script:started += $p
    return $p
}
function Wait-Port($port, $timeoutSec, $what) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ((Test-NetConnection 127.0.0.1 -Port $port -WarningAction SilentlyContinue).TcpTestSucceeded) {
            Log "$what up on :$port"; return $true
        }
        Start-Sleep -Milliseconds 700
    }
    Log "WARN: $what did not answer on :$port within ${timeoutSec}s"; return $false
}
function Port-Live($port) { (Test-NetConnection 127.0.0.1 -Port $port -WarningAction SilentlyContinue).TcpTestSucceeded }

try {
    Log "=== Mythforge launcher ==="

    # 0. First run (or a broken install): configure everything before playing.
    #    The single Start-Menu click therefore does setup-then-play the first
    #    time and just play every time after. Detect "configured" by the two
    #    artifacts bootstrap produces: the app venv and the game client.
    $venvPy = Join-Path $Root 'venv\Scripts\python.exe'
    if (-not (Test-Path $venvPy) -or -not (Test-Path $Client)) {
        Log 'first run — configuring (this downloads Ollama, ComfyUI, models and the game; go get a coffee)'
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'bootstrap.ps1') -Yes
        if ($LASTEXITCODE -ne 0) { throw 'first-run setup failed — see the output above and launcher.log' }
    }

    # 1. LLM — the one dependency the game cannot run without. Ollama fixes its
    #    GPU split at load time, so it goes up FIRST, before ComfyUI can grab the
    #    card (Performance.md §6 P1).
    if (-not (Port-Live 11434)) {
        if (Get-Command ollama -ErrorAction SilentlyContinue) { Start-Bg 'ollama' 'serve' $Root | Out-Null }
        else { Log 'WARN: ollama not found on PATH — run the installer/repair.' }
    } else { Log 'ollama already running' }
    Wait-Port 11434 30 'ollama' | Out-Null

    # 2. Backend — the game's brain. Uses the app venv the installer built.
    $venvPy = Join-Path $Root 'venv\Scripts\python.exe'
    if (-not (Test-Path $venvPy)) { throw "app venv missing at $venvPy — re-run the installer." }
    if (-not (Port-Live 7000)) {
        Start-Bg $venvPy '-m uvicorn app:app --host 127.0.0.1 --port 7000' $Root | Out-Null
    } else { Log 'backend already running' }
    if (-not (Wait-Port 7000 60 'backend')) { throw 'backend never came up — see launcher.log' }

    # 3. Seed the two model endpoints the game reads (LLM + image). The POST route
    #    dedupes on base_url, so this is a no-op after the first launch — safe to
    #    run every time rather than track first-run state.
    foreach ($ep in @(
        @{ url = 'http://127.0.0.1:11434/v1'; type = 'llm';   name = 'Ollama (local)' },
        @{ url = 'http://127.0.0.1:8101/v1';  type = 'image'; name = 'ComfyUI (local)' })) {
        try {
            Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:7000/api/model-endpoints' -Body @{
                base_url = $ep.url; model_type = $ep.type; endpoint_kind = 'local'; name = $ep.name; skip_probe = 'true'
            } -TimeoutSec 15 | Out-Null
            Log "endpoint ok: $($ep.type) → $($ep.url)"
        } catch { Log "WARN: could not seed $($ep.type) endpoint: $_" }
    }

    # 4. Image stack — best-effort, non-blocking. If there's no GPU or ComfyUI
    #    isn't installed, the game still plays; pre-baked worlds carry their art.
    $imgStack = Join-Path $Root 'scripts\start-image-stack.ps1'
    if ((Test-Path $imgStack) -and -not (Port-Live 8101)) {
        Log 'starting image stack (background; first run compiles kernels)…'
        Start-Bg 'powershell' "-NoProfile -ExecutionPolicy Bypass -File `"$imgStack`"" $Root | Out-Null
        # Do NOT wait — the game opens now; art fills in when the bridge answers.
    } elseif (Port-Live 8101) { Log 'image stack already running' }
    else { Log 'no image stack installed — playing with pre-baked art only' }

    # 5. The game. Block here until the player quits.
    if (-not (Test-Path $Client)) { throw "game client missing at $Client — re-run the installer." }
    Log 'launching the game'
    $game = Start-Process -FilePath $Client -PassThru
    $game.WaitForExit()
    Log 'game closed'
}
finally {
    # Stop only what we started, newest first (client's helpers before the LLM).
    [array]::Reverse($started)
    foreach ($p in $started) {
        try { if ($p -and -not $p.HasExited) { Log "stopping pid $($p.Id)"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } } catch {}
    }
    # ComfyUI launches its own child window from the .bat wrapper; sweep it too.
    foreach ($n in @('ComfyUI', 'main')) { Get-Process -Name $n -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Root*" -or $_.Path -like '*ComfyUI*' } | Stop-Process -Force -ErrorAction SilentlyContinue }
    Log '=== shutdown complete ==='
}
