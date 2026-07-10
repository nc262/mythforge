# setup-hip-env.ps1 — set the system environment variables ComfyUI-Zluda needs
# for an AMD GPU on Windows. Run ONCE, as Administrator, AFTER installing the
# AMD HIP SDK 6.4.2, then reboot.
#
#   Right-click PowerShell -> "Run as administrator", then:
#   powershell -ExecutionPolicy Bypass -File .\setup-hip-env.ps1
#
# Safe to re-run: it only sets values, and reports what it changed.

$ErrorActionPreference = 'Stop'
$rocm = 'C:\Program Files\AMD\ROCm\6.4\'
$bin  = 'C:\Program Files\AMD\ROCm\6.4\bin'

# Must be elevated to write Machine-scope variables.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator (it edits System environment variables)."
    exit 1
}

if (-not (Test-Path $rocm)) {
    Write-Warning "ROCm 6.4 not found at $rocm"
    Write-Warning "Install the AMD HIP SDK 6.4.2 first, then re-run this script."
    exit 1
}

[Environment]::SetEnvironmentVariable('HIP_PATH',    $rocm, 'Machine')
[Environment]::SetEnvironmentVariable('HIP_PATH_64', $rocm, 'Machine')
Write-Host "Set HIP_PATH    = $rocm" -ForegroundColor Green
Write-Host "Set HIP_PATH_64 = $rocm" -ForegroundColor Green

$path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($path -notlike "*$bin*") {
    [Environment]::SetEnvironmentVariable('Path', ($path.TrimEnd(';') + ';' + $bin), 'Machine')
    Write-Host "Added to system PATH: $bin" -ForegroundColor Green
} else {
    Write-Host "PATH already contains: $bin" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Done. REBOOT now so the new environment variables take effect everywhere." -ForegroundColor Yellow
