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

## Hard rules / gotchas (don't relearn these)
- **A grammar and a sampler chain REPLACE each other** in NobodyWho, so a
  schema-constrained call runs with no top-k/top-p/temperature/penalties. Never
  let one call both invent and serialise — think in prose, then serialise. This
  cost three wrong diagnoses before it was measured; see
  [godot/docs/LocalLLM-Tuning.md](godot/docs/LocalLLM-Tuning.md).
- **The narrator must be the only thing on the card when it loads.** llama.cpp
  fixes its GPU/CPU split once, at load time, and keeps it for the life of the
  process. A resident image stack cost 19.3 s per turn; with nothing else on the
  card it is **3.7 s**. sd-server idles at 118 MB because it loads per request.
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

## Workflow before changing anything
DISCOVER → PLAN → CHALLENGE → EXECUTE → VERIFY → REVIEW → IMPROVE.

## Verifying changes
Five harnesses, run from the repo root. The first three are offline
(`Api.test_mode`); the last two drive the real model.

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
