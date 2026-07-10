# Troubleshooting — Odysseus (local deployment)

RCAs for the failures actually hit bringing up this stack. Each: symptom → root cause →
fix.

## ComfyUI won't start / `localhost:8188` won't load

### `TypeError: init() got an unexpected keyword argument 'simple_vram_headroom'`
- **Cause:** the stock launcher (`comfyui-n.bat`) auto-`git pull`ed an upstream ComfyUI
  commit incompatible with installed components.
- **Fix:** roll back to the known-good commit (`git reset --hard <commit>`) and launch
  via the pinned `_run-comfy.bat` (no git pull). Update ComfyUI deliberately, not
  automatically.

### `OSError: [WinError 126] … cublas64_11.dll … or one of its dependencies`
- **Cause:** ComfyUI was launched as plain `python main.py` (e.g. **ComfyUI Manager's
  "Restart" button**), bypassing the ZLUDA wrapper, so the ZLUDA cublas stub can't
  resolve HIP deps.
- **Fix:** always launch via `.\zluda\zluda.exe -- python main.py` (i.e. via
  `_run-comfy.bat` / `start-image-stack.ps1`). Don't use Manager's restart.

### `tar: Error opening archive: Failed to open 'zluda.zip'` / `nccl.dll` missing
- **Cause:** Windows Defender quarantined the ZLUDA download (known false positive).
- **Fix:** add a Defender exclusion for `..\ComfyUI-Zluda`, then re-download/patch ZLUDA
  (`scripts/fix-zluda-elevated.ps1`). Confirm `cublas64_11.dll` in
  `venv\Lib\site-packages\torch\lib` is the small (~250 KB) ZLUDA stub, not the 88 MB
  CUDA original.

## Image generation fails

### `RuntimeError: cuDNN error: CUDNN_STATUS_EXECUTION_FAILED` (in UNet conv2d)
- **Cause:** ZLUDA's cuDNN path is unreliable on AMD; `cudnn.dll` isn't patched on
  purpose.
- **Fix:** disable cuDNN. The bridge routes the model through
  `CUDNNToggleAutoPassthrough(enable_cudnn=False)` in every workflow. For hand-built
  ComfyUI workflows, add the **CFZ CUDNN Toggle** node (enable_cudnn=False).

### First generation takes minutes / appears to hang
- **Cause:** ZLUDA compiles kernels for each new op-shape on first use (logs show
  "Compilation is in progress"). Not a hang — check CPU time + `%LOCALAPPDATA%\ZLUDA\
  ComputeCache` growing.
- **Fix:** wait it out once; subsequent gens for that shape are fast (cached). Give the
  bridge a generous `--timeout` for first runs.

### Bridge returns `TimeoutError` but ComfyUI keeps working
- **Cause:** the client gave up before the (first-run) compile finished; ComfyUI still
  completes the queued prompt.
- **Fix:** raise the bridge `--timeout`; the next request is fast.

## Personas

### Persona won't generate an image in chat
- **Cause:** `gurubot/girl:latest` doesn't emit tool calls; there's no chat→image
  auto-trigger. Expected.
- **Fix:** generate explicitly via the bridge `character` param, or build a deterministic
  chat trigger. Switching to a tool-capable model trades away the persona voice.

### Persona prompt edits don't show up
- **Cause:** `presets.json` is cached at startup; a UI preset-save can overwrite a file
  edit with the stale cache.
- **Fix:** edit the file then **restart Odysseus**, or edit via the UI/API. Don't do
  both out of order.

### Persona breaks character / contradicts canon
- **Cause:** old `Brain → identity` memory entries recalled alongside the new World
  Bible; or a tool-capable model pushed into "assistant" mode.
- **Fix:** reconcile/remove the stale identity memories; keep canon in the prompt.

## Launching scripts from automation
- Background/detached `cmd` may not inherit a `cd`, and PowerShell mangles single-quoted
  strings with embedded quotes passed to `cmd`. **Use a wrapper `.bat` that `cd /d`s and
  calls the target by full path**, or `Start-Process -FilePath` with absolute paths.
- ComfyUI's venv must be **Python 3.11** (triton/torch ZLUDA patches are cp311-only);
  pre-create it with `py -3.11 -m venv venv` before running the installer.
