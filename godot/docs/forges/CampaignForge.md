# PILLAR: The Campaign Forge

*A permanent first-class pillar of Mythforge. Not "New Game" — the war
table where a Dungeon Master prepares a legendary campaign. Full design
package (deliverables 1-9); implementation begins only after approval.*

---

## 1. Experience document

**Emotion: you are the Dungeon Master on the eve of the first session.**

A candlelit war table. Maps weighted open at the corners, a compass, wax,
miniatures waiting at the table's edge. You name the campaign, choose its
darkness and its voice, set the table rules — and then you watch the world
FORGE ITSELF in front of you: the map inks in, the cast's faces arrive one
by one, the first settlement lights its lamps, the opening scene seals
itself in wax. By the time you sit down to play, you have already watched
your world be born.

**Material identity:** war table — dark wood, candlelight, parchment maps,
brass compass, wax seals, scroll ribbons, constellations through the
window. (Palette-driven per world theme.)

**The ritual beats:**

| Beat | What happens |
|---|---|
| Anticipation | "Campaign Forge" from the main menu; candles gutter up |
| Reveal | The empty war table — one blank map, one quill |
| Focus | One decision per stage; the table accumulates your choices as physical objects (name on a ribbon, theme as a map corner, options as house-rule cards) |
| Interaction | Choice cards + the accumulating table |
| Reward | **The Forging**: staged generation where every artifact lands visibly — world seal → cast faces → settlement lamp → opening scene scroll |
| Graceful exit | "Begin the campaign" opens the tale at the intro scene; or snuff the candles (draft banked) |

## 2. UX flow — the stages

```
The War Table (welcome)
  ↓
The Name          — name the campaign, or "let the world name itself"
  |                 (worldsmith titles it during the Forging)
  ↓
Ruleset           — shared card with the Character Forge ("The Mythforge
  |                 Rules" today; future rune-stones dim but visible)
  ↓
Theme             — eight cards: Dark Fantasy · High Fantasy · Horror ·
  |                 Political Intrigue · Norse · Pirates · Steampunk ·
  |                 Sci-Fi — each maps to pillar presets + palette + art
  |                 seasoning for the worldsmith; "Advanced: the five
  |                 pillars" MythFold absorbs today's pillar form verbatim
  ↓
The GM's Voice    — Classic DM · Narrative · Hardcore · Sandbox · Cinematic
  |                 → preset bundles over the existing Session-Zero knobs
  |                 (humor/spice/grit/pace/rules) + an envelope directive
  |                 line; "Tune by hand" MythFold exposes the raw knobs
  |                 (Session Zero is ABSORBED here, not duplicated)
  ↓
Table Rules       — Difficulty (enemy stat multiplier — engine-owned) ·
  |                 Permadeath (death archives the save — engine flag) ·
  |                 Companions on/off · Fog of War on/off (the living map) ·
  |                 House Rules (free text → GM persona, engine-checked
  |                 where possible)
  ↓
THE FORGING       — the reward stage; staged generation, each artifact
  |                 landing on the table as it completes:
  |                   1. the World      (worldsmith mode=world) → wax seal
  |                   2. the Key NPCs   (cast + portrait queue) → faces
  |                   3. the Settlement (locations; first `here` lit)
  |                   4. the Intro      (mode=story hook + opening art)
  |                   5. the Campaign Prompt (GM persona composed + shown
  |                      as a sealed scroll — inspectable, the DM's notes)
  ↓
The Dossier       — campaign summary: name, theme, map sketch, cast faces,
  |                 the hook, the table rules; anything re-forgeable from
  |                 here (re-roll cast, re-seal intro)
  ↓
Begin Campaign    — creates the dm- adventure and its save file; the
                    tale opens ON the intro scene
```

## 3. Screen flow

One full-screen scene (`scenes/forge/campaign_forge.tscn`). The war table
is persistent; stages swap in the table's upper half while forged artifacts
accumulate on the lower half (the table fills as you progress — progress IS
the set dressing).

## 4. Wireframe

```
┌──────────────────────────────────────────────────────────┐
│  ◆──◆──●──○──○──○──○   (rail)             🕯        🕯    │
│                                                            │
│              ✦  CHOOSE THE CAMPAIGN'S THEME  ✦             │
│   [Dark Fantasy] [High Fantasy] [Horror] [Political]       │
│   [Norse]        [Pirates]      [Steam]  [Sci-Fi]          │
│         ▸ Advanced: the five pillars (fold)                │
│ ──────────────── the table ────────────────                │
│  ~map (inks in)~   name-ribbon   [rule cards]  compass     │
│  ‹ back                                    set it down ›   │
└──────────────────────────────────────────────────────────┘

THE FORGING:
│   ⚒ The world takes shape…                                 │
│   ✅ Emberreach          (wax seal pressed — thunk)        │
│   ⏳ The cast arrives…    (🙂)(🙂)( )( )  faces landing      │
│   ○ The first settlement                                   │
│   ○ The opening scene                                      │
```

## 5. Visual mockups

As with the Character Forge: milestone C1 ships the shell + war table +
two stages and stops for a screenshot review gate (MF_SHOT_WARTABLE)
before the Forging sequence is built.

## 6. Data flow

- Draft held by the manager; nothing persists until Begin Campaign
  EXCEPT the Forging's generated world (cworlds save is the existing
  worldsmith contract — a forged-then-abandoned world simply remains in
  the gallery, same as today).
- Theme → pillar preset + palette id + art-prompt seasoning.
- GM's Voice → `gm` state kind (knob bundle) + persona directive line.
- Table Rules → new `world.rules` keys: difficulty (enemy_hp/atk
  multiplier read by Combat), permadeath (death → archive save), fog
  (map honors), companions (recruit tags refused when off), house_rules
  (envelope text). Each engine-enforced where the engine owns the lever.
- The Forging: existing endpoints — /worldsmith (world, story),
  /save (cworld + dm- adventure), Art.ensure (key art, chart, cast
  portraits — pays the forge-art-queue matrix row).
- Outputs: campaign · world seed · map seed (chart art + locations) ·
  settlement seed (first here + seen) · NPC seeds (cast + codex entries)
  · quest seed (hook → first quest) · AI campaign prompt · save slot ·
  world configuration (rules block).

## 7. Architecture

- `scenes/forge/campaign_forge.tscn` + `campaign_forge.gd` — **the
  CampaignForgeManager**: stage FSM + draft + the Forging orchestrator
  (sequential generation with per-step status, cancel-safe, resumable
  if a step fails — a failed step re-strikes without redoing the others).
- `Mode` gains declared `CampaignForge` state.
- main_menu's ⚒ World Forge + Campaign Smith + Session Zero are ABSORBED:
  their entry points route here (matrix rows updated, nothing deleted).

## 8. Component requirements

Shares `MythChoiceCard` + `MythStageRail` with the Character Forge (built
once, gallery first). New: `MythForgeStep` (the Forging's staged progress
row: ○ waiting / ⏳ striking / ✅ sealed, with the artifact chip beside it)
— also reusable for any future long generation (world import, art warmup).

## 9. Implementation milestones

| # | Scope | Gate |
|---|---|---|
| **C1** | Forge scene shell + war table + Name/Theme stages wrapping the existing worldsmith call; main-menu pillar button | screenshot review |
| **C2** | GM's Voice presets (absorbs Session Zero) + Table Rules with engine enforcement (difficulty multiplier, permadeath flag, fog toggle, companions toggle, house rules line) | self-check rows for each engine lever |
| **C3** | THE FORGING: staged sequence + MythForgeStep + cast portrait queue (pays forge-art-queue debt) | screenshot + live harness |
| **C4** | Settlement + intro scene + Dossier + save-slot creation + begin-on-intro handoff | live playthrough lane |
| **C5** | Table set-dressing polish (accumulating artifacts, wax thunk, candle flicker), re-forge affordances, campaign export | full ritual review |

## Menu placement (both pillars)

Title screen becomes: **Continue · Character Forge · Campaign Forge ·
Settings** (Load lives inside Continue as today). The two Forges are
peers of Continue — permanent pillars, per the directive.
