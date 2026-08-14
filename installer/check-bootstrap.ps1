# check-bootstrap.ps1 — does the first-run script actually DO what it claims?
#
# WHY. `bootstrap.ps1` is the only part of the download nothing had ever
# executed. The clean-room proves the URLs resolve for a stranger; the Inno
# script is proven to compile, install and uninstall without residue. Between
# those two sat ~100 lines of PowerShell that had never run once, on any machine,
# and that every player runs first.
#
# HOW, and this is the whole trick: `-SkipEngine` removes the ~10 GB half, and a
# throwaway root seeded with files that are ALREADY THERE removes the rest. What
# is left is every decision the script makes — and the decisions were never the
# part that needed a fast connection.
#
# WHAT THIS CANNOT PROVE, stated plainly so a green run is not mistaken for more
# than it is:
#   * that the ~10 GB fetch works (that is scripts\install.ps1, and it needs a
#     clean machine and a real connection — the open half of DI-1)
#   * that the URLs resolve for a stranger (clean-room\check-downloads.ps1)
#   * that curl resumes a half-file over a bad line
# Every case below runs with NO NETWORK AT ALL, on purpose: a check that needs
# the internet fails for reasons that have nothing to do with the code.
#
#   pwsh installer\check-bootstrap.ps1

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$script:Fail = 0
$WORLDS = @('embervale', 'neonspire', 'everyday', 'saltmarsh', 'fimbulreach', 'brasshaven')

function Ok([string]$what, [bool]$cond, [string]$saw = '') {
	if ($cond) { Write-Host "  ok   $what" -ForegroundColor DarkGreen }
	else {
		Write-Host "  FAIL $what" -ForegroundColor Red
		if ($saw) { Write-Host "       saw: $saw" -ForegroundColor DarkRed }
		$script:Fail++
	}
}

# A throwaway install root shaped like a real one: the actual bootstrap.ps1
# under installer\, and whatever payload the case wants beside it.
function New-Root {
	param([switch]$NoInstaller, [string[]]$Worlds = @(), [switch]$Client)
	$root = Join-Path ([IO.Path]::GetTempPath()) "mf-boot-$PID-$(Get-Random)"
	New-Item -ItemType Directory -Force (Join-Path $root 'installer') | Out-Null
	Copy-Item (Join-Path $PSScriptRoot 'bootstrap.ps1') (Join-Path $root 'installer') -Force
	if (-not $NoInstaller) {
		New-Item -ItemType Directory -Force (Join-Path $root 'scripts') | Out-Null
		Set-Content (Join-Path $root 'scripts\install.ps1') '# stand-in; -SkipEngine never runs it' -Encoding utf8
	}
	if ($Worlds.Count) {
		New-Item -ItemType Directory -Force (Join-Path $root 'baked') | Out-Null
		foreach ($w in $Worlds) { Set-Content (Join-Path $root "baked\$w.zip") 'not really a zip' -Encoding utf8 }
	}
	if ($Client) {
		# HARDLINK, not a copy — the real 197 MB artifact, for free, so step 4
		# runs the real `--mf-worlds` probe instead of a stand-in that would
		# prove only that the stand-in works.
		$real = Join-Path $Repo 'dist\Mythforge.exe'
		if (Test-Path $real) { New-Item -ItemType HardLink -Path (Join-Path $root 'Mythforge.exe') -Target $real | Out-Null }
	}
	$root
}

function Invoke-Bootstrap([string]$root, [string[]]$ExtraArgs = @()) {
	$b = Join-Path $root 'installer\bootstrap.ps1'
	# PIPE, not `> file`. The probe in step 4 is an exported Godot GUI binary
	# that reattaches to the console: piped it yields its 322 characters, and
	# redirected to a file it yields an empty one. Measured both ways.
	$out = & pwsh -NoProfile -File $b -SkipEngine @ExtraArgs 2>&1 | Out-String
	[pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
}

$haveClient = Test-Path (Join-Path $Repo 'dist\Mythforge.exe')
Write-Host "bootstrap check  (real client artifact: $(if ($haveClient) {'yes'} else {'no — step 4 cases skipped'}))" -ForegroundColor Cyan

# ── 1. The repair run: everything present, nothing re-fetched ────────────────
# README calls bootstrap "idempotent, so it doubles as a repair". This is that
# claim, executed. A repair that quietly re-downloads 2.9 GB is a broken promise
# on a metered line, so the assertion is that each world is SKIPPED BY NAME.
Write-Host "`n[1] repair run — client and all six worlds already present" -ForegroundColor Cyan
$r = New-Root -Worlds $WORLDS -Client
$res = Invoke-Bootstrap $r
Ok 'exits 0' ($res.Code -eq 0) "exit $($res.Code)"
foreach ($w in $WORLDS) { Ok "$w skipped as present" ($res.Out -match "$w — already present") }
Ok 'no .part files left behind' (-not (Get-ChildItem $r -Recurse -Filter '*.part' -ErrorAction SilentlyContinue))
Ok 'skips the engine when told to' ($res.Out -match 'SkipEngine')
if ($haveClient) {
	Ok 'client reported as already present' ($res.Out -match 'already present \(\d+ MB\)')
	# The zips above are text files named .zip. A listing that counts them as
	# worlds is the exact failure the probe exists to catch, so a green run here
	# would mean the probe is decorative.
	Ok 'unreadable world zips are caught, not counted' ($res.Out -match 'CANNOT OPEN')
	Ok 'and the player is told' ($res.Out -match 'found no playable worlds')
}
Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue

# ── 2. No URL and worlds missing: named, not swallowed ───────────────────────
# The path a player lands on when MYTHFORGE_CLIENT_URL is unset. Every missing
# world must be listed, because the recovery instruction is "download these".
Write-Host "`n[2] no release URL, three of six worlds missing" -ForegroundColor Cyan
$present = $WORLDS[0..2]; $absent = $WORLDS[3..5]
$r = New-Root -Worlds $present
$res = Invoke-Bootstrap $r
Ok 'still exits 0 — a missing world warns, it does not abort the install' ($res.Code -eq 0) "exit $($res.Code)"
Ok 'warns that no client URL was given' ($res.Out -match 'no client URL given')
foreach ($w in $absent) { Ok "$w named as missing" ($res.Out -match "could not fetch:.*$w") }
foreach ($w in $present) { Ok "$w not named as missing" (-not ($res.Out -match "could not fetch:.*\b$w\b")) }
Ok 'names the folder to drop them in' ($res.Out -match 'baked')
Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue

# ── 3. baked\ gets created when it does not exist ────────────────────────────
Write-Host "`n[3] no baked folder at all" -ForegroundColor Cyan
$r = New-Root
$res = Invoke-Bootstrap $r
Ok 'creates baked\' (Test-Path (Join-Path $r 'baked'))
Ok 'exits 0' ($res.Code -eq 0) "exit $($res.Code)"
Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue

# ── 4. An incomplete payload fails LOUDLY ────────────────────────────────────
# The one case that must not be a warning. A bootstrap that shrugs at a missing
# scripts\install.ps1 hands over a game with no narrator and no explanation.
Write-Host "`n[4] payload incomplete — scripts\install.ps1 missing" -ForegroundColor Cyan
$r = New-Root -NoInstaller
$res = Invoke-Bootstrap $r
Ok 'exits non-zero' ($res.Code -ne 0) "exit $($res.Code)"
Ok 'says what is missing' ($res.Out -match 'install\.ps1 missing')
Ok 'and it is checked even under -SkipEngine' ($res.Out -match 'incomplete')
Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Fail -gt 0) { Write-Host "BOOTSTRAP-CHECK FAILED ($script:Fail)" -ForegroundColor Red; exit 1 }
Write-Host 'BOOTSTRAP-CHECK OK' -ForegroundColor Green
