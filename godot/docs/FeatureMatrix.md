# Feature Matrix

Every feature the game has or intends to have, with its status. Status: ✅ done ·
🟡 partial · 🔲 not started. Priority P1 (core play) → P4 (nice to have).
Complexity S/M/L/XL.

**Rule: no row may be deleted.** A feature that cannot ship now gets a
placeholder and a roadmap entry, so nothing quietly falls off the list.

## Shell & flows
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| Title screen (4 buttons + continue meta + key-art bg) | ✅ main_menu Title view | P1 | — | M | — |
| Continue → save-file picker (openSaves) | ✅ _show_saves | P1 | — | S | — |
| Continue vs New game (archive+wipe) | ✅ _ask_continue_or_new | P1 | — | M | — |
| Worlds gallery + step banner | ✅ | P1 | — | M | staggered card entrance anim 🔲 |
| World detail (lore/adventures/cast) | ✅ | P1 | — | M | art-style bar 🔲 (below) |
| World forge: pillars+chips+surprise+refine+preview | ✅ | P1 | Worldsmith | L | forge queue (pregen cast faces + creature art) 🔲 |
| Campaign smith (mode=story) | ✅ | P2 | — | M | preview shows hook ✅; cstories registry simplified to world graft |
| Companion 1-to-1 chat (no HUD) | ✅ | P2 | — | M | seed-photos 📷 ask-pic buttons 🔲; clear-chat 🔲 |
| Settings (native panel) | ✅ sfx/ambient+volume/motion/narrator picker/version | P2 | — | M | TTS toggle waits on a voice engine |
| Session Zero tone knobs | ✅ + 🎛 mid-game retune | P1 | — | S | |
| GM forge (dm-custom-* personas) | 🔲 | P3 | — | M | custom GM personalities |
| Character/persona forge (portrait+suggest+describe) | 🔲 | P3 | Art, Worldsmith | L | create-your-own companions |
| World import/export (.world.json) | ✅ export+opens folder / import with validation | P3 | — | S | |
| Unmake world | ✅ | P3 | — | S | |
| Campaigns tab (cross-world premises) | 🔲 | P4 | — | M | |

## Character & progression
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| Hero forge (name/heritage/class/4d6) | ✅ ABSORBED into the Character Forge pillar (same gate, full ritual) | P1 | tables.json | M | — |
| Prebuilt heroes (4 one-click) | ✅ | P2 | — | S | — |
| Backgrounds (8, +2 skills + hook) | ✅ picker + hook into session zero | P2 | — | S | |
| Portrait in hero forge | ✅ auto-commissioned at creation; crowns the sheet + grid token | P3 | Art | M | forge-time preview 🔲 |
| Standard array + editable grid | ✅ Character Forge Nature stage (hand-assigned, permutation-validated) | P3 | — | S | |
| Level-up ceremony (roll HP, feats/ASI, subclass, spells) | ✅ | P1 | — | L | ASI = +2 single (split 🔲) |
| Class feature actions (per-rest uses) | ✅ 6 ported | P1 | — | M | Bardic Insp., Lay on Hands, Wild Shape… 🔲 |
| Inspiration (grant nat20 / arm / spend adv) | ✅ full loop + chip | P2 | — | S | |
| Multiclassing | 🔲 | P4 | — | L | |
| Exhaustion enforcement UI | ✅ sheet + effects enforced via envelope | P3 | — | S | |

## Combat
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| Tracker (initiative/HP/turns/conditions) | ✅ | P1 | — | L | — |
| Player attack math (full port) | ✅ incl. small-race heavy disadvantage | P1 | — | L | |
| Two-weapon / off-hand bonus strike | ✅ light+light, once/round, no +mod dmg | P2 | — | M | |
| Enemy AI turns → real sheet | ✅ | P1 | — | M | — |
| Reactions overlay (Shield/Uncanny Dodge/Parry) | ✅ pend→choose→resolve | P1 | — | M | escape/OK = take the hit, never voids |
| Companions fight + persist wounds | ✅ | P1 | — | M | — |
| Death saves + epitaph | ✅ | P1 | — | M | game-over overlay w/ load-save & cling-to-life buttons 🟡 (revive path = long rest) |
| Victory: auto-finish, XP, killing-blow cinema | ✅ + HDYWTDT flourish + gold victory flash | P1 | — | M | |
| **Tactical battle grid** (16×10, tokens, move budgets, adjacency/ranged, enemy approach) | ✅ v1 | P1 | — | XL | token drag 🔲 (click-move shipped) |
| Engine terrain (walls/water/cover sampled from the map painting) | ✅ heuristic sampler + flood guard; walls block, water doubles cost, cover +2 AC vs ranged | P2 | — | M | LLM-authored terrain layout 🔲 |
| Combat casting (engine-resolved spell attacks, slots enforced) | ✅ v1 damage spells; Magic Missile auto-hit; typed defenses | P1 | — | M | save-DC spells 🔲 |
| End Turn auto-sweep (enemies + companions act unprompted) | ✅ reactions still pend; one combined GM note per sweep | P1 | — | M | |
| Battle underlay art (scene-matched map) | ✅ generated overhead map of the actual place, ornate frame, whisper grid | P3 | Art | M | terrain paint 🔲 |
| Combat music/backdrop swap | 🟡 tint+sting | P3 | audio | M | music system 🔲 |

## World, travel, economy
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| Clock/weather/waning conditions | ✅ + auto-advance/3 turns + chip + time-of-day tint | P1 | — | M | |
| Rests (hit dice, ambush, slots) | ✅ | P1 | — | M | rest FX 🔲 |
| Vendors: stock + buy/sell + haggle | ✅ window + location flavor + world currency | P2 | — | M | |
| Travel/atlas ("you are here", encounters) | ✅ v1 (list, travel, 1-in-5 road encounters, here-marker, scene repaint) | P2 | — | L | x/y world map render 🔲; auto here-tracking from prose 🔲 |
| Worldtick ("Meanwhile…" between days) | ✅ after every long rest | P3 | — | S | |
| Finale / THE END | ✅ detection+card | P2 | — | S | complete badge on saves 🔲; auto-snapshot 🔲 |
| Loot prompt (Add to pack / Ignore) | 🟡 auto-add via tag | P3 | — | S | opt-in prompt variant |

## Design system (MDL — docs/DesignSystem.md is the contract)
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| Tokens (SPACE/TIME/RADIUS/RARITY) + surfaces (forged/ornate/grain/socket/card/glow) | ✅ Ui autoload | P1 | — | M | |
| Motion vocabulary (polish/reveal/breathe/pulse/rise_text, reduce-motion aware) | ✅ | P1 | — | M | audio hooks await tick/thud samples |
| Component library (MythCard/Socket/Tooltip/Header/Gauge/Portrait/Camera/Fold) | ✅ ui/myth_*.gd | P1 | — | L | |
| Component gallery / visual regression page | ✅ tests/ui_gallery.tscn | P2 | — | S | |
| U1 The Pack ritual: leather surface, cards-not-cells, socket doll around portrait, ▲/▼ comparison tooltips, context menu, inspect, reward rise, scrim ritual | ✅ | P1 | MDL | L | leather material refinement pass 🔲 |
| U2 combat feel: initiative rail (portrait chips, turn halo+pulse), token slides, rising damage/heal numbers, impact blooms, attacker lunge, board shudder on hero hit | ✅ | P1 | MDL | L | action-bar icon buttons 🔲 (tracker links remain) |
| U3 living map: wheel-zoom + drag-pan camera, fog of war (world.seen persists), quest-pull gold pulse, animated dashed route preview, drifting cloud shadows, breathing here-ring, compass rose | ✅ | P2 | MDL | L | region-shaped fog (per-place blobs today) 🔲 |
| U4 journal & dialogue: manuscript journal (wax-seal quests, portrait people, fleuron chapters, tab filters + search) + GM speaker portraits (codex face near quoted speech seats their chip on the bubble) | ✅ | P2 | MDL | M | relationship chips 🔲 (no relationship stat yet); choice-button dialogue 🔲 |
| U5 destiny constellation: class road 1-20 as a night sky — winding earned-gold spine, amethyst feature stars, milestone monuments (subclass/ASI/Apotheosis, next one breathes), circles of magic, wheel-zoom + pan (shared MythCamera), level-up opens it with the new star flaring; sheet ✨ destiny link + Ctrl+K | ✅ | P2 | MDL | XL | node click-to-inspect dialog 🔲; world_map adopts MythCamera 🔲 |
| U6 the Hero's Record: identity-first full screen (portrait/name/epithet, HP+XP straps, gold-lit gear sockets → Pack handoff, carved Six, prowess, MythFold sections for skills/magic/deeds/companions) | ✅ | P2 | MDL | L | 3D turntable 🔲; heraldry crest 🔲; memory-drawn epithet 🔲 |

## The first impression (cinematic menu + handcrafted controls)
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| Opening cinematic: four genre panoramas (dragon → holo-dragon Neonspire → suburb sunset → deep space), Ken Burns + crossfades + letterbox, stars collapse into the breathing logo; skippable on any input; once per launch | ✅ scenes/ui/cinematic.gd + Art.CINE_PROMPTS | P1 | the image engine | L | ✅ FULL VIDEO shipped: SVD img2vid clips assembled to assets/video/opening.ogv (13.9s 720p Theora); stills remain the cold-cache fallback |
| MythButton: handcrafted material plates (carved oak / forged steel / aged leather / polished brass), engraved typography (dark glyphs, light kiss), hover light sheen, press seat, drawn icon | ✅ | P1 | MDL | M | steel-plate engraving contrast pass 🔲 |
| Mythforge Icon Library: 10 hand-drawn code icons (banner/anvil/wartable/compass/book/runewheel/door/cups/quill/hammer) — no fonts, emoji, or icon packs | ✅ ui/myth_icon.gd, in gallery | P1 | MDL | M | grow per new surface; full in-game emoji-free sweep 🔲 |
| New primary menu: Continue · Begin a New Adventure · Forge a Hero · Forge a Campaign · Chronicles · Settings · Exit (+ A Quiet Table) | ✅ material plates, interface reveals after the cinematic | P1 | — | M | menu EAS environment painting 🔲 |
| Begin a New Adventure orchestrator: hero (banked/forge/later) → campaign (existing/forge) → party → difficulty → house rules → preview → begin | ✅ scenes/forge/adventure_forge.gd — invokes both Forges, seats rules into the adventure | P1 | Forges | L | party multiplayer chairs dim 🔲 |

## Environmental Art System (EAS — the world is the interface)
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| MythEnvironment: painting + scrim + volumetric shafts + candle anchors + dust/embers + mouse parallax; atmosphere-only mode | ✅ | P1 | MDL, the image engine | L | |
| Seven illustrated rooms generated + cached (war room, forge, pack, merchant, journal, map table, fireside) | ✅ Art.ENV_PROMPTS, warmed | P1 | the image engine | M | per-world environment variants 🔲 |
| Mounted: both Forges (procedural = fallback), pack, merchant, journal, map table, Hero's Record, game-table atmosphere overlay | ✅ | P1 | — | M | title screen environment 🔲; dialogue fireside w/ NPC portrait staging 🔲 |
| Generated prop/frame assets (banners, statues, carved frames, icons) | 🔲 next EAS wave | P2 | the image engine | L | |

## Forge pillars (docs/forges/ — designs approved before any build)
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| **Character Forge** (pillar) | ✅ F1-F5 shipped: 11-stage anvil ritual (origin w/ one-click legends, ruleset, heritage/class/background card grids w/ lore, nature = 4d6 destiny OR hand-assigned standard array, appearance-in-words + style chips, voice placeholder rune, kit cards, Quenching w/ cooling portrait + re-strike + name strike); menu pillar banks drafts to user://forged_hero.json, resumed at the Quenching in any new adventure; commit runs the same engine math + equips the kit + commissions the portrait with the player's words | P1 | MDL, the image engine | XL | 3D model → FutureIdeas; relationships seed 🔲; portrait stage folded into Quenching (honest the image engine one-shot) |
| **Campaign Forge** (pillar): war-table ritual — name/ruleset/theme/GM's voice/table rules/THE FORGING/dossier | ✅ C1-C5 shipped: full war-table ritual — Welcome/Name/Ruleset/Theme/Voice/Rules → THE FORGING (staged: world seal, cast faces via portrait queue, settlement, opening scene, DM's notes — MythForgeStep) → Dossier (re-strike opening, inspect persona) → BEGIN THE CAMPAIGN (dm- save + gm/rules/here seeded, opens in-game) | P1 | MDL, worldsmith | XL | campaign export 🔲; forge art queue pays partially (cast faces) — creature pregen 🔲 |
| Shared forge components: MythChoiceCard · MythStageRail · MythForgeStep | ✅ | P1 | MDL | M | |
| Table rules engine levers | ✅ ALL engine-enforced: difficulty scales foe HP+damage (clamped 0.5-2.0) · permadeath archives the save on final death · fog toggle honored by the living map · companions gate refuses recruit tags · house rules ride every envelope; forge defaults seed each adventure and survive resets | P1 | — | M | self-check rows green |
| Character voice stage | ⛔ ships as a visible placeholder rune-stone | P3 | a local voice engine | S | F5 |
| 3D character generation | 🔲 future | P4 | — | XL | FutureIdeas |

## AI & memory
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| Tag protocol replacing prose mining | ✅ | P1 | — | L | — |
| Campaign memory beats+recall | ✅ | P1 | embeddings | M | — |
| Codex / quests extractors + panels | ✅ | P1 | — | M | — |
| Recap card (+art) | ✅ text | P2 | — | S | recap art 🔲 |
| Snapshots/Chronicle UI | ✅ save/list/resume-from-chapter | P2 | — | M | campaign export/import 🔲 |
| NPC portraits in codex | ✅ on-demand + auto-conjure on meet | P2 | — | M | |
| Scene backdrops ([[scene]] + 🖼) | ✅ + Ken Burns breath (reduce-motion aware) | P2 | — | M | |
| Ask-GM: learn spell / recruit | ✅ | P2 | — | S | — |
| Edit / regenerate messages | 🟡 ↻ retell button live | P2 | — | M | inline edit 🔲 |
| Narrator picker | ✅ lists the .gguf files in user://models; the pick is honoured | P2 | — | S | |
| TTS narration | ⛔ NOT BUILT | P3 | a local voice engine | M | client wiring exists; nothing in the stack speaks yet |
| STT input | ✅ push-to-talk via NobodyWhoSTT (whisper GGUF) | P4 | a whisper model | M | |

## Presentation & platform
| Feature | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|
| Per-world theming + living backdrop | ✅ | P1 | — | M | — |
| Bubbles/dice moment/battle tint/SFX | ✅ | P1 | — | M | fx suite (_fxVictory/Rest/Shake/ItemGet/LevelUp…) 🟡 partial |
| Ambient soundscapes + synth music | ✅ five looping pads, crossfade, combat drone, volume setting | P3 | — | L | scene-reactive layers 🔲 |
| Party chips w/ HP bars | ✅ in the banner chips | P2 | — | S | |
| Clock/objective/inspiration chips | ✅ clock/weather/here/quest (inspiration rides its feature) | P2 | — | S | |
| Dice tray (manual d4–d20 + mod) | 🟡 🎲 menu covers checks | P3 | — | S | raw die tray 🔲 |
| Controller support | 🔲 | **P2** | FSM/focus | L | target-game requirement |
| Keyboard shortcuts map | ✅ Ctrl+S/L/R, Space, Esc (docs/UI.md) | P3 | — | S | |
| Drag-drop inventory + paper doll | ✅ 🎒 window: 4-slot doll, 24-cell grid, rarity glow, drag/double-click, tooltips (Ctrl+I) | P3 | — | XL | |
| World map + minimap | ✅ painted map (key art, kind-colored marks, hover lore, click-travel, Ctrl+M) | P3 | — | L | minimap overlay 🔲 |
| Crafting | ✅ v1 ask-GM flow (materials judged, loot/gold tags settle it) | P3 | — | M | recipe system → M4 living world |
| Party multiplayer + voice | 🔲 | P4 | a networking design that does not exist | XL | |
| Windows .exe export (Steam-ready) | ✅ dist/Mythforge.exe (105MB, embedded pck, x86_64) | P2 | — | S | codesign + Steam SDK when publishing |
| FSM game modes | ✅ Mode autoload, 20 states | P1 | — | M | input-map per state rides M3 controller work |
