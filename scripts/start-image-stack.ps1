# start-image-stack.ps1 - bring up the local image-generation stack for Odysseus:
#   1. ComfyUI-ZLUDA (the GPU image engine) on :8188
#   2. The OpenAI-compatible bridge (comfyui_openai_bridge.py) on :8101
#
# Odysseus then talks only to the bridge (:8101), exactly like any other
# OpenAI image provider. Run this after the one-time ComfyUI-Zluda install.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\start-image-stack.ps1

$ErrorActionPreference = 'Stop'

# Paths resolve relative to this repo; override with env vars for custom layouts.
$odysseusDir = Split-Path -Parent $PSScriptRoot
$comfyDir    = if ($env:COMFY_DIR) { $env:COMFY_DIR } else {
  # Sibling install: ComfyUI-Zluda (AMD) or ComfyUI (NVIDIA), whichever exists.
  $sib = Split-Path -Parent $odysseusDir
  @("$sib\ComfyUI-Zluda", "$sib\ComfyUI") | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $comfyDir) { throw "ComfyUI not found next to this repo — set COMFY_DIR or run scripts\install.ps1" }
$venvPython = Join-Path $odysseusDir 'venv\Scripts\python.exe'
$bridge     = Join-Path $odysseusDir 'scripts\comfyui_openai_bridge.py'
$ckpt       = 'DreamShaperXL_Turbo_v2_1.safetensors'

function Test-Port($p) {
    try { (Test-NetConnection -ComputerName 127.0.0.1 -Port $p -WarningAction SilentlyContinue).TcpTestSucceeded }
    catch { $false }
}

# --- 1. ComfyUI ---
if (Test-Port 8188) {
    Write-Host "ComfyUI already running on :8188" -ForegroundColor DarkGray
} else {
    Write-Host "Starting ComfyUI-ZLUDA (new window)..." -ForegroundColor Cyan
    # Use the wrapper bat: it cd's into the repo and calls comfyui-n.bat by full
    # path. Start-Process -WorkingDirectory is NOT honored reliably for cmd here,
    # so the wrapper (which sets its own cwd) is the dependable launch path.
    # Hidden (not minimized): a visible/minimized console can be closed by the
    # user or a session event, which sends CTRL_CLOSE and aborts ComfyUI
    # (forrtl error 200). Hidden has no window to close. Logs go to the file.
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "$comfyDir\_run-comfy.bat" -WindowStyle Hidden
    Write-Host "Waiting for ComfyUI on :8188 (first launch compiles ZLUDA kernels; can take a few minutes)..."
    $deadline = (Get-Date).AddMinutes(8)
    while (-not (Test-Port 8188)) {
        if ((Get-Date) -gt $deadline) { Write-Warning "ComfyUI didn't come up within 8 min - check its window."; break }
        Start-Sleep -Seconds 3
    }
    if (Test-Port 8188) { Write-Host "ComfyUI is up." -ForegroundColor Green }
}

# --- 2. Bridge ---
if (Test-Port 8101) {
    Write-Host "Bridge already running on :8101" -ForegroundColor DarkGray
} else {
    Write-Host "Starting OpenAI->ComfyUI bridge on :8101..." -ForegroundColor Cyan
    Start-Process -FilePath $venvPython `
        -ArgumentList $bridge, '--comfy-url', 'http://127.0.0.1:8188', '--ckpt', $ckpt, '--port', '8101', '--timeout', '1800' `
        -WorkingDirectory $odysseusDir -WindowStyle Hidden `
        -RedirectStandardOutput "$env:USERPROFILE\_odyssee_bridge.log" -RedirectStandardError "$env:USERPROFILE\_odyssee_bridge.err"
    Start-Sleep -Seconds 3
    if (Test-Port 8101) { Write-Host "Bridge is up at http://127.0.0.1:8101/v1" -ForegroundColor Green }
    else { Write-Warning "Bridge didn't bind :8101 - check its window." }
}

Write-Host ""
Write-Host "Image stack ready. In Odysseus, the image provider base URL is: http://localhost:8101/v1" -ForegroundColor Yellow
