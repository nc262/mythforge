# mythforge.ps1 — the one launcher a player ever runs.
#
# Brings up EVERYTHING the desktop game needs, in the right order, on private
# loopback ports, then launches the game and tears it all down on exit. The
# player double-clicks the Start-Menu shortcut; they never see or manage a
# service. This is the whole of "nothing on localhost you deal with — it's all
# internal to the game".
#
#   image  : sd-server.exe (Vulkan)  → 127.0.0.1:8189   (optional; art)
#   client : Mythforge.exe (Godot)                      (the game)
#
# THAT IS THE WHOLE STACK. It used to be four processes — a FastAPI backend on
# :7000 called "the game's brain", Ollama on :11434, an image stack on :8101, and
# the client talking to all of them. The narrator, campaign memory, the codex,
# the quest log, the world tick, the Worldsmith, the World Compiler and
# speech-to-text now run INSIDE the game on llama.cpp (NobodyWho), and art goes
# straight to sd-server. The backend had no callers left and is deleted; Ollama
# went with it, since it existed to serve the backend.
#
# The image engine is best-effort: pre-baked worlds ship their art, so the game
# is fully playable if it never comes up.

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot                       # install dir: the client and the image engine live here
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

    # 0. First run (or a broken install): configure before playing, so the single
    #    Start-Menu click does setup-then-play the first time and just play after.
    #    "Configured" is now ONE artifact — the game client — because there is no
    #    venv to build and no services to register.
    if (-not (Test-Path $Client)) {
        Log 'first run — configuring (this downloads the game and its models; go get a coffee)'
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'bootstrap.ps1') -Yes
        if ($LASTEXITCODE -ne 0) { throw 'first-run setup failed — see the output above and launcher.log' }
    }

    # 1. Image engine — best-effort, non-blocking. No GPU or no checkpoint means
    #    the game still plays; pre-baked worlds carry their art.
    $imgStack = Join-Path $Root 'scripts\start-image-sdcpp.ps1'
    if ((Test-Path $imgStack) -and -not (Port-Live 8189)) {
        Log 'starting image engine (background; ~25 s to read the checkpoint)…'
        Start-Bg 'powershell' "-NoProfile -ExecutionPolicy Bypass -File `"$imgStack`"" $Root | Out-Null
        # Do NOT wait — the game opens now; art fills in when the engine answers.
    } elseif (Port-Live 8189) { Log 'image engine already running' }
    else { Log 'no image engine installed — playing with pre-baked art only' }

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
    # sd-server is launched via a PowerShell wrapper, so stop the engine itself
    # rather than only the shell that started it.
    Get-Process -Name 'sd-server' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Log '=== shutdown complete ==='
}
