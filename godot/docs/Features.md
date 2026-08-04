# What the game has

A coarse map of the systems, kept coarse on purpose.

This replaces a 107-row feature matrix that tracked every capability by hand.
It was audited on 2026-08-04 and **six of its eight "not started" rows were
wrong** — the GM forge, the persona forge, the campaigns shelf, multiclassing,
controller support and generated props all shipped while the matrix said they
had not been begun. A tracker nobody can keep true is worse than no tracker: it
looks like information.

So the rule changed. **The code is the record of what exists; the
[Backlog](Backlog.md) is the record of what is open.** This page is the
orientation between them, written at a grain that does not rot.

## The engine

| System | Where |
|---|---|
| Dice, checks, AC, XP, items, casting, rests | `Rules` |
| Initiative, attacks, enemy AI, death saves, the board | `Combat` |
| The flow FSM — 20 states, legal actions, legal transitions | `Mode` |
| Saves, state kinds, the adventure shelf, geography | `GameState` |
| The `[[tag]]` protocol and its prose fallbacks | `Tags` |

Every mechanical outcome is engine-owned. The model proposes through tags and
may not state a roll, an HP total, or a success — see [AI.md](AI.md).

## The AI

| System | Where |
|---|---|
| The narrator (streamed prose, tuned sampler) | `LocalGM.stream()` |
| Campaign memory (embeddings, cosine recall) | `LocalMemory` |
| Cast codex · quest log · world tick · chapters | `Chronicle` |
| Worlds, regions, campaigns from one idea | `Worldsmith` |
| World seeding: style, assets, creatures, NPCs | `Compiler` |
| Speech to text | `LocalGM.transcribe()` |
| Art | `Art` → stable-diffusion.cpp |

## Character and play

12 classes with usable per-level features · 9 heritages · 8 backgrounds ·
multiclassing · spellbooks with slots and save DCs · 13 equipment slots ·
inspiration · exhaustion · the full condition set · feats and ASI at milestones
· subclasses at 3 · death saves · short and long rests.

## The world

Six shipped worlds, pre-baked with items, creatures and painted art. Regions,
places, fog, travel with distance cost, and a GM that can charter new places
within a scope its level has earned — see [Backlog](Backlog.md) for what is
still open there, and `Rules.SCOPE_LEVEL` for the gate.

## Teaching

The forge ritual teaches hero-making. Four one-time hints teach what it cannot,
each at the moment the thing first happens: who rolls, what the board owns, what
the chart remembers, and the founding contract that the narrator may not decide a
number. `GameState.coach_once` is global rather than per-save, so a second
campaign does not re-explain the d20 bar; Settings can replay them.

## The shell

The Hall · five forges (hero, world, campaign, GM, companion) built on one
`ForgeFlow` · the Record (nine pages) · the Pack · the Atlas · the Lore Book ·
the Destiny constellation · Chronicles · a quiet table for companion chat ·
Settings.

## The interface

The Mythforge Design Language is the contract: tokens, the `Myth*` component
library, a drawn icon library with no fonts or emoji, motion with a
reduce-motion path for every animation, and the Environmental Art System behind
it all. [DesignSystem.md](DesignSystem.md) is law for anything that renders.

## Not built

Listed with the reason, in [Backlog.md](Backlog.md) — TTS, true 3D characters,
model-authored palettes, and co-op.
