# Ritual: Steel Comes Out

*U2 — combat feel. Emotions: danger · power · momentum · victory.*

## 1. Experience — what the player should feel

Combat is not a list updating. It is weight, heat, and consequence. When
initiative rolls, the room should tighten: the score darkens (already), the
board presents itself, and the combatants stand across from each other as
*faces*, not names. Every blow should land somewhere — on a body, with
motion, light, and a number that leaps off the wound. Your turn arriving
should feel like the room turning to look at you.

## 2. The ritual beats

| Beat | What happens |
|---|---|
| **Anticipation** | Sting + ember tint + combat score (shipped); the board reveals with the painted field |
| **Reveal** | The initiative rail: portrait chips of everyone in the fight, in order, faces from the same art as their tokens |
| **Focal point** | Whoever acts now: their chip swells with a gold halo and pulses as the turn passes |
| **Interaction** | Click-move (token *slides*, doesn't teleport), click-attack, ✦ cast, End turn sweep |
| **Reward** | Damage numbers rise off the struck token; an impact flash blooms; the attacker lunges into the blow; the board itself shudders when YOU are hit; HDYWTDT + gold victory flash (shipped) |
| **Graceful exit** | Ember tint lifts, world score returns, board folds away (shipped) |

## 3. UX flow

- **Initiative rail** (new): chips above the tracker — ally gold ring, enemy
  danger ring, current turn enlarged + halo + pulse; fallen dimmed; hover
  tooltip = name + HP. The rail IS the "whose turn" answer at a glance
  (hierarchy: rail → board → tracker details).
- **Token motion** (new): tokens ease to their squares (~0.2s), never snap.
- **Blow feedback** (new): HP drop → "-N" rises in danger red at the token +
  radial impact bloom; heal → "+N" in gold; the current actor lunges toward
  the victim and back; the whole board shudders briefly when the hero is hit.
- All motion honors reduce_motion (numbers still rise? no — reduce_motion
  skips motion entirely; the tracker text remains the record).

## 4. Wireframe

```
┌─ chat ────────────────────────────────┐
│  … the tale …                          │
│ [🙂][👹][👹][🙂]   ← initiative rail    │
│ ┌── painted battle board ───────────┐ │
│ │   (tokens slide, numbers rise)    │ │
│ └───────────────────────────────────┘ │
│ ⚔ COMBAT — Round 2  End turn › End …  │
│ ✦ Fire Bolt  ✦ Magic Missile  Slots…  │
└───────────────────────────────────────┘
Focus: rail (1) → board (2) → tracker actions (3)
```

## 5-8. Mockup, implementation, polish, docs

Mockup = the combat demo screenshot harness. MythPortrait grows an optional
vitals arc + turn state (system-first — the same chip serves dialogue and
party rails later). Token art mapping moves to `Art.combatant_tex` so rail
and board share one source. Docs: FeatureMatrix U2, DesignSystem (component
growth), KnownIssues for anything deferred.
