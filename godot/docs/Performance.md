# Performance

Measured on a Radeon RX 7900 GRE with Llama 3.1 8B Instruct Q4_K_M, in-process
through NobodyWho on Vulkan. Numbers are from `tests/bench_gm.tscn` and
`tests/local_stack.tscn`, which drive the real model — the other harnesses are
offline and cannot tell you anything about speed.

## Where the time goes

| | |
|---|---|
| GM turn, warm | **3.7 s** |
| memory: store 3 beats / recall | 228 ms / 4 ms |
| cast codex | 1.2 s |
| quest log | 1.4 s |
| world tick | 1.6 s |
| Worldsmith `ask_back` | 1.5 s |
| a whole world forged (six calls) | 56.6 s |
| one 512×512 image | 4.8 s |

The first turn after launch is slower than 3.7 s: the ~4.6 GB model loads on the
first call unless `start_worker()` has already run. `LocalGM._ensure_nodes()`
calls it at construction for exactly that reason — a model load buried inside
the player's first sentence is the one turn where the game most needs to look
alive.

## The two decisions that made the difference

**Nothing resident on the card but the narrator.** A GM turn measured 19.3 s
when a CUDA-shimmed image stack held ~7.4 GB of VRAM: the model loaded with a
third of its layers on the CPU and stayed that way for the life of the process,
because a llama.cpp GPU/CPU split is fixed at load time. stable-diffusion.cpp
idles at **118 MB** — it loads its checkpoint per request instead of staying
resident — and the same turn measures **3.7 s**. A fully-resident 8B beats a
half-offloaded one by more than any prompt tuning can.

**Never one call that both invents and serialises.** The Worldsmith's world-core
call took 95.8 s and failed; split into a prose call plus a schema call it takes
1.5 s. The reason is in [LocalLLM-Tuning.md](LocalLLM-Tuning.md) and it is not a
speed trick — a grammar and a sampler chain replace each other, so the slow path
was also the bad one.

## Prefill is not the bottleneck

Prompt evaluation measures ~0.15 s for a full envelope. Time-to-first-token is
not spent on the prompt, which means prompt-shrinking and prefix-cache work are
optimising the wrong end. What the player waits for is **generation**, and the
lever on generation is output length: at the rate this box generates, 300 tokens
*is* most of the turn. Shorter beats are both faster and better pacing, which is
why reply length is a player-facing knob rather than a constant.

Each turn is deliberately stateless — `LocalGM.stream()` resets the context and
the envelope carries the whole situation. Letting the chat also accumulate
history sends all of it twice: measured, turn 2 once cost *more* than turn 1
(51.7 s vs 41.6 s) because the second envelope pushed past the context window.

## The image engine

`--vae-tiling` is load-bearing, not tuning. Without it the VAE decode asks for a
Vulkan buffer past this device's limit, falls back to a slow path, and spends
36.2 s of a 50.4 s image. Tiled: 3.1 s decode, 19.9 s image, pixel-identical at
the same seed. It must be set in every launch path.

sd-server also **ignores `steps` in the request body** — steps are a launch flag
or nothing.

## The rule that keeps it fast

**If it can be known before play, it is painted before play.** Runtime
`Art.ensure` is for the genuinely emergent: a loot item the GM invented this
turn, a scene of a place that did not exist a minute ago.

This is not a style preference. The jobs that once half-offloaded the model were
**vendor stock icons** — eleven fixed names per world family, sitting in a static
table, identical for every player, fully known at build time, painted one at a
time on the player's GPU at ~22–27 s each the first time a shop opened. They are
baked now. `Art.hold` covers what is left: the queue pauses for the length of a
stream so a burst of icons cannot run across a narration call.

Still open on that rule:

| # | Item | E |
|---|---|---|
| A1 | Audit every runtime `Art.ensure` call and move each into the compiler unless it is genuinely emergent | M |
| A2 | Replace the background compile with a "preparing the world" ceremony that finishes before play opens, with real per-stage progress | M |
