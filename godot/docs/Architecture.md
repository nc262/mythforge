# Architecture

**The game is the whole application.** One executable, one optional helper
process, and a folder of save files. No server, no login, no session, no
database, no cloud.

```
Mythforge.exe ──────────────────────────────────────────────┐
  Godot 4.7 · GDScript                                      │
  NobodyWho (GDExtension) → llama.cpp → Vulkan              │
    · the narrator          · campaign memory (embeddings)  │
    · the cast codex        · the quest log                 │
    · the world tick        · the Worldsmith                │
    · the World Compiler    · speech-to-text                │
  saves · chapters · memory · art  →  user://               │
└──────────────────┬─────────────────────────────────────────┘
                   │  POST /v1/images/generations
                   ▼
      sd-server.exe  127.0.0.1:8189   (stable-diffusion.cpp, Vulkan)
```

The image engine is a separate process because it is one: stable-diffusion.cpp
serves the OpenAI image API itself, so `Art` POSTs to it directly and decodes the
base64 PNG. It is optional — shipped worlds carry pre-baked art.

## Lifecycle

Double-click the exe; it is up. There is nothing to start first and nothing left
running afterwards — the model lives in this process and dies with it, and the
save files are already on disk.

The image engine is the one exception, and the game does not own it:

```bash
pwsh scripts/start-image-sdcpp.ps1
```

`Services.warm_art()` probes `:8189/v1/models` in the background from the Hall so
the first portrait doesn't pay for the handshake. Nothing awaits it. If the
engine is not up, art requests fail to a text line and play continues.

## Autoload singletons

| Autoload | File | Owns |
|---|---|---|
| `Mode` | state_manager.gd | the flow FSM: 20 states, allowed actions, legal transitions |
| `Services` | services.gd | waits for the image engine; nothing else to wait on |
| `Ui` | skin.gd | design tokens, runtime Theme, per-world palettes, reduce-motion |
| `Api` | api_client.gd | the harness stub surface, and the Worldsmith entry point |
| `GameState` | game_state.gd | the adventure, its state kinds, rests, economy |
| `Rules` | rules_engine.gd | pure math: dice, checks, AC, XP, items, casting |
| `Tags` | tag_parser.gd | the `[[tag]]` protocol parser + prose fallbacks |
| `Composer` | prompt_composer.gd | the per-turn envelope and the GM persona |
| `Combat` | combat.gd | initiative, attacks, enemy AI, death saves, XP |
| `Chronicle` | chronicle.gd | memory beats, recall, codex, quests, world tick, chapters |
| `Art` | art_cache.gd | the image client, the `user://art` cache, the paint queue |
| `Compiler` | world_compiler.gd | seeds a world: style guide, assets, creatures, NPCs |
| `LocalGM` | local_gm.gd | the narrator, structured JSON, speech-to-text |
| `LocalMemory` | local_memory.gd | embeddings, cosine recall, per-adventure stores |
| `Worldsmith` | worldsmith.gd | forges a world or a campaign from an idea |
| `WorldSkin` | world_skin.gd | per-world palette, currency, art direction |
| `Sfx` · `Pad` | sfx.gd · pad.gd | synthesized audio; gamepad mapping |

## Scenes

`main_menu.tscn` is the entry point — the Hall. From there: worlds, the forges,
campaigns, chronicles, companions, settings, and `game.tscn` (the table:
bubbles, panels, combat, dice). Harnesses live in `tests/`.

## Where state lives

| What | Where |
|---|---|
| a save | `user://saves/<adventure-id>.json` |
| the shelf (which adventures exist) | `user://saves/adventures.json` |
| campaign memory (beats + vectors) | `user://memory/<adventure-id>.json` |
| chapters (save-points) | `user://chapters/<adventure-id>.json` |
| banked heroes | `user://heroes.json` |
| generated art + sidecars | `user://art/` |
| settings (chosen narrator, UI prefs) | `user://session.cfg` |

State is per-adventure **kinds**: `sheet, inv, combat, clock, quests, codex,
bmap, gm, world, notes` (plus a `_global` shelf for custom worlds and stories).
`GameState.save_kind()` writes the file on every mutation. Every write is
write-then-rename — a crash mid-save must not leave a truncated file that still
parses as an empty campaign.

## A turn, end to end

1. The player types. `game.gd` frames the line.
2. `Chronicle.recall()` embeds it and returns the most relevant past beats by
   cosine similarity — by meaning, not recency.
3. `Composer.envelope()` rebuilds the whole situation: sheet, scene, clock,
   inventory, cast, quests, recalled beats, the tag protocol, the language pin.
4. `LocalGM.stream()` resets the context and asks. Tokens arrive on
   `response_updated` and are re-emitted as `Api.sse_delta`, so the tag
   pipeline, the language gate and Chronicle are unchanged from when a server
   streamed them.
5. On done: `Tags.parse` → world tags mutate `GameState` → a check tag arms the
   roll bar → `Rules.resolve_check` streams the result back as the next message.
6. `Chronicle.record()` stores the beat and, every sixth turn, updates the codex
   and the quest log.

Each turn is **stateless by design**. The envelope already carries the whole
situation, so letting the chat also accumulate history sends all of it twice and
grows without bound — measured, turn 2 once cost *more* than turn 1 (51.7 s vs
41.6 s) because the second envelope pushed past the context window.

## The AI boundary (constitutional)

The model may narrate, speak NPCs, describe, and propose mechanics **via tags**.
The model may not state numeric outcomes, decide rolls, or change state.

Enforced three ways: the protocol text sits in every envelope; every mutation
path goes through a typed tag handler; and the prose-regex fallbacks exist only
for roll-calls and combat-starts, never for a state change without a tag.

## The rule that governs every model call

A grammar and a sampler chain **replace each other** in NobodyWho, so a
schema-constrained call runs with no top-k, no top-p, no temperature and no
repetition penalty. Never let one call both invent and serialise: think in prose
with the tuned sampler, then use a small schema to give that prose fields. The
measurements and failure modes are in [LocalLLM-Tuning.md](LocalLLM-Tuning.md) —
read it before touching a model call.

## What the game deliberately does not have

No HTTP client for anything but the image engine. No auth, accounts or sessions.
No SQL. No Python at runtime. No fallbacks to a server: if the narrator's model
is missing the game says so, because a quiet second path only hides the fault.

CI enforces the first of those — a `"/api/` string in any `.gd` file fails the
build.
