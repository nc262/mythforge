# Ritual: The Hero's Record

*U6 — the character screen. Emotions: identity · progress · pride.*

## 1. Experience

Not a stat sheet — a legendary hero's record, the page a chronicler would
keep about YOU. Identity comes before statistics: the painted face first,
the name in gold leaf, the epithet line that says who you are in this
world. Then the body of the record: the six carved stones of your nature,
your prowess, and — folded away until wanted — the long lists (deeds,
magic, companions). Opening it should feel like pride; reading it should
feel like being known.

This is a READING surface. Actions (equip, cast, sell) stay in the Pack
and the side sheet — the record is where you admire what they built.

## 2. The ritual beats

| Beat | What happens |
|---|---|
| **Anticipation** | 🛡 record link / Ctrl+H; the world dims |
| **Reveal** | The record settles in; portrait glowing, name in gold |
| **Focal point** | The face and the name — identity before numbers |
| **Interaction** | Read; fold open the secondary sections (▸ Deeds, ▸ Companions); hover sockets for the gear's story; the Gear tab IS the pack (cards, equip, sell) |
| **Reward** | The XP strap shows the road to the next level; the vitals say how the tale is treating you |
| **Graceful exit** | Return to the tale |

## 3. UX flow / layout

```
┌────────── 🛡 The Record of Wren Ashvale ──────────┐
│  (PORTRAIT, halo)   │  ✦ THE SIX ✦                │
│   WREN ASHVALE      │  [STR][DEX][CON]  carved    │
│   Half-Elf Wizard   │  [INT][WIS][CHA]  plaques   │
│   of Embervale · L4 │  ✦ PROWESS ✦                │
│  ═ HP 21/26 ═       │  AC 14 · Atk +5 · DC 13 ·   │
│  ═ XP → L5 ═        │  Perception 11 · Dice 3/4   │
│  87 gold            │  ▾ Skills — proficiencies    │
│  ✦ EQUIPPED ✦       │  ▾ Magic — spells + slots    │
│  [⚔][🥋][🗡][⛨]      │  ▸ Deeds — feats, features   │
│  Open the pack ›    │  ▸ Companions                │
└───────────────────────────────────────────────────┘
Focus: portrait/name (1) → vitals (2) → the six (3) → folds (4)
```

- Secondary sections are MythFold components (new MDL primitive: gilded
  ▸/▾ header, content reveals on open) — hide complexity until wanted.
- Sockets are read-only here (tooltips carry the gear's story); the
  GhostButton hands off to the Pack ritual for changes.
- One breathe: the portrait halo. Conditions surface as danger text under
  the vitals only when they exist.

## 4. Deferred (matrix)

3D rotatable character (far goal) · heraldry crest generator · epithet
from campaign memory (today: race/class/world/level line).
