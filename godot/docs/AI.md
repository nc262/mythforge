# AI Integration

## Roles
- **Narrator/GM** (streamed): the persona's stored system prompt (composed at
  adventure creation) + a per-turn envelope. Model: the session's endpoint
  (Ollama local; user-selectable — settings model picker is roadmapped).
- **Extractors** (background, constrained JSON): codex, quests, memory
  summary, worldsmith, snapshots — routed via backend `_extractor_model`.
- **Embeddings**: all-minilm via Ollama for pinpoint campaign memory.
- **Images**: SDXL through the ComfyUI bridge (`/generate`), art styles =
  checkpoints.

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
Rules stated to the model: one tag per effect, own line, never write dice
results/HP/success in prose. Verified live: qwen-class local models comply;
`Tags.detect_check` + `detect_combat_start` (ported denylist regexes) catch
prose-only turns.

## Envelope anatomy (per DM turn)
`[SHEET live summary]` `[clock/weather]` `[pack]` `[spellbook]`
`[recalled beats]` `[cast codex]` `[active quests]` `[GM style directive]`
`[MECHANICS PROTOCOL]` + player message. Companion (non-DM) chat sends the
raw message only.

## Prompt composition
- World GM persona: `Composer.compose_world_gm(world, story)` — identity,
  lore, locations, cast, campaign premise/hook, craft rules.
- Tone: Session Zero knobs (humor/spice/grit/pace/rules, 0-100) →
  `Composer.gm_directive()` low/high phrases, ≤25 / ≥75 thresholds.
- Asks: learn-spell / recruit framed as bracketed GM adjudications that may
  grant via tags — the engine never grants on the ask alone.

## Failure handling
75s idle watchdog aborts stalled streams and re-enables input; empty replies
render "The GM falls silent"; ↻ retell re-streams the identical framed
message; image generation failures degrade to text with a system line.

## Cost/perf notes
First token on the local 3B–14B models ≈ 5–50s; envelope kept ≤ ~2.5k chars;
extractors batched every 6 player turns; one image generation in flight per
subject (Art cache + `_generating` guard).
