# NPC Systems

## The cast codex (persistent NPC memory)
Every 6 player turns the transcript passes through the codex extractor →
`codex` kind: `[{name, role, disposition, note, appearance}]`, folded into
every GM envelope ("keep them consistent"). 📜 panel shows the cast with
disposition badges (ally gold / hostile red) and 🖼 portrait links
(generated from the appearance anchor, cached per NPC).

## Companions
Recruited by story or the 🤝 ask-GM action; granted only when the GM
narrates agreement **and** tags `[[companion name=…]]`. Stored on the sheet
(`companions[]`: name, role, cls, level, ac, hp/hpMax); they act in combat
(companion turns), take wounds that persist, and heal on rests.

## World cast (authored personas)
Built-in and forged worlds ship 3 cast members each with full personas —
chatting with one saves a `wc-<world>-<slug>` template (persona + world
lore folded) and opens **companion chat**: no HUD, no dice, no envelope.

## Disposition & relationships
Disposition lives per-NPC in the codex (extractor-maintained from actual
play). Global relationship tracking (`rel` kind) and reputation systems are
target-game features — roadmapped M4, design in FutureIdeas.md.

## Parity gaps (FeatureMatrix)
Party chips with HP bars in the banner · 25% companion banter injections ·
dismiss/part-ways flow · NPC speaker portraits decorating GM dialogue ·
guest heroes (multiplayer party seats).
