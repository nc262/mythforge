# Roadmap

Milestones are shippable; each ends with the harnesses green, the Backlog
reconciled, and a playable build. Order chosen by play-impact.

## M1 — Foundations for scale ✅ COMPLETE
- ✅ **Finite state machine** (`Mode` autoload): MainMenu, CharacterCreation,
  Exploration, Conversation, Combat, Inventory, Merchant, Crafting, Camp,
  Travel, Cutscene, GameOver. Each mode declares allowed actions, blocked
  input, visible UI. All existing booleans (`_streaming`, `Combat.active`)
  fold into it. *Prerequisite for controller support and every new mode.*
- ✅ ↻ retell button surfaced in the input row
- ✅ Prebuilt heroes + backgrounds in the hero forge
- ✅ Reactions overlay (Shield / Uncanny Dodge / Parry / take the hit)
- Docs system (this set) + Features.md as the coarse map ✅

## M2 — Combat & progression complete ✅ COMPLETE
- ✅ **Tactical battle grid**: 16×10 board, tokens, movement budgets,
  melee adjacency/ranged rules, enemy approach, `bmap` persistence (terrain → M3)
- ✅ **Level-up ceremony**: HP roll-vs-average, feats/ASI at milestones,
  subclass at 3 with grants, spell picks by circle
- ✅ Chronicle/snapshots UI (save chapter, list, resume-from-chapter)
- ✅ Travel atlas v1: places list, travel action, road encounters, here-marker
- ✅ GM panel: 🎛 mid-campaign retune; GM model picker in Settings

## M3 — The AAA presentation pass 🟡 WAVE 1 SHIPPED
- ✅ Keyboard shortcut map (Ctrl+S/L/R, Space, Esc)
- ✅ Banner chips: clock/weather · here · active quest · party HP
- ✅ Ambient score: five looping synth pads crossfading with world & combat,
  volume + toggle in Settings
- ⛔ TTS narration — NOT BUILT: client wiring exists; there is no local voice
  engine in the stack. It needs one chosen and shipped the way the narrator and
  whisper were
- Remaining (each a full session of work, placeholders per the rules):
  controller navigation pass · drag-and-drop inventory + paper doll ·
  merchant window · quest journal window with search · world map + minimap
  render (atlas data live) · portrait/persona forge · scaling QA ·
  ✅ Steam-shape .exe export shipped (dist/Mythforge.exe)

## M4 — The living world 🟡 FIRST SYSTEMS SHIPPED
- ✅ Worldtick: "Meanwhile…" asides after every long rest, folded into memory
- ✅ Crafting v1: 🔨 ask-the-GM flow — materials judged from the real pack,
  results granted via loot/gold tags
- ✅ World export/import (.world.json) + unmake
- Remaining: relationships/reputation web · inspiration economy ·
  recipe-based crafting · campaigns tab · STT · settlement simulation ·
  party multiplayer (+voice) — interfaces sketched in FutureIdeas.md.

## M5 — The Ritual Interface (MDL) ✅ COMPLETE
Design-system-first UI rebuild (docs/DesignSystem.md is law; every screen a
ritual with its doc in docs/rituals/):
- ✅ U0 the Mythforge Design Language + component library + gallery
- ✅ U1 the Pack (inventory ritual)
- ✅ U2 combat feel (initiative rail, living board) + the clip_contents RCA
- ✅ U3 the living map (camera, fog of war, quest pull)
- ✅ U4 the manuscript journal + dialogue speaker portraits
- ✅ U5 the destiny constellation (new system: class road as a night sky)
- ✅ U6 the Hero's Record (identity-first character screen; 3D turntable → FutureIdeas)

## M6 — The Character Forge (pillar) ✅ COMPLETE (F1-F5)
docs/forges/CharacterForge.md. F1 shell+rail+3 stages+Quenching (screenshot
gate) → F2 origins/ruleset/kits → F3 evolving portrait → F4 nature/array →
F5 voice placeholder + cinematic quench + memory/relationship seeds.

## M7 — The Campaign Forge (pillar) ✅ COMPLETE (C1-C5)
docs/forges/CampaignForge.md. C1 shell+war table+name/theme (screenshot
gate) → C2 GM's voice + engine-enforced table rules → C3 THE FORGING
(staged generation + cast portrait queue) → C4 settlement/intro/dossier/
save slot → C5 set-dressing polish + export. Absorbs world forge, campaign
smith, Session Zero; menu becomes Continue · Character Forge · Campaign
Forge · Settings.

## M8 — The Environmental Art System 🟡 FIRST WAVE SHIPPED
The world is the interface: MythEnvironment + seven generated rooms mounted
across forges, pack, merchant, journal, map, record, and the game table's
air. Next waves: title-screen environment · dialogue fireside staging ·
generated props/frames/banners · per-world room variants.

## M9 — The First Impression ✅ SHIPPED
Cinematic opening (four worlds in one breath, the name forged from stars),
handcrafted MythButton plates + the drawn Icon Library, the seven-option
menu, and Begin a New Adventure orchestrating both Forges.

## M10 — The game is the whole application ✅ COMPLETE
The narrator, campaign memory, the codex, the quest log, the world tick, the
Worldsmith, the World Compiler and speech-to-text all moved into the game's own
process; the image engine became one native binary the game POSTs to directly.
See [Architecture.md](Architecture.md) and [Performance.md](Performance.md) —
a GM turn went 19.3 s → 3.7 s, and there is nothing to start first.

## Standing rules
No milestone ships with a red harness. No feature leaves the matrix. Re-export
after any `godot/**` change, and copy the exe to the Desktop — a stale Desktop
build gets playtested by mistake.
