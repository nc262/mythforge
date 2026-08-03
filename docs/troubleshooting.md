# Troubleshooting

RCAs for failures actually hit on this stack. Each one: symptom → root cause →
fix. A symptom with a guess instead of a root cause does not belong here.

## The game says it has no narrator

> "The storyteller has no voice yet — the NobodyWho extension is not installed."

- **Cause:** the GDExtension binary is gitignored (it is over GitHub's 100 MB
  per-file limit), so a fresh clone has the manifest but no DLL.
- **Fix:** `python scripts/fetch_nobodywho.py`, or run `scripts/install.ps1`,
  which does it as step 3.

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
