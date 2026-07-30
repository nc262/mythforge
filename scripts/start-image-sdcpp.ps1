<#
.SYNOPSIS
  Start the image engine: stable-diffusion.cpp on Vulkan.

.DESCRIPTION
  One native binary, one checkpoint, no Python. It serves the OpenAI image API
  directly on /v1/images/generations, so the game POSTs to it with no proxy in
  between.

  Idempotent: if something is already listening on the port, this returns.

.PARAMETER Exe
  sd-server.exe. Install it with scripts/fetch_sdcpp.py.

.PARAMETER Checkpoint
  An SDXL .safetensors. Left unset, the first of the known model folders that
  has one wins — install.ps1 downloads into the engine's own models/ directory,
  but a machine that already keeps a model library elsewhere should not have to
  download 6.5 GB twice.
#>
param(
  [string]$Exe        = "C:\Users\cptahabb\Documents\Code\stable-diffusion.cpp\sd-server.exe",
  [string]$Checkpoint = "",
  [int]$Port          = 8189
)

if (-not (Test-Path $Exe)) { throw "sd-server not found: $Exe  (run scripts/fetch_sdcpp.py)" }

if (-not $Checkpoint) {
  $candidates = @(
    (Join-Path (Split-Path $Exe -Parent) 'models'),
    "C:\Users\cptahabb\Documents\Code\ComfyUI-Zluda\models\checkpoints"
  )
  foreach ($dir in $candidates) {
    if (-not (Test-Path $dir)) { continue }
    $found = Get-ChildItem $dir -Filter *.safetensors -ErrorAction SilentlyContinue |
             Sort-Object Name | Select-Object -First 1
    if ($found) { $Checkpoint = $found.FullName; break }
  }
}
if (-not $Checkpoint -or -not (Test-Path $Checkpoint)) {
  throw "no .safetensors checkpoint found. Pass -Checkpoint, or run scripts/install.ps1 to fetch one."
}

$live = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($live) { Write-Host "already listening on :$Port" -ForegroundColor Green; return }

$log = Join-Path $env:TEMP "sd-server.log"
Remove-Item $log, "$log.err" -ErrorAction SilentlyContinue

# --diffusion-fa: flash attention in the diffusion model. Measured on an RX 7900
#   GRE this is the difference between comfortable and tight VRAM at SDXL 1024.
# --vae-tiling: do NOT drop this. Untiled, decoding a single 1024x1024 latent
#   asks for one Vulkan buffer past this device's limit, ggml logs "Failed to
#   allocate pinned memory ... ErrorOutOfDeviceMemory" and falls back to a slow
#   path: decode alone was 36.2s of a 50.4s image. Tiled it is 3.1s, for a
#   pixel-identical result at the same seed. 50.4s -> 19.9s per image.
Start-Process -FilePath $Exe -WindowStyle Minimized `
  -ArgumentList "-m","`"$Checkpoint`"","--listen-port","$Port","--diffusion-fa","--vae-tiling" `
  -RedirectStandardOutput $log -RedirectStandardError "$log.err"

Write-Host "loading $(Split-Path $Checkpoint -Leaf) (~6.5 GB)..." -ForegroundColor Cyan
foreach ($i in 1..40) {
  Start-Sleep -Seconds 3
  if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    Write-Host "image engine up on http://127.0.0.1:$Port" -ForegroundColor Green
    return
  }
}
Write-Warning "did not come up in 2 minutes - check $log"
