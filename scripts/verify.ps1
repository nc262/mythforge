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
	[switch]$Import,    # force a re-import first (after new or rewritten assets)
	[int]$HarnessTimeoutSec = 900   # per harness; a red one hangs rather than fails
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
	param([string]$Scene, [string]$Token, [switch]$Windowed, [int]$TimeoutSec = $HarnessTimeoutSec)
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
	$errLog = "$log.err"
	Write-Host "`n── $Scene " -NoNewline -ForegroundColor Cyan

	# A TIMEOUT, because a RED HARNESS HANGS. A failed `assert` does not stop
	# Godot: script execution stops, the scene tree keeps running, and a harness
	# that only quits after its last check never quits at all. Measured — a
	# deliberately broken assertion sat there past 90 s and had to be killed. So
	# the failure mode of the gate itself was "wait forever", which under
	# `/loop /next` means the loop never comes back.
	#
	# STDERR SEPARATELY, because that is where the assertion message goes. The
	# stdout log holds the harness's own prints and NOT the reason it failed.
	# `--log-file` KEEPS THE HARNESSES OUT OF THE PLAYER'S LOG FOLDER. Godot writes
	# every session to `user://logs` and keeps only the last N, and one gate run
	# starts FIVE Godot processes — so running the gate deleted the log of every
	# real play session before anyone could read it. That is not a tidiness
	# problem: it is why "no errors in play" could not be claimed at all, because
	# the evidence was destroyed by the act of checking for it.
	#
	# `--log-file` writes "instead of the default location defined by the
	# project", so a harness now touches nothing a player produced.
	$proc = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList ($flags + @('--log-file', "$log.engine", '--path', "$repo\godot", "res://tests/$Scene.tscn")) `
		-RedirectStandardOutput $log -RedirectStandardError $errLog
	# A SCRIPT THAT DOES NOT LOAD IS RED IN SECONDS, NOT FIFTEEN MINUTES. A parse
	# error does not stop Godot any more than a failed assert does: the scene tree
	# keeps running with a dead script and the harness waits out the whole
	# timeout. On 2026-09-16 that happened three times in one session — two name
	# collisions in self_check and one in town_probe — each an error Godot had
	# already written to the engine log in the FIRST SECOND, each costing the full
	# 900 s before the gate said so. Polling the log while waiting turns that into
	# a red within a couple of seconds. It only fires on a script failing to LOAD,
	# never on a runtime error, which a harness may raise on purpose.
	$deadline = (Get-Date).AddSeconds($TimeoutSec)
	$dead = $null
	while (-not $proc.WaitForExit(1000)) {
		$early = (Get-Content "$log.engine", $errLog -ErrorAction SilentlyContinue) |
			Where-Object { $_ -match 'Parse Error|Failed to load script|Compile Error' }
		if ($early) { $dead = $early; break }
		if ((Get-Date) -gt $deadline) { break }
	}
	if ($dead) {
		$proc.Kill(); $proc.WaitForExit()
		Write-Host "SCRIPT DID NOT LOAD" -ForegroundColor Red
		$script:failed += $Scene
		$dead | Select-Object -First 6 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
		return
	}
	if (-not $proc.HasExited) {
		$proc.Kill(); $proc.WaitForExit()
		Write-Host "TIMED OUT after ${TimeoutSec}s" -ForegroundColor Red
		$script:failed += $Scene
		((Get-Content $log, $errLog -ErrorAction SilentlyContinue) | Select-Object -Last 20) |
			ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
		return
	}
	$out = ((Get-Content $log, $errLog -Raw -ErrorAction SilentlyContinue) -join "`n")
	# ASK FOR THE VERDICT, NOT THE EXIT CODE. Godot exits 0 on a scene that
	# asserted its way to failure, and it exits non-zero on shutdown noise that
	# means nothing. The harnesses each print one token when they pass; that
	# token is the only thing here that is trusted.
	if ($out -match [regex]::Escape($Token)) {
		Write-Host "$Token" -ForegroundColor Green
		# GREEN IS NOT SILENT. A harness prints its pass token and its complaints
		# to two different streams, so an engine error in a PASSING run was
		# invisible — which is how "Mode: transition Combat → LevelUp is not
		# declared" survived every green gate until someone read a log by hand.
		# Noted, not failed: these need triage, and a gate that goes red on
		# upstream shutdown noise is a gate people learn to ignore.
		# The filter holds upstream shutdown chatter, and exactly one warning a
		# harness RAISES ON PURPOSE: self_check drives the art cache past its
		# budget to prove the thrash warning fires at all. Suppressing that is
		# not hiding a defect — printing it every run is how a person learns to
		# skim this section, which is the failure mode the section exists to fix.
		# `add_bos_token` joined this list on 2026-08-17 only after being EXONERATED
		# by measurement, not because it was noisy: it appeared 38 times in a run
		# that exits 0, and the shipped GGUF carries no such metadata while neither
		# NobodyWhoModel nor NobodyWhoChat exposes a property to set it. There is
		# nothing to act on, and it was for a while read as the cause of a crash it
		# had nothing to do with. See KnownIssues and docs/troubleshooting.md.
		$noise = 'ObjectDB instances were leaked|resources still in use|Godot Engine v|Initialize godot-rust|art cache is THRASHING|add_bos_token not found in GGUF metadata'
		$gripes = ($out -split "`n") | Where-Object { $_ -match 'WARNING:|SCRIPT ERROR|ERROR:' -and $_ -notmatch $noise }
		if ($gripes) {
			Write-Host "     $($gripes.Count) engine complaint(s) in a passing run:" -ForegroundColor DarkYellow
			$gripes | Select-Object -First 3 | ForEach-Object { Write-Host "       $($_.Trim())" -ForegroundColor DarkYellow }
			if ($gripes.Count -gt 3) { Write-Host "       … and $($gripes.Count - 3) more in $log" -ForegroundColor DarkYellow }
		}
		# …and a SHORT list that goes RED rather than yellow. A complaint that has
		# been chased to its cause, fixed, and measured to zero is no longer triage:
		# its return is a regression, and nothing else in the gate would notice,
		# because a passing token plus a yellow line is exactly what it looked like
		# for the unknown number of months it went unread. Only add a pattern here
		# once it is actually at zero — a permanently-red gate teaches the same
		# skimming this section exists to prevent.
		$regressions = 'Lambda capture at index \d+ was freed'
		$back = ($out -split "`n") | Where-Object { $_ -match $regressions }
		if ($back) {
			Write-Host "     REGRESSION — a complaint that was fixed is back:" -ForegroundColor Red
			$back | Select-Object -First 3 | ForEach-Object { Write-Host "       $($_.Trim())" -ForegroundColor Red }
			$script:failed += "$Scene (regression)"
		}
	} else {
		Write-Host 'FAILED' -ForegroundColor Red
		$script:failed += $Scene
		($out -split "`n" | Select-Object -Last 40) | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
	}
}

if ($Import) {
	Write-Host "`n── import" -ForegroundColor Cyan
	& $godot --headless --log-file (Join-Path ([IO.Path]::GetTempPath()) 'mythforge-import.engine') --path "$repo\godot" --import > (Join-Path ([IO.Path]::GetTempPath()) 'mythforge-import.log') 2>&1
}

# ── The offline gate — deterministic, no model, no GPU ───────────────────────
Invoke-Harness -Scene 'self_check'     -Token 'SELF-CHECK OK'
Invoke-Harness -Scene 'town_probe'     -Token 'TOWN-PROBE OK'
Invoke-Harness -Scene 'site_probe'     -Token 'SITE-PROBE OK'   # sites, and a trouble's life: ends, reach, who hears
Invoke-Harness -Scene 'click_driver'   -Token 'CLICKDRIVE OK'
Invoke-Harness -Scene 'ui_playthrough' -Token 'PLAYTHROUGH OK'

# ── PL-5's reproduction, kept as a guard ─────────────────────────────────────
# This one FAILS DELIBERATELY without the fix: it dresses five dialogs and frees
# each in the frame it was dressed, which is what a player does closing a panel
# the instant it opens. Before the fix that printed ten "Lambda capture at index
# N was freed" errors, 10/10, every run — the first deterministic reproduction
# after four disproven theories. The regression list above catches the error
# string, so this scene only has to CAUSE it.
Invoke-Harness -Scene 'pl5_probe' -Token 'PL5-PROBE DONE'

# ── The ones that can say an answer is GOOD, not merely well-shaped ──────────
if ($Full) {
	Invoke-Harness -Scene 'local_stack' -Token 'LOCAL STACK OK'
	# ART HAS NO REAL-STACK COVERAGE WITHOUT THIS. `local_stack` drives the real
	# model and never touches a painting, which is how PY-8 ("Envision this hero
	# is inert") survived to be found by hand: the whole image pipeline was
	# exercised by nothing but a player. art_probe commissions ONE picture from
	# the real engine and reports where it stops — queued, painting, ready, or
	# nowhere. Skipped, loudly, when no engine is listening, because a missing
	# optional engine is not a red gate.
	if (Get-NetTCPConnection -LocalPort 8189 -State Listen -EA SilentlyContinue) {
		Invoke-Harness -Scene 'art_probe' -Token 'ART-PROBE OK'
	} else {
		Write-Host "`n── art_probe SKIPPED — nothing listening on :8189" -ForegroundColor DarkYellow
	}
	# bench_gm IS NOT GATED, because it does not assert — it measures turn
	# latency and repetition and prints them. There is no pass token to match,
	# and inventing a threshold here would make the gate red on a slow morning.
	# It is printed so a regression stays visible; the judgement stays human.
	Write-Host "`n── bench_gm (report only)" -ForegroundColor Cyan
	$bench = Join-Path ([IO.Path]::GetTempPath()) 'mythforge-bench_gm.log'
	& $godot --headless --log-file "$bench.engine" --path "$repo\godot" 'res://tests/bench_gm.tscn' > $bench 2>&1
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

# ── INVARIANT: --vae-tiling is load-bearing, not tuning ──────────────────────
# Without it the VAE decode asks for a Vulkan buffer past this device's limit and
# falls back to a slow path: 36.2 s of a 50.4 s image, for a pixel-identical
# result at the same seed. There is ONE launch path today and it passes the flag;
# this check exists so a SECOND one cannot appear without it. `self_check` cannot
# see these files — they live outside res:// — so the guard belongs here.
Write-Host "`n── invariant: --vae-tiling " -NoNewline -ForegroundColor Cyan
$launchers = Get-ChildItem "$repo" -Recurse -Filter *.ps1 -EA SilentlyContinue | Where-Object {
	$t = Get-Content $_.FullName -Raw
	# an actual LAUNCH: names the exe AND passes it a model
	$t -match 'sd-server\.exe' -and $t -match "'-m'|`"-m`"|\s-m\s"
}
$noTiling = @($launchers | Where-Object { (Get-Content $_.FullName -Raw) -notmatch '--vae-tiling' })
if ($noTiling.Count) {
	Write-Host 'FAILED' -ForegroundColor Red
	$failed += 'invariant:--vae-tiling'
	$noTiling | ForEach-Object { Write-Host "  launches sd-server without --vae-tiling: $($_.FullName)" -ForegroundColor DarkRed }
} else {
	Write-Host ("OK ({0} launch path(s))" -f $launchers.Count) -ForegroundColor Green
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
	& $godot --headless --log-file (Join-Path ([IO.Path]::GetTempPath()) 'mythforge-export.engine') --path "$repo\godot" --export-release 'Windows Desktop' '../dist/Mythforge.exe' `
		> (Join-Path ([IO.Path]::GetTempPath()) 'mythforge-export.log') 2>&1
	$exe = "$repo\dist\Mythforge.exe"
	if (-not (Test-Path $exe)) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
	Write-Host ("{0:N0} bytes" -f (Get-Item $exe).Length) -ForegroundColor Green

	$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Mythforge.exe'
	try {
		Copy-Item $exe $desk -Force -ErrorAction Stop
		Write-Host "desktop $desk" -ForegroundColor Green
		# AND THE SCRIPTS BESIDE IT, because the Desktop copy is the build that
		# actually gets played and it has to behave like a real install. A shipped
		# install has {app}\scripts (the installer puts it there) and the game
		# looks for start-image-sdcpp.ps1 next to its own exe to start the image
		# engine. A bare exe on the Desktop finds nothing, silently plays with
		# baked art only, and the supervisor path is untestable by the one copy a
		# human ever launches - which is exactly how it shipped unproven.
		$deskScripts = Join-Path ([Environment]::GetFolderPath('Desktop')) 'scripts'
		New-Item -ItemType Directory -Force -Path $deskScripts | Out-Null
		Copy-Item (Join-Path $repo 'scripts\*.ps1') $deskScripts -Force -ErrorAction SilentlyContinue
		Write-Host "desktop scripts/ ($((Get-ChildItem $deskScripts -Filter *.ps1).Count) launchers)" -ForegroundColor Green
		# AND THE SAME MARKER THE INSTALLER WRITES. A real install records where it
		# put the image engine in image-engine.path, because the engine lives
		# outside {app} on purpose and a convention is not a location. The Desktop
		# copy has no installer to write it, so its engine was unfindable and the
		# supervisor could only be tested by hand-setting SDCPP_DIR — which is
		# exactly the kind of "works on the dev box for a reason nobody wrote down"
		# this file exists to prevent. Resolve it once, here, the same way.
		$sdHunt = @()
		$upSd = $repo
		for ($i = 0; $i -lt 5 -and $upSd; $i++) {
			$upSd = Split-Path -Parent $upSd
			if ($upSd) { $sdHunt += (Join-Path $upSd 'stable-diffusion.cpp') }
		}
		if ($env:SDCPP_DIR) { $sdHunt = @($env:SDCPP_DIR) + $sdHunt }
		$sdFound = $sdHunt | Where-Object { $_ -and (Test-Path (Join-Path $_ 'sd-server.exe')) } | Select-Object -First 1
		if ($sdFound) {
			Set-Content -Path (Join-Path ([Environment]::GetFolderPath('Desktop')) 'image-engine.path') -Value $sdFound -Encoding utf8
			Write-Host "desktop image-engine.path -> $sdFound" -ForegroundColor Green
		} else {
			Write-Host 'desktop image-engine.path: no sd-server found — the Desktop build will play with baked art' -ForegroundColor DarkYellow
		}
	} catch {
		# LOUD, NEVER SILENT. A locked Desktop copy means the game is open, and a
		# stale Desktop build is the one that gets playtested by mistake.
		Write-Host "DESKTOP COPY FAILED — close the running game, then re-copy:" -ForegroundColor Red
		Write-Host "  Copy-Item '$exe' '$desk' -Force" -ForegroundColor Yellow
		exit 1
	}
}

Write-Host "`nGREEN" -ForegroundColor Green
