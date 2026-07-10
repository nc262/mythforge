# check-system.ps1 — can this machine run Mythforge?
#
# Analyzes CPU / RAM / disk / GPU (NVIDIA, AMD, Intel, none) and prints a
# verdict + the exact install path for this hardware. Run it standalone, or
# let scripts\install.ps1 call it (-Json) to pick the right ComfyUI flavor.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\check-system.ps1
param([switch]$Json)

$ErrorActionPreference = 'SilentlyContinue'

# ── Requirements (the honest numbers) ────────────────────────────────────────
# TEXT-ONLY  — the full game minus generated art:
#   4-core CPU · 16 GB RAM · 15 GB disk · any GPU or none
#   (the 8B storyteller model runs on CPU if it must — slower turns)
# FULL (with image generation):
#   NVIDIA: GTX 1070 / RTX 2060 (8 GB VRAM) minimum · RTX 3060 12 GB recommended
#   AMD:    RDNA2 or newer with 12 GB VRAM (RX 6700 XT+) via ZLUDA
#   plus 32 GB RAM recommended · 45 GB disk (models are big)

$os   = Get-CimInstance Win32_OperatingSystem
$cs   = Get-CimInstance Win32_ComputerSystem
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$cores = ($cpu.NumberOfLogicalProcessors, 4 | Measure-Object -Maximum).Maximum
$drive = (Get-PSDrive -Name (Split-Path -Qualifier $PSScriptRoot).TrimEnd(':'))
$freeGB = [math]::Round($drive.Free / 1GB, 1)

# ── GPU detection ────────────────────────────────────────────────────────────
# Win32_VideoController.AdapterRAM caps at 4 GB; the registry qwMemorySize is
# accurate, and nvidia-smi is authoritative when present.
$gpus = @()
$regKeys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' |
  Where-Object { $_.PSChildName -match '^\d{4}$' }
foreach ($vc in (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Microsoft Basic|Remote|Virtual' })) {
  $vramGB = 0
  foreach ($k in $regKeys) {
    $p = Get-ItemProperty $k.PSPath
    if ($p.DriverDesc -eq $vc.Name -and $p.'HardwareInformation.qwMemorySize') {
      $vramGB = [math]::Round($p.'HardwareInformation.qwMemorySize' / 1GB, 1); break
    }
  }
  if (-not $vramGB -and $vc.AdapterRAM) { $vramGB = [math]::Round($vc.AdapterRAM / 1GB, 1) }
  $vendor = switch -Regex ($vc.Name) {
    'NVIDIA|GeForce|RTX|GTX|Quadro' { 'nvidia'; break }
    'AMD|Radeon|RX '                { 'amd'; break }
    'Intel|Arc|Iris|UHD'            { 'intel'; break }
    default                         { 'other' }
  }
  $gpus += [pscustomobject]@{ name = $vc.Name; vendor = $vendor; vramGB = $vramGB }
}
# nvidia-smi wins on VRAM accuracy when the toolchain is installed.
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($smi) {
  $line = (& nvidia-smi --query-gpu=name,memory.total --format=csv,noheader) | Select-Object -First 1
  if ($line) {
    $parts = $line -split ','
    $mb = [double](($parts[1] -replace '[^\d.]', ''))
    $g = $gpus | Where-Object vendor -eq 'nvidia' | Select-Object -First 1
    if ($g) { $g.vramGB = [math]::Round($mb / 1024, 1) }
  }
}
$best = $gpus | Sort-Object vramGB -Descending | Select-Object -First 1

# ── Verdict ──────────────────────────────────────────────────────────────────
$textOK  = ($ramGB -ge 15) -and ($cores -ge 4) -and ($freeGB -ge 15)
$imageOK = $false; $imagePath = 'none'; $notes = @()
if ($best) {
  switch ($best.vendor) {
    'nvidia' {
      if ($best.vramGB -ge 8) { $imageOK = $true; $imagePath = 'comfyui-cuda' }
      else { $notes += "NVIDIA card found but $($best.vramGB) GB VRAM < 8 GB — image generation will struggle or fail." }
      if ($best.vramGB -ge 8 -and $best.vramGB -lt 12) { $notes += '8 GB VRAM works; 12 GB is the comfortable tier for SDXL.' }
    }
    'amd' {
      $rdna2 = $best.name -match 'RX 6\d{3}|RX 7\d{3}|RX 9\d{3}'
      if ($rdna2 -and $best.vramGB -ge 12) { $imageOK = $true; $imagePath = 'comfyui-zluda'; $notes += 'AMD runs SDXL through ZLUDA — it works well but setup takes ~30-60 min (HIP SDK + first-run compile).' }
      elseif ($rdna2) { $notes += "AMD RDNA2+ card found but $($best.vramGB) GB VRAM < 12 GB — SDXL via ZLUDA needs 12 GB to be reliable." }
      else { $notes += "AMD card '$($best.name)' predates RDNA2 — ZLUDA support is unreliable; text-only recommended." }
    }
    default { $notes += "GPU '$($best.name)' can't run local SDXL — the game runs text-only (no generated art)." }
  }
} else { $notes += 'No discrete GPU found — the game runs text-only (no generated art).' }
if ($imageOK -and $ramGB -lt 31) { $notes += "32 GB RAM recommended for LLM + image gen together (you have $ramGB GB — it will work, with more model swapping)." }
if ($imageOK -and $freeGB -lt 45) { $notes += "Full install wants ~45 GB free (you have $freeGB GB)." }

$result = [pscustomobject]@{
  os = $os.Caption; cpu = $cpu.Name.Trim(); cores = $cores; ramGB = $ramGB; freeGB = $freeGB
  gpus = $gpus; textOK = $textOK; imageOK = $imageOK; imagePath = $imagePath; notes = $notes
}
if ($Json) { $result | ConvertTo-Json -Depth 4; exit 0 }

# ── Human report ─────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '  ✦ Mythforge — system check' -ForegroundColor Yellow
Write-Host ('  ' + ('─' * 60)) -ForegroundColor DarkGray
Write-Host "  OS    : $($result.os)"
Write-Host "  CPU   : $($result.cpu)  ($cores threads)"
Write-Host "  RAM   : $ramGB GB"
Write-Host "  Disk  : $freeGB GB free"
foreach ($g in $gpus) { Write-Host ("  GPU   : {0}  [{1}, {2} GB VRAM]" -f $g.name, $g.vendor.ToUpper(), $g.vramGB) }
if (-not $gpus) { Write-Host '  GPU   : none detected' }
Write-Host ('  ' + ('─' * 60)) -ForegroundColor DarkGray
if ($textOK) { Write-Host '  ✔ TEXT ADVENTURE: this machine can run the game (story, combat, worlds).' -ForegroundColor Green }
else { Write-Host '  ✘ Below minimum for a smooth game (want: 4 cores, 16 GB RAM, 15 GB disk). Consider joining a friend''s server instead.' -ForegroundColor Red }
if ($imageOK) { Write-Host "  ✔ FULL EXPERIENCE: image generation supported → install path: $imagePath" -ForegroundColor Green }
else { Write-Host '  ○ Image generation: not supported on this hardware — portraits/backdrops will be disabled (or join a server that has them).' -ForegroundColor Yellow }
foreach ($n in $notes) { Write-Host "  · $n" -ForegroundColor DarkYellow }
Write-Host ''
Write-Host '  Next: powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1' -ForegroundColor Cyan
Write-Host ''
