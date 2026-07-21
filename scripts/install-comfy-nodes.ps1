# install-comfy-nodes.ps1 — add the ComfyUI custom nodes Mythforge's art
# pipeline requires, to an EXISTING ComfyUI install.
#
# Run this if you installed ComfyUI before Mythforge needed these, or if the
# AMD path told you to come back after ComfyUI-Zluda's install.bat.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\install-comfy-nodes.ps1
#   flags: -ComfyDir <path>   (otherwise auto-detected as a sibling folder)
#
# WHY THESE ARE REQUIRED, not optional:
#   InSPyReNet Rembg gives every generated image a real alpha channel. The
#   World Compiler builds thousands of item variants by recolouring and
#   re-treating a base icon, and all of that needs a clean cut-out. Measured on
#   real hardware: prompting for "a plain black background" produces a usable
#   cut-out ~60% of the time; matting is ~100%. Without it, loot can only be
#   regenerated one-by-one, never varied — which is the whole point.
param([string]$ComfyDir)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sib  = Split-Path -Parent $root

function Step($m) { Write-Host "`n> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  OK  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  !   $m" -ForegroundColor Yellow }

if (-not $ComfyDir) {
  $ComfyDir = @("$sib\ComfyUI-Zluda", "$sib\ComfyUI") |
              Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $ComfyDir -or -not (Test-Path $ComfyDir)) {
  throw "ComfyUI not found. Pass -ComfyDir <path>, or run scripts\install.ps1 first."
}
Ok "ComfyUI: $ComfyDir"

$py = Join-Path $ComfyDir 'venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
  throw "ComfyUI's venv isn't built yet ($py). On AMD, run $ComfyDir\install.bat first, then rerun this."
}

# --- InSPyReNet Rembg (matting) ---------------------------------------------
$nodes = Join-Path $ComfyDir 'custom_nodes'
New-Item -ItemType Directory -Force $nodes | Out-Null
$rembg = Join-Path $nodes 'ComfyUI-Inspyrenet-Rembg'
if (Test-Path $rembg) {
  Ok 'Matting node already present'
} else {
  Step 'Cloning InSPyReNet Rembg (matting)'
  git clone --depth 1 https://github.com/john-mnz/ComfyUI-Inspyrenet-Rembg $rembg
  Ok 'Cloned'
}

Step 'Installing its Python dependency into ComfyUI''s venv'
& $py -m pip install "transparent-background>=1.2.4" -q
Ok 'transparent-background installed'

# --- Verify torch survived ---------------------------------------------------
Step 'Verifying ComfyUI''s torch is intact'
$torchVer = & $py -c "import torch; print(torch.__version__)" 2>$null
if ($LASTEXITCODE -eq 0) { Ok "torch $torchVer" }
else { Warn 'Could not import torch — check the ComfyUI venv.' }

Write-Host ''
Write-Host '  Restart ComfyUI for the new node to register.' -ForegroundColor Yellow
Write-Host '  AMD/ZLUDA: restart it with its OWN launcher (_run-comfy.bat or' -ForegroundColor DarkGray
Write-Host '  start-image-stack.cmd). Restarting via ComfyUI-Manager''s reboot' -ForegroundColor DarkGray
Write-Host '  button drops the ZLUDA environment and image generation will fail' -ForegroundColor DarkGray
Write-Host '  with "unable to find an engine to execute this computation".' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Verify:  the node "InspyrenetRembg" appears in ComfyUI''s node list.' -ForegroundColor DarkGray
