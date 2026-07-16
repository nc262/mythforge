# Feature Matrix — original web game → Godot client

Status: ✅ done · 🟡 partial · 🔲 not started. Priority P1 (core play) → P4
(nice-to-have). Complexity S/M/L/XL. **Rule: no row may be deleted; a
feature that can't ship now gets a placeholder + roadmap entry.**
Original = static/js/characterStudio.js (+studioWorlds.js) unless noted.

## Shell & flows
| Feature | Original | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|---|
| Title screen (4 buttons + continue meta + key-art bg) | mythforge.html #mf-title | ✅ main_menu Title view | P1 | — | M | — |
| Continue → save-file picker (openSaves) | :104 | ✅ _show_saves | P1 | — | S | — |
| Continue vs New game (archive+wipe) | _adventureLoad :785 | ✅ _ask_continue_or_new | P1 | — | M | — |
| Worlds gallery + step banner | renderWorlds :230 | ✅ | P1 | — | M | staggered card entrance anim 🔲 |
| World detail (lore/adventures/cast) | renderWorldDetail :306 | ✅ | P1 | — | M | art-style bar 🔲 (below) |
| World forge: pillars+chips+surprise+refine+preview | openWorldsmith :496 | ✅ | P1 | worldsmith API | L | forge queue (pregen cast faces + creature art) 🔲 |
| Campaign smith (mode=story) | openCampaignsmith :651 | ✅ | P2 | — | M | preview shows hook ✅; cstories registry simplified to world graft |
| Companion 1-to-1 chat (no HUD) | openChat non-DM | ✅ | P2 | — | M | seed-photos 📷 ask-pic buttons 🔲; clear-chat 🔲 |
| Settings (native panel) | openSettings :8321 | ✅ sfx/ambient+volume/motion/model picker/signout/version | P2 | — | M | TTS toggle ⛔ w/ backend; shutdown button 🔲 |
| Session Zero tone knobs | _sessionZero :3680 | ✅ + 🎛 mid-game retune | P1 | — | S | |
| GM forge (dm-custom-* personas) | renderForge gm | 🔲 | P3 | — | M | custom GM personalities |
| Character/persona forge (portrait+suggest+describe) | renderForge :1216 | 🔲 | P3 | /generate /describe /suggest | L | create-your-own companions |
| World import/export (.world.json) | :278/:396 | ✅ export+opens folder / import with validation | P3 | — | S | |
| Unmake world | world-admin | ✅ | P3 | — | S | |
| Campaigns tab (cross-world premises) | :1079 | 🔲 | P4 | — | M | |

## Character & progression
| Feature | Original | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|---|
| Hero forge (name/heritage/class/4d6) | openPlayerEditor gate | ✅ | P1 | tables.json | M | — |
| Prebuilt heroes (4 one-click) | :3826 | ✅ | P2 | — | S | — |
| Backgrounds (8, +2 skills + hook) | :3796 | ✅ picker + hook into session zero | P2 | — | S | |
| Portrait in hero forge | :3826 | 🔲 | P3 | /generate | M | |
| Standard array + editable grid | :3807 | 🔲 | P3 | — | S | |
| Level-up ceremony (roll HP, feats/ASI, subclass, spells) | renderLevelUp :5825 | ✅ | P1 | — | L | ASI = +2 single (split 🔲) |
| Class feature actions (per-rest uses) | FEATURE_ACTIONS :2940 | ✅ 6 ported | P1 | — | M | Bardic Insp., Lay on Hands, Wild Shape… 🔲 |
| Inspiration (grant nat20 / arm / spend adv) | :3342 | ✅ full loop + chip | P2 | — | S | |
| Multiclassing | _canMulticlass :2877 | 🔲 | P4 | — | L | |
| Exhaustion enforcement UI | _EXHAUSTION | 🟡 shown on sheet | P3 | — | S | effects text into envelope 🔲 |

## Combat
| Feature | Original | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|---|
| Tracker (initiative/HP/turns/conditions) | renderCombatPanel :5289 | ✅ | P1 | — | L | — |
| Player attack math (full port) | _playerAttack :4911 | ✅ | P1 | — | L | small-race heavy disadvantage 🔲 |
| Two-weapon / off-hand bonus strike | _offhandAttack :4870 | 🔲 | P2 | offhand slot | M | |
| Enemy AI turns → real sheet | _enemyTurn :5051 | ✅ | P1 | — | M | — |
| Reactions overlay (Shield/Uncanny Dodge/Parry) | :5128 | ✅ pend→choose→resolve | P1 | — | M | escape/OK = take the hit, never voids |
| Companions fight + persist wounds | _companionTurn | ✅ | P1 | — | M | — |
| Death saves + epitaph | _rollDeathSave :5178 | ✅ | P1 | — | M | game-over overlay w/ load-save & cling-to-life buttons 🟡 (revive path = long rest) |
| Victory: auto-finish, XP, killing-blow cinema | _finishCombat | ✅ | P1 | — | M | HDYWTDT player flourish input 🔲; victory frame FX 🔲 |
| **Tactical battle grid** (16×10, tokens, move budgets, adjacency/ranged, enemy approach) | renderBattle :6508 | ✅ v1 | P1 | — | XL | terrain paint + token drag 🔲 (click-move shipped) |
| Battle underlay art (scene-matched map) | _ensureBattleUnderlay | 🔲 | P3 | /generate | M | |
| Combat music/backdrop swap | _enterCombatMode | 🟡 tint+sting | P3 | audio | M | music system 🔲 |

## World, travel, economy
| Feature | Original | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|---|
| Clock/weather/waning conditions | :8017 | ✅ | P1 | — | M | auto-advance every 3 turns 🔲; clock chip UI 🔲; time-of-day tint 🔲 |
| Rests (hit dice, ambush, slots) | :6747/:7488 | ✅ | P1 | — | M | rest FX 🔲 |
| Vendors: stock + buy/sell + haggle | openVendor :6447 | ✅ | P2 | — | M | location-aware vendors 🔲; currency naming 🔲 |
| Travel/atlas ("you are here", encounters) | _travelTo :6380 | ✅ v1 (list, travel, 1-in-5 road encounters, here-marker, scene repaint) | P2 | — | L | x/y world map render 🔲; auto here-tracking from prose 🔲 |
| Worldtick ("Meanwhile…" between days) | :8060 | ✅ after every long rest | P3 | — | S | |
| Finale / THE END | _checkFinale :6105 | ✅ detection+card | P2 | — | S | complete badge on saves 🔲; auto-snapshot 🔲 |
| Loot prompt (Add to pack / Ignore) | :7935 | 🟡 auto-add via tag | P3 | — | S | opt-in prompt variant |

## AI & memory
| Feature | Original | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|---|
| Tag protocol replacing prose mining | (new, better) | ✅ | P1 | — | L | — |
| Campaign memory beats+recall | §4.C | ✅ | P1 | embeddings | M | — |
| Codex / quests extractors + panels | :848/:929 | ✅ | P1 | — | M | — |
| Recap card (+art) | _showRecap :5260 | ✅ text | P2 | — | S | recap art 🔲 |
| Snapshots/Chronicle UI | :2671 | ✅ save/list/resume-from-chapter | P2 | — | M | campaign export/import 🔲 |
| NPC portraits in codex | (portraits) | ✅ on-demand | P2 | — | M | auto-conjure on meet 🔲 |
| Scene backdrops ([[scene]] + 🖼) | _combatBackdrop etc | ✅ | P2 | — | M | Ken Burns anim 🔲 |
| Ask-GM: learn spell / recruit | :8002/:8010 | ✅ | P2 | — | S | — |
| Edit / regenerate messages | :1958 | 🟡 ↻ retell button live | P2 | edit-message API | M | inline edit 🔲 |
| GM model picker | settings | ✅ (applies to new sessions) | P2 | — | S | |
| TTS narration (server) | :6114 (browser) | ⛔ BLOCKED | P3 | backend voice provider (probe: 503 provider=disabled) | M | client wiring waits for a server-side provider |
| STT input | voiceRecorder.js | 🔲 | P4 | /api/stt | M | |

## Presentation & platform
| Feature | Original | Godot status | Pri | Deps | Cx | Missing / notes |
|---|---|---|---|---|---|---|
| Per-world theming + living backdrop | applyWorldTheme | ✅ | P1 | — | M | — |
| Bubbles/dice moment/battle tint/SFX | (various fx) | ✅ | P1 | — | M | fx suite (_fxVictory/Rest/Shake/ItemGet/LevelUp…) 🟡 partial |
| Ambient soundscapes + synth music | studioAmbient.js :7252 | ✅ five looping pads, crossfade, combat drone, volume setting | P3 | — | L | scene-reactive layers 🔲 |
| Party chips w/ HP bars | :4801 | ✅ in the banner chips | P2 | — | S | |
| Clock/objective/inspiration chips | banner chips | ✅ clock/weather/here/quest (inspiration rides its feature) | P2 | — | S | |
| Dice tray (manual d4–d20 + mod) | :1671 | 🟡 🎲 menu covers checks | P3 | — | S | raw die tray 🔲 |
| Controller support | (n/a web) | 🔲 | **P2** | FSM/focus | L | target-game requirement |
| Keyboard shortcuts map | web various | ✅ Ctrl+S/L/R, Space, Esc (docs/UI.md) | P3 | — | S | |
| Drag-drop inventory + paper doll | (target, beyond web) | 🔲 | P3 | UI pass | XL | |
| World map + minimap | (target) | ✅ painted map (key art, kind-colored marks, hover lore, click-travel, Ctrl+M) | P3 | — | L | minimap overlay 🔲 |
| Crafting | _craftItem :7756 | ✅ v1 ask-GM flow (materials judged, loot/gold tags settle it) | P3 | — | M | recipe system → M4 living world |
| Party multiplayer + voice | /party/* | 🔲 | P4 | polling API | XL | |
| Windows .exe export (Steam-ready) | — | ✅ dist/Mythforge.exe (105MB, embedded pck, x86_64) | P2 | — | S | codesign + Steam SDK when publishing |
| FSM game modes | (new) | ✅ Mode autoload, 20 states | P1 | — | M | input-map per state rides M3 controller work |
