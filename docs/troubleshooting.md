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

- **Cause 1 — a bad split, permanent.** A llama.cpp GPU/CPU split is decided
  **once, at load time**. The narrator needs ~5.9 GB; if less is free when it
  loads, layers land on the CPU and stay there for the life of the process.
  Measured: 19.3 s per turn with a CUDA-shimmed ComfyUI-Zluda holding ~7.4 GB at
  load, against 3.7 s with the card clear.
- **Cause 2 — a picture is being painted right now.** This one is temporary,
  and it is the one you will actually hit. Two processes on the same shaders:
  turns went 3.5 s → 6.1 s while sd-server generated 1024×1024 images, with peak
  VRAM at 15310 MB of 16384 — nothing was evicted, they were simply competing.
- **Fix:** for cause 1, check what is on the card *before the game starts* —
  sd-server is NOT the usual culprit (127 MB until its first image, 6.6 GB after,
  which still leaves the narrator enough on a 16 GB card); a Python image stack
  is. For cause 2, confirm `Art.hold` is still being set around the stream in
  `game.gd` — that flag is the fix and it already exists.
- **NOT the cause:** sd-server merely being up when the narrator loads. Measured
  at 3.3/3.6/3.5 s against 3.0/3.5/3.5 s on a clear card — no penalty.
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

## The gate sits for fifteen minutes and then says TIMED OUT

- **Cause:** a harness script failed to **load** — almost always a parse error,
  and in this repo usually a duplicate `var` name in `self_check.gd`'s one long
  function, or an untyped array literal iterated in a `for` (see *Invariants*).
  Godot does not exit on a parse error any more than on a failed `assert`: the
  scene tree keeps running with a dead script, so the harness waits out the
  900 s timeout for an error it wrote to its engine log in the first second.
- **Fix:** `Invoke-Harness` polls the engine log while it waits and fails the
  harness as **SCRIPT DID NOT LOAD** the moment `Parse Error`, `Compile Error`
  or `Failed to load script` appears. A green gate runs in ~30 s; this was
  adding 900 s per mistake, and it happened three times on 2026-09-16.
- **Before blaming the gate,** read `mythforge-<pid>-<scene>.log.engine` in the
  temp folder — the line is there.
- **Do not pick a replacement name by guessing.** `wm_src` collided, and so did
  the next guess, `chart_src`. `grep -c 'name' godot/tests/self_check.gd`
  first. And do not `sed -g` a rename across that file: the pre-existing
  `chart_src` got renamed along with the new one.

## A regex silently matches nothing

- **Cause:** `\uXXXX` is a JavaScript escape. Godot's RegEx is **PCRE2**, where
  it is not valid — the pattern compiles to something that never matches, with
  no error.
- **Fix:** put the literal character in the pattern (`•`, `—`, `–`, `"`, `"`).
  This was written twice before it stuck.

## A source-reading check fails on code that is obviously correct

**Symptom:** `ui_playthrough` reports "the road network is defined but never
called" while the call is right there in `world_map.gd`. The definition checks in
the same block pass, so the file was read fine.

- **Cause:** the check split the file on a **literal newline pasted inside the
  string**. `core.autocrlf` is `true` here, so the working tree is genuinely
  mixed — `world_map.gd` is LF, and any file rewritten by a tool in text mode
  becomes CRLF. A CRLF harness splitting an LF file yields **one** line, and
  every per-line match silently fails. Measured: `parts=1` against 692 newlines
  in the file.
- **Fix:** `split("\n")` — the escape, not a pasted newline. `strip_edges()`
  already removes a trailing `\r`, so the escape is correct on both. All three
  such splits in `ui_playthrough.gd` now use it.
- **It never shows in `git status`.** Git normalises on commit, so a whole-file
  CRLF conversion is invisible in the diff and the gate goes red with a clean
  tree — which reads exactly like a real regression.
- **Writing files from a script on this box:** open in binary, or pass
  `newline=""`. Python's default text mode rewrites every line ending in the file.

## "Lambda capture at index N was freed. Passed null instead."

- **A lambda that captures `self` is NOT the suspect.** Godot binds such a lambda
  to `self` and disconnects it automatically when the node frees — the connection
  dump prints it as `<anonymous lambda>(self lambda)`. Chasing those wastes the
  afternoon; the ones to look at print as plain `(lambda)`.
- **An `is_instance_valid()` guard cannot silence it.** The error is raised when
  the Callable is *invoked* with a dead capture, before the first line of the body
  runs. If you see the error and the guard both, the guard is working and the
  error is still real.
- **Fix by making the capture RefCounted**, not by guarding harder: hold the node
  in a one-element Array and test `arr[0]`. An Array is never "freed", so the
  guard does its job in silence.
- **Instrument:** dump `sig.get_connections()` and print `c["callable"]` — it
  reports `(self lambda)` vs `(lambda)`. Then put a `printerr` as the first
  statement of each candidate; the engine error prints immediately *before* the
  body, so the marker that follows the error names the caller, and the marker that
  precedes it names the caller's caller.

## llama.cpp aborts with "Rust cannot catch foreign exceptions" — SOLVED

**Upstream bug, fixed in `nobodywho-godot-v9.6.0`.** This project was pinned to
v9.5.0. Exit `0xC0000409`, no Godot stack, last worker line `Worker writing until
done`.

- **Cause:** NobodyWho ran the GBNF grammar **after** the truncation samplers
  (top-k/top-p/temperature). When truncation leaves no grammar-valid token,
  llama.cpp throws a C++ exception across the FFI boundary and Rust aborts.
  Upstream issues #421 and #487, fixed by PR #644.
- **Fix:** bump the pin in `scripts/fetch_nobodywho.py` **and**
  `installer/clean-room/check-downloads.ps1`, delete
  `godot/addons/nobodywho/libnobodywho-*.dll`, re-run the fetch. **Never pin
  below v9.6.0.**
- **The confound that cost six local runs.** It looked like "explicit
  `start_worker()` + a constrained sampler aborts, lazy start is fine". It is
  not: with a lazy start the first sampler config is *dropped* ("Worker not
  started"), so the first generation runs unconstrained and later constrained
  ones land in a context that happens not to collide. The trigger is
  content-dependent, so a same-variable bisection can point straight at the wrong
  thing while every arm reproduces.
- **The old section below is kept**: everything it says about what was ruled out
  locally is still true and still the right method — it simply could not reach a
  cause that lived upstream.

## What the local bisection ruled out (still valid method notes)

**Symptom:** exit `0xC0000409`, no Godot stack, the last worker line is
`Worker writing until done`.

- **Not the double BOS.** `check_double_bos_eos: … starts with 2 BOS tokens`
  appears **38 times in a `local_stack` run that exits 0** and prints
  `LOCAL STACK OK`. It is noise. Neither is it fixable from the game:
  `NobodyWhoModel` exposes only `model_path` and `projection_model_path`, and
  `NobodyWhoChat` only `model_node`, `system_prompt`, `allow_thinking`,
  `context_length` — there is no `add_bos_token` to set.
- **Measured cause (five runs, one variable each):** a **constrained** sampler —
  a `JsonSchema` or `Grammar` step — reaching a worker that has genuinely started,
  as that worker's first act. The same worker with an unconstrained builder chain
  generates for seven minutes without complaint, and once it has done one
  unconstrained turn, eleven `JsonSchema` configs land and work.
- **Read the sampler config out of the worker log before theorising.**
  `set_sampler_preset_json` looks grammar-free and is not: it installs a default
  GBNF `Grammar` step, which made one bisection arm prove the opposite of what it
  appeared to.
- **Method:** the whole thing was settled by one grep of a *passing* log and five
  single-variable runs. Every earlier theory came from reading a failing log only.

## A dialog's exit button walks off the bottom of the screen

**Symptom:** a panel opens fine, then reveals some content — a detail strip, a
longer page — and its exit button is *gone*. Escape does nothing, clicking
outside does nothing, nothing scrolls. Task Manager is the only way out. This
soft-locked the merchant counter for weeks (PL-7).

- **Cause, and both halves are needed to explain it:** a `Window` with
  `wrap_controls` only ever **grows** to its contents minimum and never shrinks
  back, and it grows **downward** from the origin `popup_centered()` fixed when
  it was shorter. Measured on the counter: 86 px of new content took the dialog
  from 541 px to **1002 px** against a contents minimum of **627**, putting the
  OK button at **y=875 on an 800 px screen**. The over-growth comes from a
  transient — a freshly-revealed autowrapped label measures ~1 px wide mid-layout
  and reports an enormous height — and the window keeps it forever.
- **Fix:** `Skin._cap_panel_content` calls `reset_size()` (re-fit to what the
  contents actually ask for) and then clamps `position` so the whole window is on
  screen, and it runs on `content.minimum_size_changed` — deferred, or it re-fits
  to the very transient that caused the problem — as well as on root resize.
- **Three earlier attempts failed because each was half the fix.** A re-fit alone
  still hangs off a stale origin; a clamp alone cannot place a 1002 px window on
  an 800 px screen. Both were reasoned from screenshots.
- **Why no harness saw it:** `click_driver` opened the shop and audited it — in
  the one state where nothing is wrong, because it never clicked a ware. And its
  on-screen check asked `b.get_viewport().get_visible_rect()`, which for a control
  inside a dialog **is the dialog**, and the dialog grows with the button. It now
  measures in root coordinates.
- **Headless lies about screen size.** With no window, the root viewport reported
  a square **1280x1280** — 480 px taller than the shipped 1280x800 — so every
  "does this fit on screen" question was being asked of a screen no player owns.
  `click_driver` now pins the root to the size in `project.godot`.

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

## A new world forges with no cast and no campaigns (PL-13)

> `WARNING: LocalGM: JSON generation exceeded its deadline after 53386 chars`

- **Cause:** llguidance, which compiles NobodyWho's JSON schemas, allows any run
  of whitespace between tokens and any extra key in an object. The copy step has
  no sampler, so once it starts padding it never stops. The DLL was NOT the cause
  — v9.6.0 was green on Aug 17; the forge prompt changed on Sep 17 and the new
  prose walked into the loop. The world also placed 0/7 places in a region
  ("Aquari Coast" vs "The Aquari Coast"), and the harness itself carried a
  stale copy of the location kinds that predated `settlement`.
- **Fix:** Worldsmith objects are closed, its copy step sends the schema on one
  line (`LocalGM.compact_schema`), regions are resolved at the forge. The world
  call went **252 s → 51 s**, cast 0 → 3, stories 0 → 2, placed 0/7 → 4/7.
- **Instrument:** the deadline warning prints the head and tail of what the
  worker wrote. That one line is what named the cause.

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
