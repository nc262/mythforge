<#
.SYNOPSIS
  Start the image engine: stable-diffusion.cpp on Vulkan. Replaces ComfyUI+ZLUDA.

.DESCRIPTION
  One native binary, one checkpoint, no Python, no CUDA shim. It serves the
  OpenAI image API directly on /v1/images/generations, which is the same shape
  scripts/comfyui_openai_bridge.py existed to fake in front of ComfyUI — so the
  bridge is not needed either.

  What this deletes, and why it mattered (see CLAUDE.md history):
    * zluda.exe wrapper launch      - ZLUDA is a CUDA shim; Vulkan needs none
    * the Windows Defender exclusion - required only because ZLUDA tripped it
    * cuDNN forced off               - a ZLUDA/SDXL conv2d workaround
    * Python pinned to 3.11          - ZLUDA's torch patches were cp311-only
    * ComfyUI auto-update disabled   - pinned to avoid an incompatible commit

  ComfyUI itself is left installed and untouched; it is simply no longer part of
  this stack.

.PARAMETER Checkpoint
  SDXL .safetensors. Defaults to the DreamShaper XL Turbo already on this box.
#>
param(
  [string]$Exe        = "C:\Users\cptahabb\Documents\Code\stable-diffusion.cpp\sd-server.exe",
  [string]$Checkpoint = "C:\Users\cptahabb\Documents\Code\ComfyUI-Zluda\models\checkpoints\DreamShaperXL_Turbo_v2_1.safetensors",
  [int]$Port          = 8189
)

if (-not (Test-Path $Exe))        { throw "sd-server not found: $Exe  (scripts/fetch_sdcpp.py)" }
if (-not (Test-Path $Checkpoint)) { throw "checkpoint not found: $Checkpoint" }

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
    Write-Host "  register it as an image endpoint at http://localhost:$Port/v1"
    return
  }
}
Write-Warning "did not come up in 2 minutes - check $log"
