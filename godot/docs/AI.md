# AI Integration

Every language-model call in this game happens **inside the game's own process**,
on llama.cpp through the NobodyWho GDExtension, on the same Vulkan device that
draws the frame. Nothing is sent anywhere.

## Who does what

| Job | Where | Shape |
|---|---|---|
| The narrator | `LocalGM.stream()` | streamed prose, tuned sampler |
| Campaign memory | `LocalMemory` | embeddings + cosine recall |
| Cast codex · quest log · world tick | `Chronicle` | prose → schema |
| Chapters (save-points) | `Chronicle.save_chapter()` | prose → schema |
| Worlds and campaigns | `Worldsmith` | prose → schema, per stage |
| World seeding (style, assets, creatures, NPCs) | `Compiler` | prose → coerce |
| Voice input | `LocalGM.transcribe()` | whisper |
| Art | `Art` → sd.cpp `:8189` | the one out-of-process call |

## Models

`.gguf` files in `user://models`, matched by NAME rather than by position — the
folder holds several, and picking the wrong one fails silently rather than loudly.

| Role | Matched on | Default |
|---|---|---|
| narrator | anything not matching the others; Settings picks | Llama 3.1 8B Instruct Q4_K_M |
| memory encoder | `embed`, `minilm`, `nomic`, `bge`, `gte`, `e5-` | nomic-embed-text v1.5 |
| voice | `whisper`, `stt`, `ggml-base/small/tiny` | ggml-base.en |

Each is optional and each degrades honestly: no narrator and the game says so and
refuses to open a tale; no encoder and recall returns nothing rather than
guessing; no voice model and the mic says where to put one.

## The one rule

**Never let a single call both invent and serialise.** A grammar and a sampler
chain replace each other, so a schema-constrained call runs with no top-k,
top-p, temperature or repetition penalty — fine for extraction, catastrophic for
invention. Think in prose first, then serialise with a small schema.

Measurements, failure modes, and the cases where a schema is the wrong tool
entirely: [LocalLLM-Tuning.md](LocalLLM-Tuning.md).

## The MECHANICS PROTOCOL (tag grammar)

Sent in every DM envelope. The GM proposes; the engine disposes.

```
[[check ability=DEX skill=Stealth dc=13 adv=1]]   [[attack ac=14]]
[[damage roll=2d6+3]]  [[heal roll=1d8+2]]
[[gold delta=+15]]     [[loot name="Iron Dagger" rarity=common]]
[[spell-learned name="Misty Step"]]   [[time advance=1]]
[[xp delta=50 reason="…"]] (never for kills — combat XP is engine-paid)
[[combat-start foes="goblin x3, boss"]]  [[combat-end]]
[[scene place="the chapel crypt"]]    [[companion name="Ser Aldric"]]
```

One tag per effect, on its own line, and never a dice result, HP total or
success/failure in prose. `Tags.detect_check` and `detect_combat_start` catch
turns where the model narrates a roll instead of calling for one.

## Envelope anatomy (per DM turn)

`[Director framing]` `[SHEET live summary]` `[scene]` `[clock/weather]` `[pack]`
`[spellbook]` `[recalled beats]` `[cast codex]` `[active quests]`
`[GM style directive]` `[house rules]` `[MECHANICS PROTOCOL]` `[LANGUAGE pin]`
+ the player's line.

The language pin sits **last**, immediately before the player's message, because
recency wins in a long context — burying it is how the GM started answering in
another language.

## Prompt composition

- **World GM persona** — `Composer.compose_world_gm(world, story)`: identity,
  lore, locations, cast, campaign premise and hook, craft rules. Rebuilt from the
  local world every turn, deliberately, so the forge and the table cannot drift.
- **Tone** — Session Zero knobs (humor/spice/grit/pace/rules, 0–100) become
  `Composer.gm_directive()` phrases at the ≤25 / ≥75 thresholds.
- **CRAFT** — includes *"OPEN ON WHAT CHANGED — not weather, light, smell, or the
  time of day."* That one line took atmosphere openings from 3/3 to 0/3 in
  `bench_gm`. Without it "vivid" means "paint the room" to an 8B model, and every
  reply opens the same way.

## Failure handling

An idle watchdog aborts a stalled stream and re-enables input; an empty reply
renders "The GM falls silent"; ↻ retell re-streams the identical framed message;
a failed image degrades to text with a system line. A structured call carries a
deadline and discards its worker rather than reusing one in an unknown state.

## Performance

Measured on an RX 7900 GRE with Llama 3.1 8B Q4_K_M — see
[Performance.md](Performance.md) for the full table.

| | |
|---|---|
| GM turn, warm | 3.7 s |
| memory: store 3 beats / recall | 228 ms / 4 ms |
| codex · quests · world tick | 1.2 s · 1.4 s · 1.6 s |
| a whole world forged | 56.6 s |
| one 512×512 image | 4.8 s |
