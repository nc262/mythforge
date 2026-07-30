# check-system.ps1 — can this machine run Mythforge?
#
# Analyzes CPU / RAM / disk / GPU and prints a verdict. Run it standalone, or
# let scripts\install.ps1 call it (-Json).
#
# Both engines run on VULKAN, which every current vendor ships, so the only
# question this asks is how much VRAM there is — not whose logo is on the card.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\check-system.ps1
param([switch]$Json)

$ErrorActionPreference = 'SilentlyContinue'

# ── Requirements (the honest numbers) ────────────────────────────────────────
# TEXT-ONLY — the full game minus generated art:
#   4-core CPU · 16 GB RAM · 15 GB disk · any GPU or none.
#   The narrator falls back to CPU if it must; turns get slow but nothing breaks.
# COMFORTABLE — the narrator fully resident on the GPU:
#   8 GB VRAM. A half-offloaded model is the single biggest latency cost there
#   is (godot/docs/Performance.md), so this is the number that matters most.
# FULL — generated art as well:
#   12 GB VRAM · 32 GB RAM recommended · 45 GB disk.

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
$imageOK = $false; $imagePath = 'none'; $gpuNarrator = $false; $notes = @()
if ($best) {
  # One rule, every vendor: enough VRAM or not. Vulkan does the rest.
  if ($best.vramGB -ge 8)  { $gpuNarrator = $true }
  else { $notes += "$($best.vramGB) GB VRAM — the narrator will run partly on the CPU, which is the biggest single cost per turn." }
  if ($best.vramGB -ge 12) { $imageOK = $true; $imagePath = 'sdcpp-vulkan' }
  elseif ($gpuNarrator)    { $notes += 'Generated art wants ~12 GB so it does not compete with the narrator for the card.' }
  if ($best.vendor -eq 'intel') { $notes += "Intel graphics run Vulkan too, but this combination is untested here — expect to find out." }
} else { $notes += 'No discrete GPU found — the game plays text-only, on the CPU, slowly but completely.' }
if ($imageOK -and $ramGB -lt 31) { $notes += "32 GB RAM recommended when both engines are live (you have $ramGB GB)." }
if ($imageOK -and $freeGB -lt 45) { $notes += "A full install wants ~45 GB free (you have $freeGB GB)." }

$result = [pscustomobject]@{
  os = $os.Caption; cpu = $cpu.Name.Trim(); cores = $cores; ramGB = $ramGB; freeGB = $freeGB
  gpus = $gpus; textOK = $textOK; imageOK = $imageOK; imagePath = $imagePath
  gpuNarrator = $gpuNarrator; notes = $notes
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
if ($textOK) { Write-Host '  ✔ THE GAME: story, combat, worlds — this machine can run it.' -ForegroundColor Green }
else { Write-Host '  ✘ Below minimum (want: 4 cores, 16 GB RAM, 15 GB disk). It will run; it will not be pleasant.' -ForegroundColor Red }
if ($gpuNarrator) { Write-Host '  ✔ NARRATOR ON THE GPU: turns stay fast.' -ForegroundColor Green }
else { Write-Host '  ○ Narrator will share with the CPU — expect slow turns.' -ForegroundColor Yellow }
if ($imageOK) { Write-Host '  ✔ GENERATED ART: supported (stable-diffusion.cpp, Vulkan).' -ForegroundColor Green }
else { Write-Host '  ○ Generated art: off. The shipped worlds carry pre-baked art, so nothing is missing from play.' -ForegroundColor Yellow }
foreach ($n in $notes) { Write-Host "  · $n" -ForegroundColor DarkYellow }
Write-Host ''
Write-Host '  Next: powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1' -ForegroundColor Cyan
Write-Host ''
