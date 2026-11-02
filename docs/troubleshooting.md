# Troubleshooting

RCAs for failures actually hit on this stack. Each one: symptom → root cause →
fix. A symptom with a guess instead of a root cause does not belong here.

## The game says it has no narrator

> "The storyteller has no voice yet — the NobodyWho extension is not installed."

- **Cause:** the GDExtension binary is gitignored (it is over GitHub's 100 MB
  per-file limit), so a fresh clone has the manifest but no DLL.
- **Fix:** `python scripts/fetch_nobodywho.py`, or run `scripts/install.ps1`,
  which does it as step 3.
- **Same cause, different face:** `verify.ps1` passes all three offline harnesses
  (they run in `Api.test_mode`, so they never need the DLL) and then says
  `export FAILED — no fresh exe. Close the running game`. Nothing is running: the
  export log says `GDExtension: Failed to copy shared object`. Hit 2026-11-02 in
  the main checkout, which had the addon's manifest but never its DLL — every
  harness log also carried `GDExtension dynamic library not found`.

> "no .gguf model in …"

- **Cause:** nothing in `user://models`.
- **Fix:** `scripts/install.ps1` downloads all three, or drop any chat `.gguf`
  in that folder and restart.

## The GM answers, but badly and instantly

- **Cause:** the 80 MB **encoder** got loaded as the narrator. Both live in
  `user://models`, and if the narrator picker fell back to "first file found",
  filesystem order would decide which one talks.
- **Fix:** `LocalGM.chat_models()` skips anything matching the encoder hints
  (`embed`, `minilm`, `nomic`, `bge`, `gte`, `e5-`), and Settings' picker lists
  only the survivors. If you add a model whose name contains one of those, it
  will be treated as an encoder — rename it.
- **Why it is worth guarding:** this failure is silent. It does not error; it
  just narrates worse, forever.

## Turns are slow (tens of seconds)

- **Cause, almost always:** the model is not fully resident on the GPU. A
  llama.cpp GPU/CPU split is decided **once, at load time**, so anything holding
  VRAM when the model loads costs you for the life of the process.
- **Fix:** make sure nothing else is on the card when the game starts.
  stable-diffusion.cpp idles at ~118 MB and loads per request, so it is not the
  culprit; a resident image stack (7+ GB) absolutely is. Measured on this box:
  19.3 s per turn with one resident, 3.7 s without.
- See [godot/docs/Performance.md](../godot/docs/Performance.md).

## A structured call takes 90+ seconds and then fails

> `Error during context shift: not enough messages to shift`

- **Cause:** one call was asked to *invent* and *serialise* at the same time. A
  grammar and a sampler chain **replace each other** in NobodyWho, so a
  schema-constrained call runs with no top-k, top-p, temperature or repetition
  penalty — and an unsampled model rambles until it runs out of context.
- **Fix:** think in prose first (`LocalGM.prose()`), then hand that prose to
  `complete_json()` with a small schema. Measured: 95.8 s failure → 1.5 s
  success.
- **Do not** "fix" this by raising the context or adding `maxLength` to the
  schema. Both were tried. `maxLength: N` compiles to `char{0,N}` in GBNF, which
  is extremely slow to sample, and at N ≥ 2000 it emits GBNF that does not
  parse. Full detail in
  [godot/docs/LocalLLM-Tuning.md](../godot/docs/LocalLLM-Tuning.md).

## Every GM reply opens the same way

> "The smell of bread hangs in the air. The lamplight…"

- **Cause:** two things at once. The extension's default sampler carries a fixed
  seed, and "be vivid" means "paint the room" to an 8B model.
- **Fix:** `LocalGM._tune_narrator()` sets an explicit sampler before every turn,
  and CRAFT carries *"OPEN ON WHAT CHANGED — an action, a person, a consequence,
  a line of speech. Do NOT open with weather, light, smell, or the time of
  day."* That line alone took atmosphere openings from 3/3 to 0/3 in `bench_gm`.

## An image takes ~50 s and most of it is the decode

- **Cause:** without `--vae-tiling`, the VAE decode asks for a Vulkan buffer past
  this device's limit, falls back to a slow path, and spends 36.2 s of a 50.4 s
  image.
- **Fix:** `--vae-tiling` in **every** launch path. Tiled: 3.1 s decode, 19.9 s
  image, pixel-identical at the same seed. This is load-bearing, not tuning.
- **Related:** sd-server **ignores `steps` in the request body**. Steps are a
  launch flag or nothing.

## A regex silently matches nothing

- **Cause:** `\uXXXX` is a JavaScript escape. Godot's RegEx is **PCRE2**, where
  it is not valid — the pattern compiles to something that never matches, with
  no error.
- **Fix:** put the literal character in the pattern (`•`, `—`, `–`, `"`, `"`).
  This was written twice before it stuck.

## A mesh was rewritten and Godot kept serving the old one

**Symptom:** a `.gltf` is re-exported with new geometry, `--import` is run, the
harness measures **exactly** the same numbers as before — identical to the digit,
including breakdowns that could not possibly repeat by chance.

**Root cause:** Godot decides whether to re-import by hashing the file its
`.import` points at — the **`.gltf`**. With `GLTF_SEPARATE` that JSON holds only
offsets and counts; every vertex lives in the **`.bin`** beside it, and **Godot
does not hash the `.bin`**. Rewrite a mesh in place without changing its vertex
count and the JSON comes out byte-identical, `source_md5` still matches, and the
engine serves the mesh it cached the first time. Nothing reports anything: the
file on disk is new and the scene in the game is old.

Confirmed directly — the stored hash equalled the live `.gltf` hash while the
`.bin` had changed:

```
source_md5="123e1ea4eddd35de345571431668b4d6"   # .godot/imported/....md5
123e1ea4eddd35de345571431668b4d6                # md5 of the .gltf   -> match
d8d479ac4f69ddfcadd7b10d33522dd4                # md5 of the .bin    -> ignored
```

**Fix:** `stamp()` in `scripts/refit_garments.py` and `scripts/forge_base_body.py`
writes the `.bin`'s md5 into the glTF's `asset.extras`, so the `.gltf`'s own
checksum moves whenever the geometry does. Any script that rewrites a mesh in
place must do the same.

**To clear a cache already poisoned:** delete the matching
`.godot/imported/<name>.gltf-*.md5` and `.scn` and re-import. Touching the file
does **not** work — the check is a hash, not a timestamp.

This cost three rounds of measurements taken against day-old geometry, and the
only reason it was caught is that the numbers were *too* identical.

## A harness "runs" for ten minutes and prints nothing

**Symptom:** a scripted harness sits there. The Godot process is alive and
burning CPU, so it looks like slow work — but its log holds only the startup
banner, and that banner names **Vulkan and the GPU**, which a headless run has
no reason to touch.

**Root cause:** `--headless` never arrived, so Godot opened a window and waited
for a player. In `scripts/verify.ps1` the flags were built as

```powershell
$flags = if ($Windowed) { @() } else { @('--headless') }   # WRONG
```

and PowerShell **unrolls a one-element array returned from an `if`** — `$flags`
became the *string* `--headless`, and `@flags` splatted a string rather than an
argument list. Assign the array directly instead, on its own statement.

**The tell is the banner.** `Vulkan … Using Device #0` in a run that was
supposed to be headless means the flag was dropped, every time. Same run,
headless, takes 3.9 s.

**Related, same script:** two runs sharing one log path kill each other with
*"the process cannot access the file"*, so the log name carries `$PID`.

**And the exported game is the mirror image of this.** `Mythforge.exe` is a
GUI-subsystem binary that reattaches to the parent console, so its output
survives a **pipe** and is lost to a **file redirect** — `--headless --mf-worlds`
gives 322 characters through `| Out-String` and a **0-byte file** through
`> out.txt`. Exit codes are correct either way. So: pipe the game, redirect the
editor. Getting it backwards silently empties whichever log you were trusting.

## A harness that FAILS never comes back

**Symptom:** a harness you expect to fail neither passes nor exits. It sits.

**Root cause:** a failed `assert` does not stop Godot. Script execution stops,
the **scene tree keeps running**, and a harness that only calls `quit()` after
its last check never reaches it. So the natural failure mode of every harness
here is *hang*, not *fail* — measured at over 90 s on a deliberately broken
assertion before it was killed.

Worse, the reason is on **stderr** while the harness's own prints are on stdout,
so a log that captures only stdout shows a run that simply stopped mid-way.

**Fix:** `scripts/verify.ps1` runs each harness under a timeout
(`-HarnessTimeoutSec`, default 900), kills it, captures **both** streams, and
reports it red. Anything else that drives a harness unattended must do the same
or it waits forever.

## A dialog's exit button is off the bottom of the screen

The merchant counter soft-lock (PL-7): pick any ware and "Leave the counter" is
gone, with no way out but killing the game.

- **Cause:** an embedded `Window` grows to its content's minimum size and **never
  shrinks back**, nor re-centres. The detail strip was toggled from
  `visible = false`, and for the frame it appeared its autowrapped `Label` was
  measured at zero width — one word per line — so the dialog grew to **1002 px
  for 571 px of content** and kept it. Measured, not inferred: three earlier
  fixes (re-measuring the content cap, clamping the position) assumed the
  content was too tall, and it never was.
- **Fix:** keep anything that appears later **in the layout from the start** and
  reveal it with `modulate.a`, so a wrapping label always has its real width.
  The dialog now stays 627 px before and after picking.
- **Why no harness saw it:** `click_driver`'s audit measured a dialog's buttons
  against the dialog's own viewport, so a button that left the screen with its
  window was still "on-screen". It now measures in screen space, and the shop
  station picks a ware and must leave by the button.

## The exe won't copy to the Desktop

> `Device or resource busy`

- **Cause:** the game is running and holding the file.
- **Fix:** close it first. Never skip the Desktop copy silently — a stale
  Desktop build gets playtested by mistake, which wastes a whole session chasing
  bugs that are already fixed.

## The Desktop icon is still the old one

- **Cause:** Windows caches icons per path.
- **Fix:** `ie4uinit.exe -show`, or log out and back in.

## The art is the wrong style entirely

- **Cause:** the image engine loaded a different checkpoint. `start-image-sdcpp.ps1`
  takes the first `.safetensors` it finds, and on a machine with a shared model
  library that can be anything — an anime checkpoint restyles every item,
  portrait and backdrop in the game without erroring once.
- **Fix:** it now prefers a checkpoint whose name matches `dreamshaper` then
  `juggernaut`. Point `SD_MODEL_DIR` at your library, or pass `-Checkpoint`
  explicitly. The engine names the file it loaded on startup — read that line.

## An old image stack keeps coming back

- **Cause:** something is supervising it. Two things have: a pm2 app that polled
  the port and relaunched it (and `pm2 save` is needed, or `dump.pm2` restores it
  on reboot), and a logon script in the Startup folder pointing at a *different*
  checkout entirely.
- **Fix:** check pm2's dump and the Startup folder before believing a kill
  worked. Both are disabled here.

## Method notes that keep earning their place

- **A string search is not a dependency check.** A grep for a filename found 44
  of 49 dependents; five more used path joins and were only caught by diffing
  the test collection.
- **Assert what the failure looks like, not what a good answer looks like.**
  Three separate metrics in this repo's history passed broken output with
  confidence.
- **Ask the parser, not the text.** If you want to know whether the model
  produced a valid object, parse it. Scoring the string is how you end up
  measuring the wrong thing.
