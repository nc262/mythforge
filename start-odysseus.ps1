# -----------------------------
# Odysseus Bootstrap (PM2-safe)
# -----------------------------

$ErrorActionPreference = "Stop"

# Lock working directory so PM2 doesn't break relative paths
Set-Location $PSScriptRoot

Write-Host "🚀 Starting Odysseus stack..." -ForegroundColor Cyan

# -----------------------------
# Start Chroma
# -----------------------------
Write-Host "🧠 Starting Chroma..." -ForegroundColor Yellow

$chroma = Start-Process "chroma" `
    -ArgumentList "run --host 0.0.0.0 --port 8100" `
    -PassThru `
    -WindowStyle Hidden

# Wait for Chroma readiness (with timeout)
$timeout = 60
$elapsed = 0
$ready = $false

while (-not $ready -and $elapsed -lt $timeout) {
    Start-Sleep 2
    $elapsed += 2

    try {
        Invoke-RestMethod "http://localhost:8100/api/v2/heartbeat" | Out-Null
        $ready = $true
    }
    catch {
        $ready = $false
    }
}

if (-not $ready) {
    throw "❌ Chroma failed to start within $timeout seconds"
}

Write-Host "✅ Chroma ready" -ForegroundColor Green

# -----------------------------
# Start Image Stack
# -----------------------------
Write-Host "🖼️ Starting image engine..." -ForegroundColor Yellow

& "$PSScriptRoot\scripts\start-image-sdcpp.ps1"

# -----------------------------
# Start API (UVICORN)
# -----------------------------
Write-Host "🌐 Starting FastAPI (uvicorn)..." -ForegroundColor Cyan

Set-Location $PSScriptRoot

python -m uvicorn app:app `
    --host 0.0.0.0 `
    --port 7000