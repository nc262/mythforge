# Ritual: Reading Your Stars

*U5 — the destiny constellation. Emotions: destiny · growth · magic.*

## 1. Experience

Not a talent spreadsheet — the night sky of who you are becoming. Your
class's whole journey, levels 1 through 20, hangs as a constellation: a
winding river of stars climbing the dark, each feature a named star, each
milestone a monument. The stars you have earned burn gold and amethyst,
joined by glowing threads; the ones ahead wait as dim promises you can
read — destiny visible, not hidden. The next milestone breathes softly:
it knows you are coming.

Progression is still awarded by the level-up ceremony (the engine owns
growth); the constellation is where you SEE the road — and where a fresh
level bursts alight.

## 2. The ritual beats

| Beat | What happens |
|---|---|
| **Anticipation** | Opened from the sheet's ✨ destiny link (or Ctrl+K); the world dims |
| **Reveal** | A starfield with nebula breath; the constellation climbs from Level 1 at the base |
| **Focal point** | Your current star, ringed and breathing — *you are here* on the road of your class |
| **Interaction** | Wheel-zoom into the sky, drag to pan; hover any star for its story |
| **Reward** | After the level-up ceremony the constellation opens itself with the new star flaring alight |
| **Graceful exit** | Close — the scrim lifts |

## 3. UX flow

- **Spine**: 20 level-stars along a winding curve, bottom → top. Earned =
  gold-lit, joined by glowing thread; ahead = dim thread, hollow stars.
- **Feature stars** branch off their level on curved threads, named
  (from class_features), amethyst when earned.
- **Milestones** are monuments: your Tradition/Path at its level, the Gifts
  of Growth (ASI/feat levels 4/8/12/16/19), Apotheosis at 20 — diamonds
  with halos; the NEXT one ahead breathes gold.
- **Circles of magic** (casters): a star flares where each new spell circle
  unlocks, from the slot table.
- **Hover**: nearest star tells its story in the ledger line at the bottom
  (name · earned at level N / awaits at level N · detail).
- Camera + fog lessons inherited: MythCamera (shared pan/zoom helper),
  clip_contents on.

## 4. Wireframe

```
┌──── ✨ The Constellation of Wren ───────────────┐
│      · ˚ ✦20 Apotheosis ˚    ·      ˚           │
│   ˚      ✧19◇        · (dim thread ahead)       │
│        ✧… ✧…   ˚                                │
│   Circle 3 ✶——✧7    ·        ˚                  │
│      ◆4 Gift——●4                                │
│  Tradition ◇3——●3   ← breathing (next milestone)│
│     Arcane Recovery ✦——●2                       │
│            ●1 Level 1  (base of the climb)      │
│ ledger: "Arcane Recovery — earned at level 1 …" │
└─────────────────────────────────────────────────┘
```

## 5-8

MythCamera extracted to ui/ (world_map adopts it as a debt row — one camera,
two skies). Harness MF_SHOT_TREE. Docs: FeatureMatrix U5, TechnicalDebt
(world_map camera adoption), Roadmap M5 tick.
