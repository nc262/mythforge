# Character Creation

## Hero forge (gate into every new adventure)
Dialog on first entry (no saved sheet): name · heritage (9 races with
ability bonuses, speed, traits, skills) · class (12, from `class_presets`:
hit die, saves, skills, caster flag) · **4d6-drop-lowest destiny**, best
scores auto-assigned by class priority (cast ability → DEX/STR by class →
CON), rerollable. Derived: HP = hit die + CON, 10+1d20 gold, class+heritage
skill proficiencies, heritage traits as features, level-1 slots + starting
spells for casters. Then Session Zero (tone), then the GM's opening scene.

## Original-parity gaps (FeatureMatrix rows, M3)
- **Prebuilt heroes**: Brakka Ironhide / Elara Venn / Finch / Sister Maren
  one-click fills + "start fresh"
- **Backgrounds** (8, each +2 skills + a story hook) — data already in
  `tables.json`
- **Portrait generation** in the forge (prompt seeded from race/class/world
  reskin, `/describe` appearance anchor)
- Backstory field (GM weaves it in), standard-array option, editable
  ability grid, world class reskins in the picker

## Leveling
XP curve: triangular ×100 (L2@100, L3@300…). Level-up today: auto — avg
hit-die HP, full heal, auto class features, caster slot growth. **The
level-up ceremony** (M2): roll-vs-average HP choice, feat/ASI at milestone
levels, subclass at 3, learnable-spell picks by class circle — data all
present in `tables.json` (feats, subclasses, subclass_grants, class_spells).

## Companion characters
NPCs recruit via `[[companion]]` (ask-GM action or story); they get
level-scaled HP/AC and fight in the tracker; wounds persist; rests heal.
Guest heroes / play-as (party multiplayer) — roadmapped M4.
