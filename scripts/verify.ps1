# verify.ps1 — the gate. One command that decides whether work is done.
#
# WHY IT EXISTS. The five harnesses and the export were five things to remember,
# and the one most often forgotten was the export: a `godot/**` change that is
# never re-exported means the next playtest runs YESTERDAY'S EXE and every bug
# it finds is already fixed. That has cost whole sessions. Making the gate a
# single command means a run either goes green all the way to the Desktop copy
# or it does not go green at all.
#
# SERIAL ON PURPOSE. Nothing here runs in parallel and nothing here should. The
# narrator's GPU/CPU split is fixed once at load time, so a second heavy job on
# the card during -Full poisons the very number -Full exists to measure — and a
# windowed render plus a headless harness plus a Blender bake is what froze this
# machine once already. One thing on the card at a time.
#
#   pwsh scripts/verify.ps1                # offline gate + export + Desktop copy
#   pwsh scripts/verify.ps1 -Full          # + the two that drive the real model
#   pwsh scripts/verify.ps1 -Audit         # + the windowed body audit (~4 min)
#   pwsh scripts/verify.ps1 -NoExport      # tests only, leave the exe alone
param(
	[switch]$Full,      # local_stack + bench_gm — real models, real GPU
	[switch]$Audit,     # body_audit — windowed, slow, pre-release rather than inner loop
	[switch]$NoExport,  # skip export and the Desktop copy
	[switch]$Import     # force a re-import first (after new or rewritten assets)
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$failed = @()

# ── Find Godot ───────────────────────────────────────────────────────────────
# The console build, not the plain one: the plain exe detaches from the terminal
# and a harness that prints its verdict to nowhere cannot gate anything.
$godot = $env:GODOT
if (-not $godot -or -not (Test-Path $godot)) {
	$godot = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
		-Filter 'Godot_v*_console.exe' -Recurse -ErrorAction SilentlyContinue |
		Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $godot) { Write-Error 'no Godot console build found; set $env:GODOT'; exit 1 }
Write-Host "godot   $godot" -ForegroundColor DarkGray

# REDIRECT TO A FILE, NEVER PIPE. `Godot_..._console.exe` is a shim that spawns
# the real GUI binary and relays its output; put a PowerShell pipe on the far end
# and the pair deadlocks with the harness apparently running — 105 s of CPU, ten
# minutes of wall clock, not one line printed. The identical run redirected to a
# file finishes in 3.9 s.
function Invoke-Harness {
	param([string]$Scene, [string]$Token, [switch]$Windowed)
	# TWO STATEMENTS, NOT `$flags = if (...) {@('--headless')}`. An `if` that
	# yields a one-element array hands back the ELEMENT — PowerShell unrolls it —
	# so `@flags` splatted a string, `--headless` never reached Godot, and every
	# harness opened a window and waited for a player who was never coming.
	# Direct assignment keeps the array.
	$flags = @('--headless')
	if ($Windowed) { $flags = @() }
	# PID in the name: a leftover run still holding `mythforge-ui_playthrough.log`
	# took down a good one with "the process cannot access the file".
	$log = Join-Path ([IO.Path]::GetTempPath()) "mythforge-$PID-$Scene.log"
	Write-Host "`n── $Scene " -NoNewline -ForegroundColor Cyan
	& $godot @flags --path "$repo\godot" "res://tests/$Scene.tscn" > $log 2>&1
	$out = Get-Content $log -Raw
	# ASK FOR THE VERDICT, NOT THE EXIT CODE. Godot exits 0 on a scene that
	# asserted its way to failure, and it exits non-zero on shutdown noise that
	# means nothing. The harnesses each print one token when they pass; that
	# token is the only thing here that is trusted.
	if ($out -match [regex]::Escape($Token)) {
		Write-Host "$Token" -ForegroundColor Green
	} else {
		Write-Host 'FAILED' -ForegroundColor Red
		$script:failed += $Scene
		($out -split "`n" | Select-Object -Last 40) | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
	}
}

if ($Import) {
	Write-Host "`n── import" -ForegroundColor Cyan
	& $godot --headless --path "$repo\godot" --import > (Join-Path ([IO.Path]::GetTempPath()) 'mythforge-import.log') 2>&1
}

# ── The offline gate — deterministic, no model, no GPU ───────────────────────
Invoke-Harness -Scene 'self_check'     -Token 'SELF-CHECK OK'
Invoke-Harness -Scene 'click_driver'   -Token 'CLICKDRIVE OK'
Invoke-Harness -Scene 'ui_playthrough' -Token 'PLAYTHROUGH OK'

# ── The ones that can say an answer is GOOD, not merely well-shaped ──────────
if ($Full) {
	Invoke-Harness -Scene 'local_stack' -Token 'LOCAL STACK OK'
	# bench_gm IS NOT GATED, because it does not assert — it measures turn
	# latency and repetition and prints them. There is no pass token to match,
	# and inventing a threshold here would make the gate red on a slow morning.
	# It is printed so a regression stays visible; the judgement stays human.
	Write-Host "`n── bench_gm (report only)" -ForegroundColor Cyan
	$bench = Join-Path ([IO.Path]::GetTempPath()) 'mythforge-bench_gm.log'
	& $godot --headless --path "$repo\godot" 'res://tests/bench_gm.tscn' > $bench 2>&1
	Get-Content $bench | Where-Object { $_ -match 'turn \d+:|REPETITION' } |
		ForEach-Object { Write-Host "  $($_.TrimEnd())" -ForegroundColor DarkGray }
}
if ($Audit) {
	# Windowed because a headless capture comes back blank — the dummy
	# rasterizer draws nothing, so every pixel count would read zero and pass.
	Invoke-Harness -Scene 'body_audit' -Token 'BODY-AUDIT OK' -Windowed
}

# ── The first-run script, which is not the game but ships with it ────────────
# Offline, no network, a few seconds. It belongs in the gate because the download
# is the one part of this project a harness could never see: the code can be
# perfect and the thing a stranger installs still broken.
Write-Host "`n── check-bootstrap " -NoNewline -ForegroundColor Cyan
$bootLog = Join-Path ([IO.Path]::GetTempPath()) "mythforge-$PID-bootstrap.log"
& pwsh -NoProfile -File "$repo\installer\check-bootstrap.ps1" > $bootLog 2>&1
if ((Get-Content $bootLog -Raw) -match 'BOOTSTRAP-CHECK OK') {
	Write-Host 'BOOTSTRAP-CHECK OK' -ForegroundColor Green
} else {
	Write-Host 'FAILED' -ForegroundColor Red
	$failed += 'check-bootstrap'
	Get-Content $bootLog | Select-String 'FAIL' | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
}

if ($failed.Count) {
	Write-Host "`nRED: $($failed -join ', ')" -ForegroundColor Red
	Write-Host 'Not exporting. A red gate must not reach the Desktop.' -ForegroundColor Red
	exit 1
}

# ── Export, and then the copy that is actually played ────────────────────────
if (-not $NoExport) {
	Write-Host "`n── export " -NoNewline -ForegroundColor Cyan
	New-Item -ItemType Directory -Force "$repo\dist" | Out-Null
	& $godot --headless --path "$repo\godot" --export-release 'Windows Desktop' '../dist/Mythforge.exe' `
		> (Join-Path ([IO.Path]::GetTempPath()) 'mythforge-export.log') 2>&1
	$exe = "$repo\dist\Mythforge.exe"
	if (-not (Test-Path $exe)) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
	Write-Host ("{0:N0} bytes" -f (Get-Item $exe).Length) -ForegroundColor Green

	$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Mythforge.exe'
	try {
		Copy-Item $exe $desk -Force -ErrorAction Stop
		Write-Host "desktop $desk" -ForegroundColor Green
	} catch {
		# LOUD, NEVER SILENT. A locked Desktop copy means the game is open, and a
		# stale Desktop build is the one that gets playtested by mistake.
		Write-Host "DESKTOP COPY FAILED — close the running game, then re-copy:" -ForegroundColor Red
		Write-Host "  Copy-Item '$exe' '$desk' -Force" -ForegroundColor Yellow
		exit 1
	}
}

Write-Host "`nGREEN" -ForegroundColor Green
