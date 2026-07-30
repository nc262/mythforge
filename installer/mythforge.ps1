# mythforge.ps1 — the one launcher a player ever runs.
#
# Two processes, and only one of them matters:
#
#   client : Mythforge.exe (Godot)                      the game
#   image  : sd-server.exe (Vulkan)  → 127.0.0.1:8189   optional; art only
#
# The narrator, campaign memory, the codex, the quest log, the world tick, the
# Worldsmith, the World Compiler and speech-to-text all run INSIDE the game on
# llama.cpp. There is nothing to sign in to and nothing to start first.
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
function Start-Bg($file, $arguments, $workdir) {
    Log "start: $file $arguments"
    $p = Start-Process -FilePath $file -ArgumentList $arguments -WorkingDirectory $workdir -WindowStyle Hidden -PassThru
    $script:started += $p
    return $p
}
function Port-Live($port) { (Test-NetConnection 127.0.0.1 -Port $port -WarningAction SilentlyContinue).TcpTestSucceeded }

try {
    Log "=== Mythforge launcher ==="

    # 0. First run (or a broken install): configure before playing, so the single
    #    Start-Menu click does setup-then-play the first time and just play after.
    #    "Configured" is ONE artifact — the game client — because there is no
    #    environment to build and no services to register.
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

    # 2. The game. Block here until the player quits.
    if (-not (Test-Path $Client)) { throw "game client missing at $Client — re-run the installer." }
    Log 'launching the game'
    $game = Start-Process -FilePath $Client -PassThru
    $game.WaitForExit()
    Log 'game closed'
}
finally {
    # Stop only what we started.
    foreach ($p in $started) {
        try { if ($p -and -not $p.HasExited) { Log "stopping pid $($p.Id)"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } } catch {}
    }
    # sd-server is launched via a PowerShell wrapper, so stop the engine itself
    # rather than only the shell that started it.
    Get-Process -Name 'sd-server' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Log '=== shutdown complete ==='
}
