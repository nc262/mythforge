# run.ps1 — the clean-room check, in a throwaway container.
#
#   pwsh installer\clean-room\run.ps1
#
# Uses the stock PowerShell image and mounts this folder. No Dockerfile, no
# build step, nothing to keep in sync — the image is a PowerShell interpreter
# and the test is the script beside this one.
#
# The container is the point, not a convenience: it has no GitHub credentials,
# no gh CLI, no browser session and no cached tokens, so it fetches these URLs
# exactly the way a stranger's machine will. Run the same script on the dev box
# and it passes even when the release is private — which is precisely the bug
# it is meant to catch.
param(
    [string]$Repo = 'nc262/mythforge',
    [string]$Tag  = 'latest',
    [string]$Image = 'mcr.microsoft.com/powershell:latest'
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

docker run --rm `
    -e MF_REPO=$Repo -e MF_TAG=$Tag `
    -v "${here}:/clean-room:ro" `
    $Image pwsh -NoProfile -File /clean-room/check-downloads.ps1
exit $LASTEXITCODE
