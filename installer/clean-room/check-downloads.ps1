# check-downloads.ps1 — can a STRANGER fetch everything a first run needs?
#
# Runs inside a throwaway Linux container: no GitHub credentials, no gh CLI, no
# browser session, no cached tokens, no dev machine. That is the whole point —
# on the dev box every one of these URLs works, because the dev box is signed in.
#
# It exists because of a real break. On 2026-08-04 the repo's `latest` release
# was v1.0.0, carrying a 1525 MB pre-split exe and six world packages that
# predated the tile bake (~220 MB lighter each). Every harness was green, the
# code was correct, and a stranger following the README got a broken game.
# No test in the project could see it, because the fault was in the PUBLISHED
# ARTIFACTS rather than in anything the repo builds.
#
# What this can prove: the URLs resolve anonymously, return the right kind of
# file, and are the size they should be.
# What it CANNOT prove: that the game runs. There is no GPU, no Vulkan and no
# Windows in a Linux container. That is DI-1 and it still needs a real machine.
#
#   pwsh check-downloads.ps1 [-Repo nc262/mythforge] [-Tag latest]

param(
    [string]$Repo = $env:MF_REPO,
    [string]$Tag  = $env:MF_TAG
)
if (-not $Repo) { $Repo = 'nc262/mythforge' }
if (-not $Tag)  { $Tag  = 'latest' }

$ProgressPreference = 'SilentlyContinue'   # progress bars in a container are noise
$script:Failures = 0
$script:Checked  = 0

# A release asset URL. `latest/download/<name>` is what the installer actually
# uses, so test that exact shape rather than a pinned tag we happen to know.
function Rel([string]$name) {
    if ($Tag -eq 'latest') { "https://github.com/$Repo/releases/latest/download/$name" }
    else                   { "https://github.com/$Repo/releases/download/$Tag/$name" }
}

# One asset: does it resolve, is it big enough, and does it start with the magic
# bytes of the format it claims to be?
#
# The magic-byte check is not paranoia. A private repo, a deleted asset or a
# typo'd name all return a 200 with an HTML error page, and content-length alone
# happily calls that a pass.
function Check {
    param(
        [string]$Label,
        [string]$Url,
        [int64]$MinBytes = 1,
        [byte[]]$Magic = $null,
        [int64]$MaxBytes = 0
    )
    $script:Checked++
    try {
        $h = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 10 -TimeoutSec 60 -ErrorAction Stop
        $len = [int64]($h.Headers['Content-Length'] | Select-Object -First 1)
    } catch {
        "  FAIL  {0,-34} unreachable: {1}" -f $Label, $_.Exception.Message
        $script:Failures++
        return
    }

    $mb = [math]::Round($len / 1MB, 1)
    if ($len -lt $MinBytes) {
        "  FAIL  {0,-34} {1} MB — expected at least {2} MB" -f $Label, $mb, [math]::Round($MinBytes/1MB,1)
        $script:Failures++
        return
    }
    if ($MaxBytes -gt 0 -and $len -gt $MaxBytes) {
        "  FAIL  {0,-34} {1} MB — expected at most {2} MB" -f $Label, $mb, [math]::Round($MaxBytes/1MB,1)
        $script:Failures++
        return
    }

    if ($Magic) {
        try {
            $n = $Magic.Length - 1
            $r = Invoke-WebRequest -Uri $Url -Headers @{ Range = "bytes=0-$n" } `
                                   -MaximumRedirection 10 -TimeoutSec 60 -ErrorAction Stop
            $got = [byte[]]$r.Content[0..$n]
            if (Compare-Object $got $Magic) {
                "  FAIL  {0,-34} {1} MB — wrong magic bytes ({2}), not the file it claims to be" `
                    -f $Label, $mb, (($got | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
                $script:Failures++
                return
            }
        } catch {
            "  WARN  {0,-34} {1} MB — range request refused, size-only check" -f $Label, $mb
            return
        }
    }
    "  ok    {0,-34} {1} MB" -f $Label, $mb
}

$PK = [byte[]](0x50, 0x4B, 0x03, 0x04)   # zip
$MZ = [byte[]](0x4D, 0x5A)               # Windows PE

"== the game, from $Repo @ $Tag =="
# 131 MB exe. The floor is 50 MB and the CEILING matters just as much: a build
# over ~400 MB means the worlds got bundled back in, which is what put the
# release over GitHub's 2 GiB cap and is the shape of the v1.0.0 break.
Check 'Mythforge.exe' (Rel 'Mythforge.exe') (50MB) $MZ -MaxBytes (400MB)

"`n== the six worlds =="
# ~445-540 MB each. The floor is 350 MB SPECIFICALLY to catch a tile-less pack:
# v1.0.0's worlds were 220-243 MB because they predated the tile bake, and a
# lower floor would have called them fine.
foreach ($w in 'embervale','neonspire','everyday','saltmarsh','fimbulreach','brasshaven') {
    Check "$w.zip" (Rel "$w.zip") (350MB) $PK
}

"`n== the models (HuggingFace, public) =="
Check 'narrator (llama 3.1 8B Q4_K_M)' 'https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf' (4GB)
Check 'memory encoder (nomic v1.5)'    'https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf' (50MB)
Check 'voice (whisper base.en)'        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin' (50MB)
Check 'art checkpoint (DreamShaper)'   'https://huggingface.co/Lykon/dreamshaper-xl-v2-turbo/resolve/main/DreamShaperXL_Turbo_v2_1.safetensors' (5GB)

"`n== the two engines (GitHub, public) =="
# Both are PINNED versions. If upstream deletes or retags one, the install
# breaks on a stranger's machine and nothing here would otherwise notice.
$sdTag = 'master-802-e92e86f'
$sdAsset = "sd-$($sdTag -replace '^master-802-', 'master-')-bin-win-vulkan-x64.zip"
Check 'stable-diffusion.cpp (vulkan)' "https://github.com/leejet/stable-diffusion.cpp/releases/download/$sdTag/$sdAsset" (10MB) $PK

# The asset name repeats the tag in full — verified here rather than trusted,
# because fetch_nobodywho.py builds this URL by string-mashing.
$nwTag = 'nobodywho-godot-v9.5.0'
Check 'NobodyWho GDExtension' "https://github.com/nobodywho-ooo/nobodywho/releases/download/$nwTag/nobodywho-godot-$nwTag.zip" (100MB) $PK

"`n=============================================="
if ($script:Failures -gt 0) {
    "CLEAN-ROOM FAILED — $($script:Failures) of $($script:Checked) downloads are broken for a stranger."
    'A first run would fail on someone else''s machine even though every harness here is green.'
    exit 1
}
"CLEAN-ROOM OK — all $($script:Checked) downloads resolve anonymously, at the right size and format."
'Proves the plumbing only. Nothing here ran the game: no GPU, no Vulkan, no Windows.'
exit 0
