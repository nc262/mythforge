# Runs ELEVATED (admin). Adds a Windows Defender exclusion for the ComfyUI-Zluda
# folder (ZLUDA is a known AV false-positive), then downloads + extracts ZLUDA and
# applies the CUDA->ZLUDA DLL swaps into the torch lib. Writes a result marker.
# Reversible: Remove-MpPreference -ExclusionPath <path> undoes the exclusion.
param(
    # ComfyUI-Zluda install dir — defaults to the sibling of this repo.
    [string]$repo = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))) 'ComfyUI-Zluda')
)
$ErrorActionPreference = 'Continue'
$z    = "$repo\zluda"
$lib  = "$repo\venv\Lib\site-packages\torch\lib"
$url  = 'https://github.com/lshqqytiger/ZLUDA/releases/download/rel.5e717459179dc272b7d7d23391f0fad66c7459cf/ZLUDA-nightly-windows-rocm6-amd64.zip'
$marker = Join-Path $env:USERPROFILE '_excl_done.txt'
$log = @()
try {
    Add-MpPreference -ExclusionPath $repo -ErrorAction Stop
    $log += "exclusion added: $repo"
} catch { $log += "exclusion FAILED: $($_.Exception.Message)" }
Start-Sleep -Seconds 3
Remove-Item $z -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $z | Out-Null
& curl.exe -L --ssl-no-revoke -o "$z\zluda.zip" $url
$zip = Get-Item "$z\zluda.zip" -ErrorAction SilentlyContinue
$log += "zip MB: $([math]::Round(($zip.Length/1MB),2))"
try {
    Expand-Archive -Path "$z\zluda.zip" -DestinationPath $z -Force -ErrorAction Stop
    Remove-Item "$z\zluda.zip" -Force
    $log += "extracted OK"
} catch { $log += "extract FAILED: $($_.Exception.Message)" }

# Apply DLL swaps (mirrors patchzluda-n.bat, without touching torch itself)
$pairs = @(
    @("$z\cublas.dll",   "$lib\cublas64_11.dll"),
    @("$z\cusparse.dll", "$lib\cusparse64_11.dll"),
    @("$lib\nvrtc64_112_0.dll", "$lib\nvrtc_cuda.dll"),
    @("$z\nvrtc.dll",    "$lib\nvrtc64_112_0.dll"),
    @("$z\cufft.dll",    "$lib\cufft64_10.dll"),
    @("$z\cufftw.dll",   "$lib\cufftw64_10.dll")
)
foreach ($p in $pairs) {
    if (Test-Path $p[0]) { Copy-Item $p[0] $p[1] -Force; $log += "copied $(Split-Path $p[1] -Leaf)" }
    else { $log += "MISSING source $($p[0])" }
}
if (Test-Path "$repo\comfy\customzluda\zluda.py") {
    Copy-Item "$repo\comfy\customzluda\zluda.py" "$repo\comfy\zluda.py" -Force
    $log += "comfy\zluda.py installed"
}
$log += "zluda.exe present: $(Test-Path "$z\zluda.exe")"
$cub = Get-Item "$lib\cublas64_11.dll" -ErrorAction SilentlyContinue
$log += "cublas64_11.dll size now: $($cub.Length) (small = ZLUDA stub, ~88M = still original CUDA)"
$log += "done $(Get-Date)"
$log -join "`r`n" | Out-File -FilePath $marker -Encoding utf8
