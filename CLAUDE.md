# CLAUDE.md — Mythforge

Project context for AI-assisted work on this machine. Read this first, then the
relevant file in `godot/docs/`.

## What this is
A single-player desktop RPG: a Godot 4.7 game whose Game Master is a local LLM.
No server, no account, no cloud. One executable, one optional image engine, a
folder of save files.

## Architecture in one paragraph
**The game is the whole application.** `Mythforge.exe` runs llama.cpp in its own
process through the **NobodyWho** GDExtension (Vulkan, on an AMD RX 7900 GRE
here): the narrator, campaign memory (embeddings + cosine recall), the cast
codex, the quest log, the world tick, the Worldsmith, the World Compiler and
speech-to-text. Saves are JSON files under `user://`. The one other process is
**stable-diffusion.cpp** on `:8189`, which serves the OpenAI image API itself, so
the game POSTs to it directly. See
[godot/docs/Architecture.md](godot/docs/Architecture.md).

## MEASURE FIRST. NEVER GUESS.

**Before writing a fix, state the measurement that identifies the cause.** Not
the mechanism you find plausible — the number, the log line, the pixel count, the
printed value. If you cannot name one, you do not know the cause yet, and
**getting an instrument is the task** before the fix is.

Four things that follow, each of which cost a wasted cycle here:

1. **Confirm the instrument runs before trusting what it says.** An `_exit_tree`
   fix for the audio leak was written, shipped through a gate, and moved nothing
   — the `print()` inside it had never fired, because `_exit_tree` does not run
   for an autoload on that quit path. The hook was wrong, not the logic, and one
   `print()` first would have said so.
2. **A fix that does not move the number is not a fix.** Revert it. Do not leave
   it behind a comment claiming it fixed something. A change that moves no pixel
   is a change to delete.
3. **Never reason from the same weak evidence twice.** Two PL-7 fixes were
   inferred from screenshots and both missed. The second one was the mistake; the
   first was a guess, the second was a habit.
4. **Record the negative result where the next attempt will read it** — the
   backlog row, or a comment at the code. "`_exit_tree` never fires here" and
   "the cap is 876 px against 600 px of content" are worth more than another
   plausible theory.

Three separate wrong diagnoses in this project's history were each settled in
minutes by *rendering it, printing it, or counting it* — and every one of them
had a confident explanation attached first. See
[docs/troubleshooting.md](docs/troubleshooting.md).

## Hard rules / gotchas (don't relearn these)
- **A grammar and a sampler chain REPLACE each other** in NobodyWho, so a
  schema-constrained call runs with no top-k/top-p/temperature/penalties. Never
  let one call both invent and serialise — think in prose, then serialise. This
  cost three wrong diagnoses before it was measured; see
  [godot/docs/LocalLLM-Tuning.md](godot/docs/LocalLLM-Tuning.md).
- **Two different rules, and the docs carried only the first for a year.**
  (1) llama.cpp fixes its GPU/CPU split once, at load time. The narrator needs
  **~5.9 GB**; leave it less and layers land on the CPU for the life of the
  process — that is the 19.3 s per turn against 3.7 s, and the tenant that caused
  it was a CUDA-shimmed ComfyUI-Zluda holding 7.4 GB, not sd-server.
  (2) **Do not paint while the narrator talks.** Measured three ways below; the
  load-order rule turns out not to bind for sd-server at all, and concurrency
  does.

  | | turn 1 | 2 | 3 | … | 6 |
  |---|---|---|---|---|---|
  | narrator alone, clean card | 3.0 s | 3.5 s | 3.5 s | | |
  | engine already holding 6.6 GB at narrator load | 3.3 s | 3.6 s | 3.5 s | | |
  | engine generating 1024×1024 during the turns | 3.9 s | 4.4 s | 4.6 s | … | **6.1 s** |

  Peak VRAM in that last run was 15310 MB of 16384 — it never ran out, so nothing
  was evicted. They were contending for shaders, not memory. `Art.hold` in
  [godot/scripts/game.gd](godot/scripts/game.gd) already holds the art queue for
  the whole stream; that table is what the flag is worth.

  **What costs the card is the FIRST IMAGE, not the engine.** Two wrong answers
  were written here before anyone sampled the GPU counter, so here is the counter
  (`\GPU Adapter Memory(*)\Dedicated Usage`, summed, RX 7900 GRE):

  | moment | dedicated VRAM |
  |---|---|
  | nothing running | 2271 MB |
  | sd-server listening, never asked for an image | 2398 MB |
  | immediately after its first image | 8989 MB |
  | 20 s idle after that image | 8977 MB |
  | after killing sd-server | 2264 MB |

  So an idle engine costs **127 MB**, it takes **6.6 GB on first generation**, and
  it **never gives that back** while the process lives. Killing it reclaims all
  of it.

  Both earlier claims misread the same log line. sd-server prints
  `total params memory size = 6624.11MB (VRAM 6624.11MB, RAM 0.00MB)` *before*
  `listening on:` — but that is an allocation PLAN, not a transfer. It reaches
  "listening" in **0.8 s**, which is far too fast to have moved 6.6 GB, and the
  `model_loader.cpp:1305 - loading tensors completed` lines land afterwards,
  during the first request. Reading RSS was one trap; reading the plan line as a
  completed load was the second, and the second was written while correcting the
  first.

  So THE ORDER THAT MATTERS is narrator-loads-before-first-image, not
  narrator-loads-before-engine-starts. Having the engine merely *up* is nearly
  free. `_open_the_adventure` starts it after `LocalGM.warm()` returns, which
  satisfies the real rule with room to spare.
- **`--vae-tiling` is load-bearing, not tuning.** Without it the VAE decode asks
  for a Vulkan buffer past this device's limit, falls back to a slow path, and
  eats 36.2 s of a 50.4 s image. Tiled: 3.1 s decode, 19.9 s image,
  pixel-identical at the same seed. Set it in **every** launch path. Also:
  sd-server **ignores the `steps` field in the request body** — steps are a
  launch flag or nothing.
- **Godot's RegEx is PCRE2**, where `\uXXXX` is not an escape. A pattern using it
  compiles and then silently matches nothing. Use the literal character.
- **The models are matched by NAME, not position.** The encoder and the whisper
  model live in the same folder as the narrator; picking the wrong one fails
  silently rather than loudly.
- **If an image stack you did not start comes back**, something is supervising
  it: a pm2 app that polls the port and relaunches (needs `pm2 save`, or
  `dump.pm2` restores it), and a logon script in the Startup folder pointing at a
  different checkout entirely. Check both before believing a kill worked.

## READ THIS BEFORE YOU FIX ANYTHING
[godot/docs/Invariants.md](godot/docs/Invariants.md) — the rules that hold across
the whole repo, each with the check that enforces it.

It exists because this codebase carries **147** references to past incidents and,
before it, **21** checks. The knowledge was written down every time and enforced
almost never, so the same root cause kept surfacing somewhere new — five times in
one day: an art key that did not carry its world (four prefixes), a package-vs-cache
fallback hand-spelled at five sites in three ways, a progress report the forge never
got although the character screen had it, a style anchor nobody trimmed.

**Every one was already documented at the site of the fix.** A comment is only
discoverable if you are already reading that file, which is exactly when you no
longer need it. So:

> **An RCA comment without a check is unfinished work.** When you write "this cost
> us X", write the assertion in the same commit and add the row to Invariants.md.

## Workflow before changing anything
DISCOVER → PLAN → CHALLENGE → EXECUTE → VERIFY → REVIEW → IMPROVE.

**`/next` runs that loop by itself** — it pulls the top item off
[Backlog.md](godot/docs/Backlog.md), works it, gates it, commits it, and takes
the next one, without asking what to do next. `/loop /next` runs it unattended.
The skill carries the short list of things that genuinely stop for a human
(taste, anything irreversible, money, a windowed GPU render); everything else it
decides and says what it decided. Unknowns about the world go to the
`researcher` agent instead of to you. See
[.claude/skills/next/SKILL.md](.claude/skills/next/SKILL.md).

## Verifying changes
**One command is the gate:**

```
pwsh scripts/verify.ps1          # offline harnesses → export → Desktop copy
pwsh scripts/verify.ps1 -Full    # + the two that drive the real model
pwsh scripts/verify.ps1 -Audit   # + the windowed body audit (~4 min)
```

It refuses to export when anything is red, which is the only reliable way the
Desktop copy stays honest. Underneath it are five harnesses over the game, run
from the repo root. The first three are offline (`Api.test_mode`); the last two
drive the real model.

```
<godot> --headless --path godot res://tests/self_check.tscn      # rules, prompts, parsers
<godot> --headless --path godot res://tests/click_driver.tscn    # every station reachable
<godot> --headless --path godot res://tests/ui_playthrough.tscn  # a real game, scripted
<godot> --headless --path godot res://tests/local_stack.tscn     # REAL models + GPU
<godot> --headless --path godot res://tests/bench_gm.tscn        # turn latency + repetition
```

`local_stack` and `bench_gm` are the only ones that can tell you an answer is
*good*, not merely well-shaped. **Re-export after any `godot/**` change** or you
are testing a stale exe, and copy it to the Desktop — that copy is the one that
gets played.

A sixth harness tests the **published download** rather than the game, in a
container with no credentials — because none of the five can see a release whose
*artifacts* are wrong. Run it before and after publishing:

```
pwsh installer/clean-room/run.ps1
```

Image engine: `pwsh scripts/start-image-sdcpp.ps1`; `curl :8189/v1/models`.

## Local services & ports
| Port | Service |
|---|---|
| `8189` | stable-diffusion.cpp (image engine, Vulkan) — **the only one** |

The game itself listens on nothing.

## The docs that matter
| Doc | Covers |
|-----|--------|
| [godot/docs/Architecture.md](godot/docs/Architecture.md) | What runs where, and what the game deliberately does not have |
| [godot/docs/LocalLLM-Tuning.md](godot/docs/LocalLLM-Tuning.md) | **Read before touching a model call.** Sampler/grammar limits, with numbers |
| [godot/docs/AI.md](godot/docs/AI.md) | The tag protocol, the envelope, the model boundary |
| [godot/docs/Performance.md](godot/docs/Performance.md) | Where the time goes, measured |
| [godot/docs/Testing.md](godot/docs/Testing.md) | The five harnesses, and what each can and cannot prove |
| [godot/docs/DesignSystem.md](godot/docs/DesignSystem.md) | The visual contract. Law for anything that renders |
| [godot/docs/Features.md](godot/docs/Features.md) | The coarse map of what the game has |
| [godot/docs/Invariants.md](godot/docs/Invariants.md) | **Repo-wide rules and the check enforcing each.** Read before fixing anything |
| [docs/troubleshooting.md](docs/troubleshooting.md) | RCAs, symptom → root cause → fix |
| [docs/code-style.md](docs/code-style.md) | Conventions for the game and the tooling |

## Where a piece of work belongs
One home each, so nothing is tracked twice or lost between two lists:

| | |
|---|---|
| [Backlog.md](godot/docs/Backlog.md) | **Everything open.** If it could be worked on, it is here |
| [KnownIssues.md](godot/docs/KnownIssues.md) | Limitations that will **not** be fixed, with the reason |
| [TechnicalDebt.md](godot/docs/TechnicalDebt.md) | Deliberate shortcuts, each with its ceiling and upgrade path |
| [Testing.md](godot/docs/Testing.md) | What the harnesses prove, and the coverage gaps |

A 107-row feature matrix used to sit alongside these. It was audited on
2026-08-04 and six of its eight "not started" rows were wrong — the code is the
record of what exists, and a hand-maintained tracker that drifts is worse than
none, because it looks like information.
