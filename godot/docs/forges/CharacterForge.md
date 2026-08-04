# PILLAR: The Character Forge

*A permanent first-class pillar of Mythforge — equal in weight to BG3's
character creator. Not a dialog. Not a form. The place where legends are
struck. This document is the full design package (deliverables 1-9);
implementation begins only after approval.*

---

## 1. Experience document

**Emotions: excitement · ownership · identity · anticipation.**

You are not filling in a character sheet. You are standing at an ancient
forge — runes on the anvil, embers rising, molten light on stone — and you
are hammering a legend out of raw metal. Every stage is a strike: heritage
rings, class throws sparks, the portrait cools into a face. The final
reveal is the quenching — steam, the name struck in gold, the finished
hero turning to face the road.

**Material identity:** ancient forge — dark iron, rune-cut stone, ember
drift, molten gold seams, starfield above the smoke. (Palette-driven:
Neonspire forges in neon plasma, Everyday at a craftsman's workbench.)

**The ritual beats:**

| Beat | What happens |
|---|---|
| Anticipation | From the main menu: "Character Forge" — the menu dims, embers begin to drift |
| Reveal | The cold anvil; "Every legend begins as raw metal." |
| Focus | One decision per stage, full-screen, nothing else competing |
| Interaction | Choice cards struck like hammer blows; the stage rail (rune-stones) lights as you advance |
| Reward | The Quenching: cinematic reveal — portrait large, name in gold, stats orbiting in, gear laid on the anvil |
| Graceful exit | "Begin the adventure" → the tale opens; or the forge banks its fire (draft kept) |

## 2. UX flow — the stages

```
The Cold Anvil (welcome)
  ↓
Origin            — Raw Metal (forge from nothing) · four Forged Legends
  |                 (prebuilts Brakka/Elara/Finch/Maren — pick one and jump
  |                 straight to the Quenching with everything filled)
  ↓
Ruleset           — one card today: "The Mythforge Rules" (engine-owned d20);
  |                 future slots visible as dim rune-stones (strict-5e,
  |                 homebrew) — destiny visible, not hidden
  ↓
Heritage          — choice cards from the heritages table (speed, traits)
  ↓
Class             — cards with class lore, hit die, casting; the forge fire
  |                 retints per class hovered (evocation ember, rogue violet…)
  ↓
Background        — the 8 backgrounds (skills + the hook that seeds memory)
  ↓
Nature            — 4d6 destiny (the dice moment, 6 tumbling) OR the standard
  |                 array with an assignable grid (pays that matrix debt)
  ↓
Appearance        — describe them in words (feeds the portrait prompt);
  |                 art-style chips (painted/ink/noir…) — pays the
  |                 art-style-picker (Backlog)
  ↓
The Portrait      — the commission begins HERE, async; the anvil shows a
  |                 cooling silhouette that resolves into the face when the
  |                 painting lands (evolving portrait, honest version);
  |                 ↻ re-strike (regenerate) with different style chips
  ↓
The Voice         — ⛔ no local voice engine yet: the stage EXISTS as a
  |                 dim rune-stone "awaiting the bards" (placeholder per the
  |                 no-simplification rule; wired when the provider wakes)
  ↓
Equipment         — class kits as card trios (e.g. Soldier's kit / Skirmisher's
  |                 kit / Scholar's kit) drawn from class presets + vendor
  |                 tables; the chosen kit lays out on the anvil
  ↓
The Quenching     — review + cinematic reveal; strike the name (input) if
  |                 unnamed; steam, gold flash, portrait framed
  ↓
Begin Adventure   — commits everything, hands off to the campaign/tale
```

Back/forward: every stage reachable backward via the rail; forward gated on
the stage's one decision. Esc = bank the fire (draft persists in-session).
Keyboard: arrows navigate cards, Enter strikes, full focus ring support.

## 3. Screen flow

One full-screen scene (`scenes/forge/character_forge.tscn`), NOT a dialog.
Stages are children swapped by the flow controller with MDL transitions
(reveal_children stagger; the rail persists across stages).

## 4. Wireframe (stage template + quenching)

```
┌──────────────────────────────────────────────────────────┐
│  ◆──◆──◆──●──○──○──○──○──○──○   (stage rail: rune-stones) │
│                                                            │
│              ✦  CHOOSE YOUR HERITAGE  ✦                    │
│                                                            │
│   [ card ]   [ card ]   [ CARD·selected ]   [ card ]       │
│    art top     …           gold rim, lifted    …           │
│    name        …           traits, speed       …           │
│                                                            │
│  ‹ back                                        strike ›    │
│  (embers drifting; anvil silhouette at the base)           │
└──────────────────────────────────────────────────────────┘

THE QUENCHING:
┌──────────────────────────────────────────────────────────┐
│                 (steam · gold flash · sting)               │
│                    ┌──────────────┐                        │
│                    │   PORTRAIT   │  ← breathes            │
│                    └──────────────┘                        │
│                  W R E N   A S H V A L E                   │
│           Half-Elf Wizard · Sage of Embervale              │
│   STR 8 · DEX 14 · CON 12 · INT 17 · WIS 12 · CHA 10       │
│   ⚔ Silvered Dagger  🥋 Traveler's Leathers  🧪 potions     │
│                                                            │
│              [ ⚒ BEGIN THE ADVENTURE ]                     │
└──────────────────────────────────────────────────────────┘
```

## 5. Visual mockups

Per MDL practice the mockup medium is the engine itself: milestone F1 ships
the shell + welcome + one content stage and STOPS for a screenshot review
gate (MF_SHOT_FORGE harness mode) before further stages are built. The
component gallery gains MythChoiceCard and MythStageRail first.

## 6. Data flow

- The manager holds a **draft** dictionary; NOTHING persists until the
  Quenching commits. Cancel = no orphaned state.
- Commit: `GameState.set_sheet` (name/race/cls/background/abilities/HP/
  gold/spells/slots/features) → `inv` kit PUT → `Art.ensure_hero_portrait`
  (already queued from the Portrait stage) → **memory seed**: background
  hook + appearance line posted as the campaign's first beat → relationships
  seed (background-suggested contact into codex, F5).
- Reads: `tables.json` (heritages/backgrounds/class_presets/feats),
  `class_lore.json`, `spells.json`, vendor tables for kits.

## 7. Architecture

- `scenes/forge/character_forge.tscn` + `character_forge.gd` — **the
  CharacterForgeManager**: a flow-controller node owning the stage FSM
  (array of stage builders, back/forward, rail state, draft, commit).
  No game.gd involvement; main_menu launches it, it hands off on commit.
- `Mode` gains a declared `CharacterForge` state (allowed: edit_hero,
  navigate; to: Loading, MainMenu).
- The existing in-game hero-forge dialog is REPLACED by launching this
  scene (matrix rule: absorbed, not deleted — same entry points).

## 8. Component requirements (MDL-first — built in the gallery before use)

| Component | Contract |
|---|---|
| `MythChoiceCard` | The large decision card (art/glyph top, title, body, footnote); selected = gold rim + lift; keyboard focusable; `chosen(payload)` signal. Serves heritage/class/background/kits/themes — both Forges share it. |
| `MythStageRail` | The journey's rune-stones: n stages, lit/current/dim, click-back navigation, pulse on advance. Shared by both Forges. |
| Forge backdrop | Ember drift + anvil silhouette; reuses backdrop.tscn + palette tint + glow_tex embers (no new asset pipeline). |

## 9. Implementation milestones

| # | Scope | Gate |
|---|---|---|
| **F1** | MythChoiceCard + MythStageRail (gallery), forge scene shell + rail + welcome + Heritage/Class/Background stages wrapping existing data, Quenching commit path replacing the hero-forge dialog, main-menu pillar button | screenshot review |
| **F2** | Origin stage (Raw Metal + four Forged Legends), Ruleset stage, Equipment kits | harness green |
| **F3** | Appearance + evolving Portrait stage (style chips, re-strike) | screenshot review |
| **F4** | Nature stage: 4d6 dice moment + standard array assignable grid | self-check rows |
| **F5** | Voice placeholder stage, cinematic Quenching polish (steam/flash/sting), memory + relationship seeds | full ritual review |

Outputs registry (Backlog): character · portrait · starting
inventory · stats · background · relationships seed · memory seed ·
3D model (future, FutureIdeas).
