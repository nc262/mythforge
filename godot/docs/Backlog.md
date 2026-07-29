# Backlog — the full deep dive (2026-07-18, updated 2026-07-28)

## 0. Resolved 2026-07-27/28 — The Great Bake, then UX Rounds 6 & 7

**The bake shipped.** Six worlds poured, verified and zipped: the original four
plus **fimbulreach** (Norse) and **brasshaven** (steampunk), added because no
built-in world covered those families. ~1 800 images, 7 390 catalogue entries,
~11 h of GPU. Every world verified at **0 truncated PNGs, 0 catalogue entries
with a missing icon**. Details and measurements in [AssetBake.md](AssetBake.md).

| Item | Now |
|---|---|
| B1–B7 (the whole bake plan) | ✅ done; B4 proven by killing it mid-pour and restarting |
| B2 — the seed's ask | ✅ 10 materials + 10 treatments, 4/4 worlds, verified LIVE against the 8B |
| B6 — vendor stock icons | ✅ baked into `art/icons/`; the exact jobs that starved the narrator |
| Two new worlds (Norse, steampunk) | ✅ full records, casts, campaigns, locations, backdrops, GM portraits |
| Ship weight | ✅ **decided**: zips are release assets, `godot/baked/*.zip` gitignored |
| `v1.0.0` release | ✅ published (private repo), 7 assets, byte-verified |
| One-click installer | ✅ built in [`installer/`](../../installer/) — **not yet validated on a clean machine** |

**UX Rounds 6 & 7** ([R6](UXAudit-Round6.md) · [R7](UXAudit-Round7.md)):
281 findings from a windowed click-walkthrough, then two fix passes.
**107 fixed, 51 of 51 Criticals closed, 12 findings retracted as wrong.**

Four instances of ONE root-cause bug drove most of it: the play screen, the
minimap, the Atlas, the menu and the Lore Book all asked the **art cache** for
art the bake had written into the **world package**. That single wrong lookup was
hiding an 11-hour bake from the player and making the game re-render, at ~25 s a
piece on their GPU, images it already had.

Also closed: the panel contract (stock dialog chrome, OS title bars, the exit
clipped off-screen since Round 5), three "take your seat" ceremony screens
(cold start to play **~18 → ~13 screens**), the ComfyUI VRAM lever (**7.4 GB →
0.5 GB**, measured), and reply length as a player-facing GM knob.

> **Method note that matters more than the count:** 12 of 281 findings described
> the app *wrongly* — features that existed but were unpopulated in the canned
> harness state (quests, companions, tooltips, keyboard shortcuts, dice, save
> feedback). `[shot]` means "I saw this frame", not "I understood why". Treat
> any remaining screenshot-derived finding as a hypothesis until the code path
> is read.

**Still open from R6/R7:** ~160 findings, almost all Medium/Low mechanical
polish (copy, spacing, hover states, per-screen empty states), plus a known
share that are of the wrong-finding class above.

### Open from the R8 real-exe playtest (2026-07-28)

Driving the shipped exe by hand found continuity bugs that three rounds of
auditing and both harnesses missed — see [Playtest-R8.md](Playtest-R8.md).

| # | Item | P | Effort |
|---|------|---|--------|
| ~~R8-01~~ | ~~**No CONTINUE ADVENTURE on the title** after a played session — the save exists but the Hall offers no way back; the player must re-walk the Adventure Forge~~ — **fixed** — see R12-01. Two bugs: the `adventures` state kind was refused by the server, and with auth disabled `get_current_user()` returned None so every save was filed under "null" while the player's own sat under their username. CONTINUE — FREE ROAM verified on the title screen | ✅ | — |
| R8-02 | **A banked hero's portrait does not follow them into a new adventure** — the seat keys off `hero-<cid>` and re-commissions a face the game already owns | P1 | S |
| R8-03 | Opening turn still **60+ s** with the GPU freed and the reply cap live | P1 | M |
| R8-04 | Quenching summary line is low-contrast grey over bright forge art | P3 | S |
| R8-05 | `MythPortrait` has no empty state (empty ring while unpainted); `MythPlate` got one this session | P3 | S |

**Session 2 (same save, played to Dawn Day 4 — past the three-day ask).** The
rules engine came out clean: every modifier, DC, save, skill bonus, crit-miss
and rest computation checked correct against the sheet (Playtest-R8 §2). What
failed is everything *around* the rules — which actions the game offers, and
which controls actually work.

| # | Item | P | Effort |
|---|------|---|--------|
| ~~R8-06~~ | ~~**Four of nine character-sheet tabs cannot be clicked.** Chronicle and The Table are dead at every window size; maximized, Destiny and Atlas die too. Hover proves no mouse event arrives. **Root cause unknown — my first answer was wrong and an in-engine probe disproved it.** Ruled out: geometric overflow (0.0 px, every tab inside the window at both sizes) and any covering control (identical, clean ancestor chain at Gear / Destiny / Chronicle). It does not reproduce in a probe scene. The dead zone starts *exactly* at a tab's left edge, and the rail's live span *shrinks as the window grows* — which no overflow can produce. Next step is an in-game probe logging `gui_get_hovered_control()` along the rail, not more static reading. Workaround: the More menu opens the sheet directly on a page~~ — **closed — not reproducible.** The Director never hit it, and the reachability probe added to `click_driver` (which asks what a mouse asks: which control is topmost at this point) reports all nine tabs owning their own centre. Reopen with a window size if it returns | ✅ | — |
| R8-32 | **Two front-ends — researched, and the framing was wrong.** The web UI is not leftover cleanup after a port: the game is **9% of this repository** (21.5k lines of Godot against ~158.6k of web UI and ~59.9k of backend Python). Mythforge is a game bolted onto a web *workspace*, which is why the older client is ahead on features. Every endpoint the game calls has an in-process equivalent — and on this AMD card a Vulkan backend deletes the entire ZLUDA/Defender/cuDNN/Python-3.11 tower, which exists only because ComfyUI wants CUDA. Plan and evidence in [Architecture-InProcess.md](Architecture-InProcess.md). **Decision needed: extract the game, do not delete the workspace.** | **P0 decision** | — |
| ~~R8-33~~ | ~~**The Cast never records who you've met.** Björn Salt-Tongue, Ingrid the Völva and the hooded figure all appeared across four days; none were captured. The web UI has this panel; the Godot client does not populate one~~ — **fixed**: the Cast is written under state kind `cast`, which the server's `_WS_KINDS` never accepted — every write 400'd silently, exactly like `adventures`. Same bug, third instance. `scripts/check_state_kinds.py` now guards the contract | ✅ | — |
| R8-34 | **The portrait and the gear paper-doll are different people.** The round portrait and the full-body doll are separate diffusion renders with no shared seed or identity anchor, so the hero's face changes between two views of the same character. Compounds R8-24/R8-02 — three portrait defects from one habit: deriving the hero's likeness at the point of use instead of carrying one identity | P1 | L |
| ~~R8-31~~ | ~~**The minimap is not a map** — reads as a random frozen pond: no key points, no labels, and **no marker for where the player is**; plus a grey panel over the mid-section sitting on top of the transcript (see R8-12). Decoration that costs legibility~~ — **fixed by R12-05** — the chart read the world package's static gazetteer instead of `state.world.places`, so no dot ever matched; `clip_contents` was also unset, which is what the stray rectangle was | ✅ | — |
| ~~R8-07~~ | ~~**The player cannot start a fight.**~~ — **fixed**: `Tags.detect_player_attack()` opens combat on the player's own declaration, before the GM answers, so it narrates into a live round. Deliberately skips `_foe_bad_re` (which blocks `figure`/`shape`/`form`) — that list guards against the GM's *incidental* nouns; "I attack X" is intent. Four assertions in `self_check.gd`. Old text: Combat triggers only on the GM's own prose (`tag_parser.gd:92`); three deliberate attacks in 14 turns produced narration and one d20, never initiative. `_foe_bad_re` also blacklists `figure`/`shape`/`form`, so the GM's usual name for an unrevealed enemy can never become a combatant. **This blocks the entire tactical layer** — grid, line of sight, cover, adjacency, death saves — from ever being reached | **P0** | L |
| ~~R8-08~~ | ~~Short rest fires **at full HP** and silently burns the Hit Die~~ — **fixed**: third branch in `GameState.short_rest()`; unhurt, the hour passes and features recharge but the dice stay in hand. New assertion in `tests/playthrough.gd` | ✅ | S |
| ~~R8-09~~ | ~~**Send while a turn is in flight is silently discarded**~~ — **fixed**: keeps the text, shakes the field, deny cue, and says *"The table is still speaking — your words are held, not lost."* | ✅ | S |
| R8-10 | **Location continuity breaks across a long rest** — camped at the barrow-mound, woke in the mead-hall guest room with no travel | P1 | M |
| R8-27 | **Turn latency 45–100 s**, measured five times. Still the dominant cost of play | P1 | L |
| ~~R8-28~~ | ~~**No XP is ever awarded.** Traced: `award_xp` has exactly two callers — a `<xp>` tag from the GM, and `combat.gd:845` on foes slain. With combat unreachable (R8-07) the only reliable source never fired. **Fixing R8-07 should restore the main path**; whether checks/quests should also grant XP is a design call, not a bug~~ — **fixed by R8-07 + R11-01, and now proven.** `finish()` always paid for the slain, but it only runs when a fight ENDS — the player could not start one, and once they could, the GM's dice path resolved attacks without applying damage, so nothing died. self_check now asserts the whole chain: a won fight pays XP and that XP lands on the sheet | ✅ | — |
| R8-11 | Raw parser tags leak into prose — `[[Perception`, `[Active Perception]` rendered verbatim | P2 | S |
| R8-12 | The minimap overlays the transcript and hides the left of every line it reaches | P2 | S |
| R8-13 | The scene backdrop never changes — one plate across 4 days, 3 weather states, 4 locations | P2 | M |
| R8-14 | The Atlas is decoration, not a map — no names, legend, compass, scale, roads or POIs; one unlabelled dot; a fjord drawn as scattered lakes | P2 | L |
| ~~R8-15~~ | ~~**Sell offered with no buyer**~~ — **fixed**: new `GameState.shop_here()` reuses the gate the shop system already had; the price still shows (worth knowing) but the item is disabled with "No one here is buying". Old text: — "Sell — 3 silver" inside a sealed barrow | P2 | S |
| R8-16 | A level-1 Fighter has **no class features** — Powers shows only the Human heritage trait, mislabelled as a class feature and duplicated on Story | P2 | M |
| R8-17 | Starting equipment is one weapon — no armour, shield, pack or rations | P2 | M |
| R8-20 | Destiny labels overlap their nodes; four nodes all named "Gift of Growth" | P2 | S |
| ~~R8-24~~ | ~~Play-screen hero ring stays empty while the same portrait renders on the sheet~~ — **fixed** with ~~R8-02~~: six readers rebuilt `"hero-" + cid`; new `Art.hero_key()` asks the hero for the key they were painted with, and `ensure_hero_portrait` returns early when that art exists, so an adventure no longer re-commissions a face we already own | ✅ | S |
| R8-25 | Sleeping in a hostile place has no consequence — two rests in an opened barrow, hostile figure watching, nothing happened | P2 | M |
| R8-26 | The GM invents consequences that never happened ("vitality lost in battle", no battle fought) | P2 | M |
| ~~R8-18~~ | ~~"Armour Class 12 · 1 worn" counts a wielded weapon as worn~~ — **fixed**: hands hold, only the body wears | P3 | S |
| R8-19 | Item icon contradicts the item — a "Shortblade" drawn as a cruciform arming sword | P3 | S |
| ~~R8-21~~ | ~~Full HP renders as an alarm-red bar~~ — **fixed**: `MythGauge.grade_by_fill` walks danger→gold with the fraction, so colour and value cannot disagree | P3 | S |
| R8-22 | Skills / Powers / Story leave ~700px empty below a cramped top block | P3 | S |
| R8-23 | Item context menu spawns clipped at the window edge and does not flip | P3 | S |
| R8-29 | Time divider printed for the first long rest only | P4 | S |
| R8-30 | Each long rest costs a full dawn-to-dawn day; no way to rest without losing one | P4 | M |

### R9 — combat, driven for real (2026-07-28)

The R8-07 fix works: declaring an attack opens the board. The engine underneath
is the healthiest system in the game — initiative, rounds, enemy AI movement,
action economy, movement budgeting and damage all verified by hand (see
[Playtest-R8.md](Playtest-R8.md) §R9). Two defects stop it being playable.

| # | Item | P | Effort |
|---|------|---|--------|
| ~~R9-01~~ | ~~**Attacks are not range-checked** — a melee blow landed on a foe ~50 ft away without moving. The game checks distance for *movement* ("Too far, or the square is taken") and ignores it for *attacks*. Directly the Director's "is the enemy next to you" question~~ — **fixed by R11-01** — the engine resolves attacks now, and `player_attack`'s reach guard is asserted every run | ✅ | — |
| R9-04 | **Every combat action costs a full GM turn (~90 s)** — a three-round fight is ~10 minutes of waiting. Latency is annoying in exploration; in combat it is fatal | **P0** | L |
| ~~R9-03~~ | ~~**Phantom combat — introduced by the R8-07 fix.** The board opens on the player's declaration without confirming a foe is present; the GM narrated "no sign of them nearby" and "you strike at the unseen foe" while the tracker showed a 16/16 Ice Jotun. Fix by letting the GM's reply confirm the encounter, or restricting the trigger to combatants actually staged — **not** by widening the regex~~ — **fixed**: opening on the declaration alone staged whatever the player named — "I attack the ice jotun" with no jotun in the scene produced a 16/16 Ice Jotun on the tracker while the GM answered "no sign of them nearby". Combat now stages only a foe that appears in the GM's last prose (full name, or a distinctive word of it). An unrecognised target is not refused, just not staged — the message still goes to the GM, who can open a real encounter | ✅ | — |
| ~~R9-02~~ | ~~**Line of sight almost certainly unenforced** — unproven directly, but the 50-ft hit crossed open water and no LOS/cover language exists in the combat UI. Verify against a wall~~ — **fixed** — `cover_between` was correct and asserted for a whole round while `player_attack` never called it, so an arrow crossed a wall as happily as open air. The attack now refuses a blocked line before spending the action and applies 5e cover (+2 half, +5 three-quarters) to any attack, not only ranged | ✅ | — |
| ~~R9-05~~ | ~~**The minimap covers the combat action bar** — "End turn" renders as "nd turn ›". R8-12 hid text; this hides controls~~ — **fixed by R11-03** — the minimap is hidden outright during combat | ✅ | — |
| ~~R9-07~~ | ~~**The four-day session was never persisted** — no CONTINUE *and* Chronicles empty. R8-01 is not a missing button; the save was never written~~ — **fixed** — same root cause as R8-01/R12-01. The four-day session was never lost, only orphaned; 11 adventures recovered by `scripts/rebuild_adventure_index.py` | ✅ | — |
| R9-06 | Equipped weapon contradicts the kit — Quenching said Longsword, combat swung a Korvul Black Iron Hammer | P2 | S |
| ~~R9-08~~ | ~~Ability scores render as floats — `destiny: 15.0, 12.0, 11.0…`~~ — **fixed**: rounded on the way to the eye, not in the data | ✅ | — |
| R9-09 | Forge card text clipped in three places | P2 | S |
| R9-10 | Choosing a banked hero still routes through The Quenching — a forge step where nothing is forged | P2 | S |
| R9-11 | The "choose a world" hint prints ~250 px below the button that refused | P3 | S |
| R9-12 | The Party stage is one toggle on a full screen; all four Difficulty cards use the same sword glyph | P3 | S |

## R11 — the baked board, played ([Playtest-R11.md](Playtest-R11.md))

| id | finding | pri | size |
|----|---------|-----|------|
| ~~R11-01~~ | ~~**The GM adjudicates fights, not the engine — the root cause of R9-01.** The GM narrates "make an attack roll"; `tag_parser._atk_re` turns that into a *generic check*, which has no reach, no target, no AC, no damage and no action economy. Observed: a **natural-20 critical hit** on a foe **55 ft away**, neither combatant moved, target left **17/17**, action never spent. `Combat.player_attack()` is correct and `self_check` proves its reach guard every run — it is simply never called. Re-fixing the guard changes nothing~~ | ✅ | — |
| ~~R11-02~~ | ~~The grid draws 5-ft squares as ~75x40 px **rectangles** — every baked tile stretched 2:1, and a Chebyshev grid drawn where a diagonal is not an orthogonal~~ | ✅ | — |
| ~~R11-03~~ | ~~The board is clipped by the composer, and the minimap is drawn **over** both the board and the action bar — `End turn ›` renders `nd turn ›`, HP readouts half-hidden. R9-05 confirmed, and it covers controls, not just text~~ | ✅ | — |
| ~~R11-04~~ | ~~Terrain patches have hard rectangular edges — undergrowth is a sharp green rectangle on the dirt with no transition~~ | ✅ | — |
| ~~R11-05~~ | ~~The Preview never names the world — tale, hero and difficulty only~~ — **fixed**: the Preview now names the world | ✅ | — |
| ~~R11-06~~ | ~~All three tales share the Free Roam subtitle "wander it as you please"~~ — **fixed**: only free roam wears the free-roam blurb | ✅ | — |

## DEAD CODE — the Odysseus carcass (measured 2026-07-29, half done)

This kept getting deferred behind gameplay work and was nearly missed again.
Numbers are **measured**, not estimated: tracked `.gd/.py/.js/.css/.html/.ts`
lines, excluding `godot/baked/` and `godot/art/`.

### Done in this pass — the browser UI

| | before | after |
|---|---|---|
| **total** | 347,294 | **145,010** |
| `static/` (both web front ends) | 201,617 (58.1%) | **0** |
| `godot/` (the actual game) | 22,692 (6.5%) | 22,692 (**15.6%**) |

`static/` held **two** front ends: `index.html` (the upstream Odysseus workspace
— email, notes, calendar, documents) and `mythforge.html`, a browser build of the
game, which is the second front end the in-process move exists to remove. 193
files, 162 of them `.js`. Twelve page routes went with it.

Safe because the Godot client calls `/api/*` and nothing else, and every sound it
plays is `res://assets/sfx/*.wav` inside the exe. Verified by grep before
deleting, then by booting the trimmed backend and checking every endpoint the
client actually calls (all 200/400-validation; the twelve UI routes 404).

**47 backend test files went with it** (~4.5k lines, 218 tests) — they read
`static/js/*.js` off disk and asserted on its source text, so their subject no
longer exists. Two were kept because they test live Python and only *mention*
`static/` in a docstring; one (`test_upload_multifile.py`) had a single assertion
that parsed `MAX_FILES` out of `fileHandler.js`, now inlined with a comment
saying so, because the rate-limit guard it protects is still worth having.

Method note worth repeating: `grep "static/"` found 44 of them. Five more used
`_REPO / "static" / "js" / ...` path joins and were caught only by diffing
`pytest --collect-only` against HEAD. **A string search is not a dependency
check.** Baseline for that diff: **33 collection errors already existed on HEAD**
— dead tests for routes cut in earlier passes (`memory_routes`,
`research_*`, `vault`, `shell`, device-flow). Those are part of this carcass too
and are not yet cleaned; the count is 32 now only because one of them happened to
test the module deleted here.

### Still to do — the backend, and it needs TRACING not guessing

69% of what remains is backend: `backend-lib` 58,391 (40.3%) + `backend-tests`
41,916 (28.9%). Some is load-bearing — the client still needs this process for
image generation and as the narrator fallback when NobodyWho is unavailable
(Architecture-InProcess.md, Stage 5). Much is not.

The endpoints the Godot client provably calls are only these:

    /api/auth/{login,logout,status}   /api/chat_stream   /api/default-chat
    /api/characters/studio/*          /api/models        /api/presets/templates
    /api/session*  /api/history/*  /api/version  /api/stt/transcribe

**Do not delete by eyeball.** `routes/` is almost entirely live (only
`__init__.py` is truly unreferenced; `chat_helpers`/`gallery_helpers`/
`device_flow` are imported by sibling routes, not `app.py`). `src/` is where the
weight is, and importer counts lie: `research_handler` has 2 importers but
`research_routes` was cut, so those importers may themselves be unreachable. The
job is a reachability trace from the live route set above, then delete the
complement, then delete the tests that only covered it.

Known-dead already found: `src/email_thread_parser.py` (0 importers) — removed.
`src/tool_index.py` still retries **ChromaDB every 30 s** on boot, and ChromaDB
was cut in batch 2; that whole path is dead weight still burning a timer.

Also: `characterStudio.js` existed **twice** (`static/js/` and `static/`, 8,402
and 8,299 lines) — gone with `static/`, but a sign the extraction was never
finished rather than merely paused.

### Not touched on purpose

`/api/shutdown` is called by nothing (it was a web-UI button), but it is an API
endpoint, not a page. Removing API surface belongs to the Stage 5 trace, not to a
"delete the browser UI" pass — keeping the two separate is what makes either one
reviewable.

## R12 — Director's pass on the shipped build (2026-07-29)

Reported from playing the exe. **Priority is set by what blocks testing**, not by
severity in the abstract: the Director's note was *"I hate trying to test with
all these known bugs still in the way."* A bug that makes the next bug harder to
find is worth more than a worse bug that doesn't.

| id | finding | pri | size |
|----|---------|-----|------|
| ~~R12-01~~ | ~~**The save still never persists — no CONTINUE, Chronicles empty.** Reported three times now (R8-01, R9-07, here). Every test session starts from the Forge and a played session cannot be resumed, so nothing downstream of "play for a while" can be tested at all. **This is the top of the list**~~ — **fixed and verified in the shipped build** — CONTINUE — FREE ROAM shows Drao, level 4, day 6 | ✅ | — |
| ~~R12-02~~ | ~~**A login prompt still flashes at startup.** `session.cfg` carries an `odysseus_session` auth cookie, so there is a live auth step in the path — and the 2026-07-22 entry below records login as *removed*. A regression, not a gap~~ — **fixed**: login *was* retired — but login.tscn is the boot scene and showed the name/word fields the whole time it waited for the backend, then vanished. It reads as a regression because it looks like one. The form now starts hidden and appears only if the realm says the door is shut | ✅ | — |
| ~~R12-03~~ | ~~**Four of nine character-sheet tabs are dead** (R8-06). Half the sheet cannot be inspected while testing anything else~~ — **closed — not reproducible**, see R8-06. Probe added to click_driver so a real cover-up would now fail the harness rather than pass it | ✅ | — |
| ~~R12-04~~ | ~~The dragon cut-scene still plays on every start. Unskippable ceremony between the tester and the game~~ — **fixed**: was once per LAUNCH; now once ever (remembered in session.cfg). A first impression can only happen once — after that it is a toll, paid hardest by whoever tests the build most | ✅ | — |
| ~~R12-05~~ | ~~**The minimap is decoration:** no points of interest, no marker for where the player is, and a grey rectangle floating over it (R8-31, R8-12)~~ — **fixed**: the chart read `Rules.world_locations()` — the world package's STATIC gazetteer — while the tale records what it visits in `state.world.places` with its own x/y. A save proves it: here = "Moonwhisper's Cottage", 8 places recorded, none in the package list, so every dot failed the match and the map drew empty. `seen` is also never written on any save, which fog then used to hide the rest. Plus `clip_contents` was never set, so the cover-fit chart spilled outside its frame — that was the "random rectangle" | ✅ | — |
| ~~R12-06~~ | ~~Sheet/Chronicles buttons are mislabelled against their icons — "Sheet" reads as a word while the Chronicles button wears the sheet glyph~~ — **fixed**: `_iconify_toolbar` glyphed eight buttons and skipped SheetBtn, so the record wore the word "Sheet" while CodexBtn wore the SCROLL. The record takes the scroll; cast-and-quests takes the banner | ✅ | — |
| ~~R12-07~~ | ~~**The music is two or three pulsing notes.** Director's steer: use public-domain recordings (IMSLP, Musopen) rather than generating it~~ — **fixed**: melody voice added (sparse, chord-aware, seeded), progressions doubled to 8 chords, loops 27-45s -> 40-64s, and **the three silent worlds got tracks** — fimbulreach, brasshaven and saltmarsh had no `amb_*.wav` at all. Still CC0 by construction: synthesised here, no samples, nothing downloaded | ✅ | — |
| ~~R12-08~~ | ~~The header ring beside the adventure title is empty — no portrait, and no initial either, because `MythPortrait` has no empty state (R8-05). The art-cache eviction exposed it~~ — **fixed**: the art_ready handler passed "" as the fallback glyph, assuming ready meant present. When round_tex returned null anyway the ring had no texture AND no letter, and drew empty | ✅ | — |
| ~~R12-09~~ | ~~**Turns time out waiting on the narrator** (143 s and climbing)~~ — **fixed**: not a slow narrator, the *wrong* narrator. `auto_gm_model()` caps the GM at 9B but runs only at session creation, and `ensure_session` reuses a remembered session id — so a session born under a 14B default stayed pinned to it forever. Measured live: qwen2.5:14b resident with 4.2 GB in VRAM (half spilled to CPU) while llama3.1:8b sat unused. The model is now re-asserted on every reopen via `PATCH /api/session` | ✅ | — |
| ~~R12-10~~ | ~~Two bars at the top showing the same HP and gold~~ — **fixed**: the chips row states both permanently; the arrival line recited them again one row below. An arrival line now says who arrived | ✅ | — |
| ~~R10~~ | ~~Battle terrain overlay does not match the map art~~ — **fixed and verified in play.** Tiles come from the world package; cover dots and impassable hatching sit on exactly the squares that carry the art | ✅ | — |

**Still untested, and why** — the tactical layer (blocked by R8-07), spells
(needs a caster), merchants (never met one), level-up (blocked by R8-28),
chapter close / chronicle / tone knobs (blocked by R8-06), companions, the Lore
Book filling, equip/unequip (only one item ever existed). That list is a
coverage gap, not a clean bill of health.

**Method note.** R8-06 is the sharpest lesson available: the tab rail draws
correctly, screenshots beautifully, and passes any visual audit — while four of
its nine buttons have never worked. The harnesses assert screens are
*reachable*; the audits assert they *look right*. Nothing asserts a drawn
control is **clickable** or an offered action is **legal**. Both new P0s and
three of the four new P1s live in exactly that blind spot.

---

# Backlog — the earlier deep dive (2026-07-18, updated 2026-07-22)

One consolidated view of everything outstanding, pulled from FeatureMatrix,
Roadmap, TechnicalDebt, KnownIssues, FutureIdeas, and this session's sprint.
Priority **P1** (core play) → **P4** (nice-to-have). Effort **S/M/L/XL**.

> **Resuming a session? Read [SESSION-HANDOFF.md](SESSION-HANDOFF.md) first.**

## 0. Resolved 2026-07-22 (World Compiler → shipped worlds → no-login → bug pass)

| Item | Now |
|---|---|
| World Compiler S1–S10 + Reforge | ✅ compiles a world to POPULATED ([WorldCompiler.md](WorldCompiler.md)) |
| Per-material item art (form × material, ~60/world) | ✅ AAA, world-true; rarity = draw-time glow |
| Catalogue visible in play (icons + glow, loot rolls, hero armed from catalogue) | ✅ `Art.item_tex_for`, `Compiler.roll_item`, `kit_for` |
| Backend matte plumbing (Inspyrenet rembg cut-outs) | ✅ verified end-to-end on GPU |
| Seed-stage LLM 504s + invalid-JSON fallbacks | ✅ `complete_json` timeout-exempt + `json_mode` + 3000 tok |
| Four worlds ship PRE-BAKED (saltmarsh, embervale, neonspire, everyday) | ✅ zips in `godot/baked/`, first-run extract, in `worlds.json` |
| **No login** (single-player) | ✅ `AUTH_ENABLED=false` (pm2 + supervisor); client skips login |
| Forge no longer blocks play | ✅ `compile_seed` fired unawaited from campaign forge |
| Playtest bugs: stock icon, no card pictures, dead sheet during load, "loses the thread" | ✅ icon set, card art, `can_panels()`, 180s SSE timeout + Ollama keep-warm |

**Open after 2026-07-22:** tale/world flow decision · sparse `everyday` world ·
verify-in-play · ship-weight (git-LFS?) · `godot/data` gitignore. Full list in
[SESSION-HANDOFF.md](SESSION-HANDOFF.md) §4.

---

> **Reconciliation note.** The First-Complete-Experience sprint (language guard,
> World Skin, Lore Book, skill-tree motif, Chronicles gallery, paper doll, AAA
> sheet, menu legibility) is **not yet in FeatureMatrix/Roadmap** — those trackers
> predate it. §1 lists what this session resolved so the matrix can be updated;
> §2–§5 are the true remaining backlog.

---

## 1. Resolved this session (matrix/roadmap need these rows)

| Item | Was tracked as | Now |
|---|---|---|
| Language integrity guard | (not tracked) | ✅ M-A: pin + drift detect + silent retry |
| Per-world theming beyond 3 built-ins | "per-world theming ✅" (only 3) | ✅ M-B World Skin: 8 families, palette/currency/art/music/materials |
| MythButton engraving contrast | "steel-plate engraving contrast pass 🔲" | ✅ M-E: raised outlined lettering |
| Emoji-free sweep (controls) | "full in-game emoji-free sweep 🔲" | ✅ **COMPLETE (2026-07-18)** — bake pipeline (`Ui.ico`/`[img]` inline + `.icon` on controls); every displayed emoji across game.gd, all 4 forges, windows, autoloads gone. Functional icons → drawn art; garnish → clean text (BG3 rule). Zero glyphs render. |
| Illustrated Lore Book | (not tracked) | ✅ M-C: aggregated encyclopedia + `[[lore]]` growth |
| Chronicles as cover gallery + Continue fold | "Continue → save picker ✅" (plain) | ✅ M-E: illustrated covers, open-book-from-Hall |
| World-adaptive skill tree | "constellation ✅" (single motif) | ✅ M-D: circuit/gears/chart/constellation motifs |
| AAA character sheet | "Hero's Record ✅" (fold list) | ✅ tabbed Record/Gear/Skills/Powers/Story |
| Paper doll + equipment breadth | "3D turntable 🔲", "paper doll (FutureIdeas)" | ✅ M-F Stage A: full-body doll + 13 slots |
| Forge-time portrait preview | "forge-time preview 🔲" | ✅ live Envision in the Appearance stage |
| Race art in hero forge | (not tracked) | ✅ per-race portraits in Heritage |
| Real-UI playthrough test harness | (not tracked) | ✅ `tests/ui_playthrough` drives loot→equip→damage/heal→combat→levelup→persistence through the real game scene; caught 2 shipped crashes |
| `THE END` completion never fired | (not tracked) | ✅ regex bug — `"\b"` was a backspace char; fixed + auto-snapshot + Chronicles complete badge |
| Save-DC spells / class-feature actions / companion kits / B1 / B2 / write-queue | see §2–4 | ✅ all resolved 2026-07-18 (rows struck through below) |

---

## 2. Bugs & correctness (from KnownIssues, re-triaged)

| # | Issue | Pri | Effort | Note |
|---|---|---|---|---|
| B1 | ~~`_show_saves`/Chronicles fetches each save's state **serially**~~ | ~~P2~~ | ✅ | **DONE 2026-07-18** — cards build sync; each state fetch fires concurrently, fills its caption when it lands. |
| B2 | ~~Art cache **never evicts** (no LRU)~~ | ~~P2~~ | ✅ | **DONE** (A2) — 700 MB budget, manifest + LRU `_enforce_budget`/`_evict`. |
| B3 | ~~`Rules.attack_mod` couples to `GameState.inv()`~~ | ✅ | — | Verified stale 2026-07-21 — inv is an explicit param, no GameState fallback. |
| B4 | ~~Combat attack rolls don't play the dice-moment overlay~~ | ✅ | — | ✅ **DONE 2026-07-21** — player_attack returns roll+caption; the swing animates. |
| B5 | ~~Art queue priority lanes~~ | ✅ | — | ✅ **DONE 2026-07-21** — ensure(front=true): battle maps + hero portraits jump menu backfill. |
| B6 | Backend auth = single shared cookie file per OS user | P4 | — | Fine solo; matters at multiplayer. |
| B7 | Godot 4.7 shutdown RID/StringName leak noise (headless) | P4 | — | Upstream; grep-filtered. |

## 3. Technical debt (re-triaged; two got worse this session)

| Debt | Pri | Effort | Note |
|---|---|---|---|
| ~~**game.gd god-script**~~ | ~~P2~~ | ✅ | **DONE 2026-07-18** — A0 split complete: merchant/GM-tuner/level-up/reaction extracted to windows; journal/chronicle/atlas folded into lore_book/world_map. 2461→~2000 lines; what remains is the streaming/tag/combat core. |
| ~~**ForgeFlow base extraction**~~ | ~~P2~~ | ✅ | **DONE 2026-07-18** — ui/forge_flow.gd; all four forges are stage-content only; GM + Companion forges built on it same-day. |
| ~~**Per-world EAS room variants**~~ | ✅ | — | Duplicate row — already done as A1 (`ENV_ROLE` + `env_resolved`), see row below. |
| ~~State writes are fire-and-forget PUTs, no debounce/retry~~ | ~~P2~~ | ✅ | **DONE** (A5) — `save_kind` updates local instantly + enqueues; `_drain_writes` coalesces (last-write-wins) + retries. |
| ~~Per-world EAS room variants (fantasy-flavored ENV_PROMPTS)~~ | ~~P2~~ | ✅ | **DONE** (A1) — `ENV_ROLE` + `env_resolved`/`env_prompt` drive per-world rooms from the skin. |
| Companion kit generic (Fighter/AC13) | ~~P3~~ | ✅ | **DONE 2026-07-18** — `infer_companion_kit` maps role→class/AC/HP. |
| ~~Enemy stats by name-regex tiers~~ | ✅ | — | ✅ **DONE 2026-07-21** — bestiary tier → HP band/AC/atk/dmg dice; regex stays as fallback. |
| ~~Companion kit generic~~ | ✅ | — | Duplicate row — done 2026-07-18 (`infer_companion_kit`). |
| ~~world_map own pan/zoom~~ | ✅ | — | ✅ **DONE 2026-07-21** — MythCamera adopted, hand-rolled camera deleted. |
| ~~Envelope context budgeter~~ | ✅ | — | ✅ **DONE 2026-07-21** — per-section 1400-char word-boundary cap, marked trims. |
| ~~Tests hit the live backend~~ | ✅ | — | Stale — ui_playthrough + click_driver run on Api.test_mode (canned SSE); legacy tests/playthrough.gd is the only live-backend one and is superseded. |
| ~~Terrain sampler colour heuristic~~ | ✅ | — | ✅ **DONE 2026-07-21** — [[terrain]] tag lets the GM lay block/water/cover; heuristic bake stays as fallback. |

## 4. Feature gaps (from FeatureMatrix 🔲/🟡, still open)

**Play systems**
- ~~Save-DC spells~~ — ✅ **DONE 2026-07-18**: foe rolls a save vs your spell DC (tier-derived save mod); for-half/negate; typed vuln/resist.
- ~~More class-feature actions: Bardic Inspiration, Lay on Hands, Wild Shape~~ — ✅ **DONE 2026-07-18** (+ Channel Divinity).
- ~~Token **drag** on the battle grid~~ — ✅ DONE 2026-07-21 (lift, ghost, drop-to-move)
- ~~LLM-authored terrain layout~~ — ✅ DONE 2026-07-21 ([[terrain]] tag)
- ~~ASI split (+1/+1 vs +2)~~ — ✅ DONE 2026-07-21 (all 15 pairs in the ceremony)
- ~~Multiclassing~~ — ✅ **DONE 2026-07-18**: classes[] on the sheet, ceremony redirect, combined caster level, prereqs.
- ~~Recipe-based crafting v2~~ — ✅ DONE 2026-07-21 (recipes table, component consumption, dice-menu craft lane, GM seeds components via loot)

**Shell & creation**
- ~~**GM Forge**~~ — ✅ **DONE 2026-07-18**: full pillar; seals to _global.cgms; Campaign Forge Voice stage offers forged personas.
- ~~**Persona/Companion Forge**~~ — ✅ **DONE 2026-07-18**: full pillar; npc-<slug> portrait shared with journal/codex; Party stage picks ride in on day one.
- ~~Companion chat: seed photos, clear-chat~~ — ✅ DONE 2026-07-21 (fireside staging + priority portrait + Clear-the-table)
- ~~Campaigns tab~~ — ✅ DONE 2026-07-21 (CAMPAIGNS shelf in the Hall)
- ~~Staggered card-entrance animation~~ — ✅ DONE 2026-07-21 (worlds grid + campaign shelf)

**Presentation**
- ~~**Controller support**~~ — ✅ **DONE 2026-07-18**: Pad autoload (runtime InputMap), universal focus seeding, grid pad cursor, mf_roll/mf_end_turn. Ceilings: stage rail + combat spell links stay mouse-only.
- ~~Combat music system~~ — ✅ verified already shipped (combat drone crossfade + [[music cue]])
- ~~Raw dice tray~~ — ✅ DONE 2026-07-21 (d4–d100 + expression roller in the dice menu)
- ~~Minimap overlay~~ — ✅ DONE 2026-07-21 (corner chart, lamp-dots, you-are-here, click → Atlas)
- ~~x/y world-map render + auto here-tracking~~ — ✅ DONE 2026-07-21 (x/y chart shipped earlier; [[scene]] prose now moves the pin)
- ~~Complete-badge + auto-snapshot on THE END~~ — ✅ shipped with the THE END regex fix (2026-07-18)
- ~~Recap art~~ — ✅ DONE 2026-07-21 (world seal on the recap card); scene-reactive ambient layers covered by [[mood]]/[[music]] presentation tags

**EAS (M8 next waves)**
- ~~Generated prop/frame/banner assets~~ — ✅ first slice DONE 2026-07-21 (heraldic title banner; MythPlate is the shared frame); more props land as screens call for them
- ~~Title-screen environment painting~~ — ✅ DONE 2026-07-21 (env-hall behind the title)
- ~~Dialogue fireside with NPC portrait staging~~ — ✅ DONE 2026-07-21 (fireside room + breathing portrait at the table)
- (Per-world room variants folded into §3 above)

**AI & voice**
- **TTS narration** — ⛔ BLOCKED on a server-side voice provider (probe 503); client wiring is ready
- ~~STT push-to-talk~~ — ✅ DONE 2026-07-21 (hold-the-quill record → /api/stt/transcribe → input box; server 503s politely without a provider)
- ~~Inline message edit~~ — ✅ DONE 2026-07-21 (Ctrl+E rewords your last line, stale exchange leaves the thread)
- Model routing — ⛔ BLOCKED: backend model is per-session (chat_stream has no per-message override); needs a backend field before any client work
- Vision loop — ⛔ BLOCKED: /describe is an appearance-anchor endpoint (upload-based); a scene-describe route is a backend task
- ~~Structured per-NPC voices~~ — ✅ DONE 2026-07-21 ([[npc voice=]] → cast canon, dialogue kept in voice)

## 5. This-sprint carry-overs (deliberately deferred)

| Item | State | Unlock |
|---|---|---|
| **M-F Stage C — true 3D character** | Paused by Director | An asset-sourcing decision (commissioned vs. generated-3D vs. bought pack). See CharacterRender.md. |
| Narration bbcode emoji (💰🎒📖 in `_say_system`) | ✅ **DONE (2026-07-18)** — `_say_system(text, glyph)` leads with a live MythIcon; RichText uses `Ui.ico`. Zero glyphs. | — |
| World Skin palette from the LLM | Deterministic families only | Worldsmith emits palette hexes → merge → contrast-clamp (the guard is already in place). |
| ~~**Material textures on surfaces**~~ | ✅ **DONE 2026-07-21** — `stone_tex`/`parchment_tex` generators + per-family `panel`/`page` material roles; menu hero panel + Lore Book pages wear them (stone in fantasy-kin, glass on cyber/space, leather in Everyday). Extend to more surfaces as screenshots direct. | — |
| ~~**World-skinned vendor stock**~~ | ✅ **DONE 2026-07-21** — `vendor_stock_cyber/everyday/space` in tables.json (names carry mk_item classifier keywords so stats resolve); `Rules.vendor_stock()` picks by family, others fall back to the fantasy base. | — |
| ~~**Real-UI click-driver playtest tool**~~ | ✅ **DONE 2026-07-21** — `tests/click_driver.tscn`: real synthesized mouse events through the input pipeline (embedder-routed into dialog windows), per-station occlusion/off-screen audit, outcome-asserted click paths (menu, 9 tabs, shop, book), PNGs per station in windowed runs, `MF_LIVE=1` for the live stack. **First run caught 2 shipped bugs**: tab rail overflowed the window (Chronicle/The Table unreachable) and the menu wrapped taller than the screen (OK button off-screen). | — |

## 6. FutureIdeas parking lot (uncommitted)

Relationship/reputation web · engine-verified quest objectives · world-sim depth
(NPC goals, seasons, festivals) · camp mode with banter · animated 3D dice ·
cinematic finale slideshow + stats · photo/share mode · Steam achievements &
Workshop · co-op party + WebRTC voice · one-click bundled backend installer.

---

## 7. Recommended next (if the sprint continues)

Ranked by **impact ÷ effort**, favouring things this session made urgent or exposed:

1. **Per-world EAS room variants** (§3) — M. The World Skin themes colours but the
   *rooms* are still fantasy; a cyber campaign in a fantasy forge is the most
   visible remaining inconsistency. Skin should drive `ENV_PROMPTS`.
2. **Art-cache LRU + parallel save fetch** (B2 + B1) — M together. We generate a lot
   more art now, and the Chronicles gallery made serial fetches felt.
3. **ForgeFlow base extraction** (§3) — M. Four forges of duplicated scaffold; pays
   down real debt and de-risks the next forge.
4. **Save-DC spells** (§4) — M. The biggest *mechanical* gap in combat (only damage
   spells resolve); casters feel half-implemented without it.
5. **game.gd split** (§3) — L. The structural keystone for everything after; best done
   deliberately, not under feature pressure.
6. **Controller support** (§4) — L. The one P2 platform requirement still open.

Everything else is genuine P3/P4 polish or is blocked (TTS) / paused (3D) / parked
(FutureIdeas).

## 8. Doc hygiene (should follow this audit)

- Add matrix rows for the §1 sprint work (the matrix's own rule: no feature ships
  un-tracked). New docs already exist: `Sprint-FirstImpression.md`, `WorldSkin.md`,
  `CharacterRender.md`.
- Retire the resolved 🔲 markers in FeatureMatrix (engraving contrast, forge-time
  preview, per-world theming scope).
- Add a Roadmap **M10 — First Complete Experience** milestone summarising M-A…M-F.
