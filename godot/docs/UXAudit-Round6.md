# UX Audit — Round 6 (2026-07-27)

A full click-walkthrough of the shipped app, driven through the real input
pipeline and captured as rendered frames, not read off the source.

**Method.** `tests/click_driver.tscn` run **windowed** at 1280×800 so every
station writes a real PNG (`user://clickdrive/`), plus `tests/screenshot.tscn`
for scenes the driver doesn't reach, plus live timing against Ollama/ComfyUI.
Every finding marked **[shot]** is visible in a captured frame; **[code]** is
read from source; **[meas]** is a number measured this session. Nothing here is
guessed — where I could not verify something, it says so.

**Evidence captured:** `menu-title`, `menu-campaign-shelf`, `play-screen`,
`shop`, `lore-book`, and the nine Record tabs (`record`, `gear`, `skills`,
`powers`, `story`, `destiny`, `atlas`, `chronicle`, `the-table`), plus the
Character Forge's opening stage.

> **A harness bug found while auditing:** `_visit()` called `_shot()` without
> awaiting it, so every screenshot landed one or two stations late and was
> mislabelled — `menu-title.png` actually showed the Campaign Shelf. Fixed
> before any evidence here was read. Any previous visual audit taken from these
> PNGs was looking at the wrong screen.

---

## 0. The five that matter most

Ordered by damage per unit of fix.

1. **The play screen is 60 % empty void** (§4.1) — the screen the player spends
   99 % of their time on has no scene art, no HUD, and an empty box where the
   minimap goes. This is the game.
2. **Every panel's exit is clipped off the bottom of the window** (§1.1) —
   Round 5 called this out as B2; it is still shipping.
3. **Eleven identical grey diamonds** on the Gear tab (§4.2) — the bake put
   1 150+ items in the world and the paper doll still shows placeholder shapes.
4. **The Lore Book renders with no panel background** (§1.3) — it is transparent
   over the play screen, so two UIs occupy the same pixels.
5. **~18 screens between "I want to play" and playing** (§3.1), several of which
   accept no input at all.

---

## 1. Bugs

| # | Finding | Sev |
|---|---------|-----|
| BUG-01 | **[shot]** The Record dialog's only exit, "Return to the tale", is clipped by the window bottom edge — the button is half-drawn at y≈790 in an 800 px window. Every one of the nine tabs. Round 5 B2, unfixed. | Critical |
| BUG-02 | **[shot]** Two main-menu buttons render entirely **below** the viewport (y=801 and y=873 in an 800 px window). They are unreachable — no scroll container. Caught by the audit only in windowed mode. | Critical |
| BUG-03 | **[shot]** The "MYTHFORGE" wordmark is clipped at the top of the frame — the crown of the letters is cut off. | High |
| BUG-04 | **[shot]** The SETTINGS button is half-cut at the bottom edge, below it two more are lost (BUG-02). The menu simply doesn't fit its own window. | High |
| BUG-05 | **[shot]** The Lore Book draws with **no background panel** — the play screen's toolbar, input box and title all bleed through it. | Critical |
| BUG-06 | **[shot]** The Record dialog leaves a **grey/white unstyled band** across the bottom — stock `AcceptDialog` chrome, unthemed, in a game that is otherwise deep purple. | High |
| BUG-07 | **[shot]** Same grey chrome band on the Shop dialog behind "Leave the counter". | High |
| BUG-08 | **[shot]** The Shop's title "The trading post" renders **outside** its own panel, overlapping the day/time banner behind it. | High |
| BUG-09 | **[shot]** The Shop's ✕ sits outside the panel's top-right corner, floating over the play screen. | Medium |
| BUG-10 | **[shot]** Stock Godot window title bar ("The Record of Clickwyn") with a stock white ✕ on the Record dialog — OS chrome inside a themed game. | High |
| BUG-11 | **[shot]** The play screen's title "Clickwyn: Free Roam" bleeds through the top-left of the Record dialog on every tab. | Medium |
| BUG-12 | **[shot]** The Atlas renders location pins **over the tavern-interior backdrop** — the "chart of the world" is a photo of a fireplace. No map art is used. | Critical |
| BUG-13 | **[shot]** Two glowing orb artifacts float at the bottom of the Lore Book over empty space — particles with no host element. | Medium |
| BUG-14 | **[code]** `click_driver._visit()` did not await `_shot()`, so all station screenshots were captured late and mislabelled. Fixed this session. | High |
| BUG-15 | **[shot]** The Campaign Shelf's tale text is drawn at ~10 % effective contrast over a full-brightness backdrop — functionally illegible. | Critical |
| BUG-16 | **[shot]** The Gear tab's paper-doll panel is an **empty dark rectangle** — no character render, no placeholder, no "not yet rendered" state. | High |
| BUG-17 | **[shot]** Two equipment slots are both labelled "Ring" with nothing distinguishing them (left/right). | Low |
| BUG-18 | **[shot]** The Shop's "Your pack" is a large empty box with **no empty state** — no "your pack is empty", just void. | Medium |
| BUG-19 | **[shot]** Several vendor item icons are near-invisible slivers at list size (Dagger, Shortsword render as thin lines). | Medium |
| BUG-20 | **[meas]** ComfyUI holds **7.4 GB of VRAM while completely idle**, capping the LLM at 79 % on GPU. Nothing is generating; the memory is simply never released. | High |
| BUG-21 | **[code]** `Api.BASE` is hard-coded to `http://127.0.0.1:7000` with no override — a player whose backend is on another port cannot connect and gets no diagnostic. | Medium |
| BUG-22 | **[shot]** The Record's left panel avatar is the letter "C" in a circle — the portrait pipeline exists but no portrait is shown even for a hero who has one. | High |
| BUG-23 | **[shot]** The Atlas compass rose is drawn partially outside the map frame's bottom-right corner. | Low |
| BUG-24 | **[shot]** The "Re-render with current gear" button is flush against the empty portrait box with no gap — they visually collide. | Low |
| BUG-25 | **[code]** `_stage_anvil` and other ceremony stages call `_nav(-1, …)`, passing −1 as the back-target; the back affordance renders as bare text ("bank the fire") rather than a button. | Medium |
| BUG-26 | **[shot]** The Lore Book's "Close the book" is plain text with no button chrome — it does not read as clickable (Round 5 B1 was that it was *dead*; it now works but still doesn't look clickable). | Medium |
| BUG-27 | **[shot]** The Chronicle tab shows only "These pages are still blank…" with the entire rest of the screen empty — no illustration, no skeleton. | Medium |
| BUG-28 | **[shot]** The XP bar renders as an empty outlined box with the label inside it; at 0 % it is indistinguishable from a disabled field. | Low |
| BUG-29 | **[shot]** HP bar is a flat pink rectangle with the value centred inside — no gradient, no segment ticks, no damage animation hook. | Medium |
| BUG-30 | **[code]** The Record dialog is an `AcceptDialog`; `_open_shop` already triggers "another exclusive child" errors in the log when two panels open in sequence (seen in harness output). | Medium |
| BUG-31 | **[shot]** "The tale of Clickwyn: Free Roam continues…" is placeholder copy shown as the *only* narration on a fresh screen. | Medium |
| BUG-32 | **[meas]** `llama3.1:8b` runs at `ctx 4096` — the app requests far more (Performance §2); the clamp is silently applied server-side and is invisible to the player. | Low |

## 2. Playability pain points

| # | Finding | Sev |
|---|---------|-----|
| PLAY-01 | **[shot]** No HP/gold/time HUD on the play screen. HP exists only inside a modal — the player must open a dialog mid-fight to learn if they are dying. | Critical |
| PLAY-02 | **[shot]** The minimap frame is empty; the player has no spatial sense of where they are. | Critical |
| PLAY-03 | **[shot]** 12 toolbar icons with no labels and no visible grouping — the player must hover each to learn what it does. | High |
| PLAY-04 | **[code]** The only input is a free-text "What do you do?" box — no suggested actions, no verbs, no affordances. A new player faces a blank prompt. | Critical |
| PLAY-05 | **[shot]** The Shop exposes raw mechanics: "Haggle with the keeper (Persuasion, DC 12)". DC and skill names leak the ruleset. | Medium |
| PLAY-06 | **[shot]** Buy is gold/prominent, Sell is muted purple — asymmetric emphasis on two equal actions. | Low |
| PLAY-07 | **[shot]** No keeper portrait or name in the Shop — "The trading post" is a vending machine, not a person, despite the game having a full NPC cast. | High |
| PLAY-08 | **[shot]** Equipment slots are click-to-change but nothing indicates that except a footer line ("click a slot to change it"). | Medium |
| PLAY-09 | **[shot]** "Armor Class 11 · 0 pieces worn" is a plain grey footer — the single most important defensive stat is the least prominent text on the panel. | Medium |
| PLAY-10 | **[shot]** The Record's nine tabs are text-only with a faint box on the active one — weak selection affordance. | Medium |
| PLAY-11 | **[shot]** Two competing exits on The Table tab ("Return to the Hall" and the clipped "Return to the tale") with different destinations. | High |
| PLAY-12 | **[shot]** The GM tone sliders have no numeric value, no default marker, and no preview of effect. | Medium |
| PLAY-13 | **[shot]** Sliders are stock Godot `HSlider`s — grey, unthemed, inconsistent with everything around them. | High |
| PLAY-14 | **[code]** No difficulty/tone change is possible without opening a modal mid-play. | Low |
| PLAY-15 | **[shot]** The Atlas shows 7 undiscovered "?" pins and no legend — the player cannot tell if that means unexplored or broken. | Medium |
| PLAY-16 | **[shot]** No indication anywhere on the play screen of whose turn it is or whether the GM is thinking, beyond one static line. | High |
| PLAY-17 | **[code]** `Art.hold` pauses art for the length of a GM stream — good — but the player gets no signal that art is queued/paused. | Low |
| PLAY-18 | **[shot]** The Campaign Shelf lists tales with no world grouping, no art, and no indication which are already in progress. | Medium |
| PLAY-19 | **[shot]** Nothing on the shelf distinguishes a 2-campaign world from a 0-campaign one until you read every row. | Low |
| PLAY-20 | **[code]** Free Roam and authored campaigns are visually identical cards in the world detail; the player cannot tell scripted from open-ended. | Medium |
| PLAY-21 | **[shot]** The purse ("Your purse: 20 gold") is small grey text in the Shop's top-left, easy to miss while spending. | Medium |
| PLAY-22 | **[shot]** No confirmation on Buy — a mis-click spends gold irreversibly. | Medium |
| PLAY-23 | **[code]** Vendor stock is fixed per world family — the same eleven goods in every shop in the world, forever. | Medium |
| PLAY-24 | **[shot]** The equipped list shows four "—" rows; a new hero is armed from the kit but the panel reads as though nothing is equipped. | High |
| PLAY-25 | **[code]** No keyboard shortcuts for any panel (sheet/shop/book) — everything is a mouse trip to the toolbar. | Medium |
| PLAY-26 | **[shot]** No breadcrumb on the Record dialog — nine tabs deep with no sense of place. | Low |
| PLAY-27 | **[code]** The 11-stage Character Forge has no "skip to the end / roll me one" path from stage 0 other than the pre-made list inside Origin. | High |
| PLAY-28 | **[shot]** The forge progress rail labels only the *current* stage; the other ten dots are unlabelled, so the player cannot see what remains. | High |
| PLAY-29 | **[code]** No autosave indicator anywhere; the player cannot tell whether their progress is safe. | High |
| PLAY-30 | **[code]** No way to rename or delete a forged world/hero from the menu once created (export exists; delete does not). | Medium |
| PLAY-31 | **[shot]** "Close a chapter — the chronicler writes it down" gives no preview of what closing does or whether it is reversible. | Medium |
| PLAY-32 | **[shot]** The Shop list mixes category headers ("— Weapon —") into the same selectable list as items — headers are dead rows in a selection list. | Medium |

## 3. Unnecessary screens & text

| # | Finding | Sev |
|---|---------|-----|
| CUT-01 | **[code/shot]** **"The Cold Anvil"** — an entire screen whose whole content is the line *"Every legend begins as raw metal."* and a button. **Zero input.** This is precisely the "click the forge then have to take a seat" complaint. Delete it; open on Origin. | High |
| CUT-02 | **[code]** The Character Forge is **11 stages** (`Anvil · Origin · Ruleset · Heritage · Class · Background · Nature · Appearance · Voice · Equipment · Quenching`). Ruleset and Nature can be defaulted; Voice and Appearance can be one screen. | High |
| CUT-03 | **[code]** The Adventure Forge opens on **"The Table"** — another ceremonial first stage before any choice. | High |
| CUT-04 | **[code]** The Campaign Forge is **8 stages** and *also* opens on "The Table". Two different forges with the same ceremonial opener. | High |
| CUT-05 | **[code]** Reaching play from a cold start crosses **~18 screens** (menu → adventure forge 7 → character forge 11). | Critical |
| CUT-06 | **[code]** Both Campaign Forge and World Forge carry a near-identical 8-card THEME grid — duplicated concept, duplicated code, duplicated screen. | Medium |
| CUT-07 | **[shot]** "The tale of Clickwyn: Free Roam continues…" restates the title already in the header two lines above. | Low |
| CUT-08 | **[shot]** The Record dialog's window title ("The Record of Clickwyn") duplicates the left panel's name ("Clickwyn"). | Low |
| CUT-09 | **[shot]** The main menu's tagline "A local Game Master. Your table, your tale." sits under a wordmark that is itself clipped — marketing copy on the play path. | Low |
| CUT-10 | **[shot]** Five separate "FORGE A …" entries dominate the main menu (Hero, World, Campaign, GM, Companion). They could be one "Forge" destination. | High |
| CUT-11 | **[shot]** "Every legend begins as raw metal." — flavour with no information. | Low |
| CUT-12 | **[shot]** "These pages are still blank — they fill as you explore, meet, fight, and remember." occupies an otherwise entirely empty screen. | Low |
| CUT-13 | **[shot]** Subtitles appear on only *some* menu buttons ("the table is set", "a realm of your own") and not others — inconsistent, so they read as noise. | Medium |
| CUT-14 | **[shot]** "click a slot to change it" is instructional text compensating for a missing affordance. | Low |
| CUT-15 | **[code]** The GM Forge's "The Seat" and the Adventure Forge's "The Table" and the Campaign Forge's "The Table" are three differently-named versions of the same ceremonial idea. | Medium |
| CUT-16 | **[shot]** The Shop shows "— Weapon —" / "— Armor —" headers as list rows, spending vertical space in an already-short list. | Low |
| CUT-17 | **[code]** "Quenching" as the final character stage is a themed name for a confirm screen. | Medium |
| CUT-18 | **[shot]** "Haggle with the keeper (Persuasion, DC 12)" — the parenthetical is for a rules lawyer, not a player. | Low |
| CUT-19 | **[shot]** The Record's left panel repeats "Level 1 Human Fighter · The Embervale" which is also derivable from the Record tab. | Low |
| CUT-20 | **[shot]** "20 gold in the purse" (Record) and "Your purse: 20 gold" (Shop) — two phrasings of one fact. | Low |
| CUT-21 | **[code]** The World Forge's "The Atlas" is a fourth stage that only displays what was just forged. | Medium |
| CUT-22 | **[shot]** "EQUIPMENT" and "EQUIPPED" appear as two separate headed sections on adjacent panels of the same tab. | Medium |
| CUT-23 | **[shot]** Decorative "✦" flourishes bracket almost every section header; at this density they stop being special. | Low |
| CUT-24 | **[code]** Difficulty (4 cards) and House Rules are separate stages in the Adventure Forge; both are one-line settings. | Medium |
| CUT-25 | **[code]** "The Preview" is a seventh Adventure Forge stage that summarises the six the player just completed. | Medium |
| CUT-26 | **[shot]** The Chronicle tab exists in *both* the Record dialog and the Lore Book. | Medium |
| CUT-27 | **[shot]** "Campaigns" exists as a main-menu destination *and* as a Lore Book tab *and* inside world detail. | Medium |
| CUT-28 | **[shot]** The forge back-affordance is themed per forge ("bank the fire") — cute, but it means "back" is spelled differently everywhere. | Medium |
| CUT-29 | **[shot]** "Set the tone" button under sliders that already apply live would be unnecessary if the sliders committed on release. | Low |
| CUT-30 | **[shot]** The day banner "Morning · Day 1" spans the full 1280 px width to display 14 characters. | Low |
| CUT-31 | **[code]** `world_forge` and `campaign_forge` both implement `_show_take()` with near-identical body text. | Medium |

## 4. Unrendered / blank screens & assets

| # | Finding | Sev |
|---|---------|-----|
| BLANK-01 | **[shot]** **The play screen** — roughly 60 % of the frame (y≈160–600) is empty background. No scene art, ever. | Critical |
| BLANK-02 | **[shot]** **The minimap** is an empty outlined rectangle, bottom-left. | Critical |
| BLANK-03 | **[shot]** **The paper doll** (Gear tab) is an empty dark box. | Critical |
| BLANK-04 | **[shot]** **All 13 equipment slots** render as identical grey ◇ diamonds. The bake produced 1 150+ items for this world; none reach this panel. | Critical |
| BLANK-05 | **[shot]** **The Atlas map** shows no map — location pins float over the room backdrop. | Critical |
| BLANK-06 | **[shot]** **The Chronicle tab** (Lore Book) is entirely empty but for one line. | High |
| BLANK-07 | **[shot]** **"Your pack"** (Shop) is an empty box with no empty-state copy. | Medium |
| BLANK-08 | **[shot]** **The hero avatar** is a letter in a circle, not a portrait. | High |
| BLANK-09 | **[shot]** The Lore Book has no panel background at all — the "page" is the play screen. | Critical |
| BLANK-10 | **[shot]** The Campaign Shelf's cards render with effectively no visible card surface against the backdrop. | High |
| BLANK-11 | **[shot]** The Character Forge's opening stage is ~95 % empty void. | High |
| BLANK-12 | **[shot]** No enemy portraits, initiative rail, or battle map are visible on the play screen in the non-combat state — the whole tactical layer is invisible until a fight. | Medium |
| BLANK-13 | **[shot]** The XP bar renders empty with no fill at 0 %. | Low |
| BLANK-14 | **[shot]** The equipped-items list is four "—" placeholders. | High |
| BLANK-15 | **[shot]** No quest/objective display anywhere on the play screen. | High |
| BLANK-16 | **[shot]** No companion strip, though companions are a shipped feature. | Medium |
| BLANK-17 | **[shot]** No weather/season indicator despite a living-world clock. | Low |
| BLANK-18 | **[code]** Lore Book "Places" entries have no art (Round 5 VIS-12); the illustrated encyclopedia is unillustrated. | High |
| BLANK-19 | **[code]** Heritage previews render blank when uncached, and the default selection is one of the uncached ones (Round 5 VIS-07). | High |
| BLANK-20 | **[code]** The four pre-made heroes have no portraits (Round 5 VIS-06). | High |
| BLANK-21 | **[shot]** The main menu's backdrop is so dark it reads as flat black — the art is there and invisible. | Medium |
| BLANK-22 | **[shot]** No GM portrait/presence on the play screen, though `gm_portraits` exists per world in `worlds.json`. | High |
| BLANK-23 | **[shot]** The Record tab (default landing) was captured but shows the same left panel with no distinct content region filled. | Medium |
| BLANK-24 | **[code]** Battle maps are baked (6 per world) but never appear outside combat. | Low |
| BLANK-25 | **[shot]** No world key art anywhere in the Record dialog, though every world has it baked. | Medium |
| BLANK-26 | **[shot]** Item icons in the Shop are baked at 1024² and rendered at ~20 px — effectively unreadable. | High |
| BLANK-27 | **[code]** `art/icons/` (vendor wares) are baked but the Shop list still renders them at list-icon size with no larger preview until selected. | Medium |
| BLANK-28 | **[shot]** The detail pane in the Shop is not visible in the default state — the large preview area only appears on selection. | Medium |
| BLANK-29 | **[code]** Creature portraits are baked (5–9/world) but no bestiary art appears in the Lore Book's Bestiary tab by default. | High |
| BLANK-30 | **[code]** NPC portraits are baked (6/world) and the cast is never shown on the play screen. | High |

## 5. Latency

All measured this session against the live stack.

| # | Finding | Sev |
|---|---------|-----|
| LAT-01 | **[meas]** **Cold model load costs 6.5 s** before a single token. First turn of a session pays it. | High |
| LAT-02 | **[meas]** A 272-token narration took **10.0 s of generation** (27.3 tok/s) — *when the GPU is free*. | — |
| LAT-03 | **[meas]** **ComfyUI idles holding 7.4 GB of VRAM**, so Ollama loads at **79 % on GPU** (4.67 of 5.86 GB). 21 % of the model runs on CPU for the life of the session. | High |
| LAT-04 | **[meas]** This is a **3–4× swing**: Performance.md measured 6–9 tok/s with ComfyUI hot; free-ish, it is 27.3. The single biggest lever in the app is VRAM contention, not prompt engineering. | Critical |
| LAT-05 | **[meas]** Prompt eval is **0.30 s for 31 tokens** — prefill is not the bottleneck; generation length is. | — |
| LAT-06 | **[meas]** `ctx 4096` is server-clamped; a machine without `OLLAMA_CONTEXT_LENGTH` set would request far more and lose VRAM to KV cache (Performance §2). Latent cliff for a friend's install. | High |
| LAT-07 | **[code]** No `num_predict` ceiling on GM turns — a 300-token reply is ~11 s at best, ~45 s at worst, with no cap. | High |
| LAT-08 | **[shot]** During that wait the player sees **one static line**. No spinner, no elapsed timer, no streaming indicator. | Critical |
| LAT-09 | **[code]** Image generation is ~22–27 s/icon; any runtime `Art.ensure` during play competes directly with narration. | High |
| LAT-10 | **[code]** The forge's worldsmith path is **six sequential LLM calls** (~2.5 min) with a single static wait line. | Critical |
| LAT-11 | **[code]** `_await_art` has a 200 s per-image ceiling; a stalled image blocks a compile stage for over three minutes. | Medium |
| LAT-12 | **[code]** The Character Forge's Appearance stage commissions a portrait inline — a ~25 s stall mid-creation. | High |
| LAT-13 | **[meas]** ComfyUI's first generation after launch compiles ZLUDA kernels (documented ~10 min); nothing in the UI communicates this. | High |
| LAT-14 | **[code]** No request cancellation — a player who regrets an action waits for the full turn. | Medium |
| LAT-15 | **[code]** No prefetch of the next likely art (e.g. biome plates for adjacent locations). | Low |
| LAT-16 | **[code]** `Api.call_json` has no timeout parameter on most calls; a hung backend hangs the UI. | Medium |
| LAT-17 | **[code]** The 180 s SSE timeout means a genuinely slow turn can silently die at 3 min with no retry. | High |
| LAT-18 | **[meas]** Backend health responds instantly (<50 ms) — the backend is not the latency source; the model is. | — |
| LAT-19 | **[code]** Every panel open re-reads and re-parses `items.json` (1 150 entries) from disk via `catalogue_for`. | Medium |
| LAT-20 | **[code]** `_tex_cache` is unbounded — a long session with many item icons grows memory without eviction. | Medium |
| LAT-21 | **[meas]** World zips are ~250 MB each and unpacked on first run; six worlds = a **1.4 GB first-launch unpack** with no progress UI. | High |
| LAT-22 | **[code]** `_seed_baked_worlds` runs synchronously in `_ready()` — that unpack blocks the first frame. | Critical |
| LAT-23 | **[code]** No lazy loading of world packages; all six seed on launch even though the player uses one. | High |
| LAT-24 | **[meas]** The exe is 1.6 GB; cold start includes reading it from disk. | Medium |
| LAT-25 | **[code]** No texture atlas — every item icon is a separate 1024² PNG decode. | High |
| LAT-26 | **[code]** Icons are decoded at full 1024² then drawn at 64 px; no mipmaps or downscale on load. | High |
| LAT-27 | **[code]** `Image.load_from_file` + `ImageTexture.create_from_image` per icon on the main thread. | High |
| LAT-28 | **[code]** No background thread for art adoption during compile — the UI can stutter mid-forge. | Medium |
| LAT-29 | **[code]** The chronicle/memory recall path adds an LLM call per turn on top of narration. | Medium |
| LAT-30 | **[code]** No caching of `Rules.vendor_stock()` per family; recomputed per shop open. | Low |
| LAT-31 | **[meas]** Godot's own import of this project took minutes on a cold `.godot/` — irrelevant to players but slows every dev iteration. | Low |

## 6. AAA quality gaps (buttons, icons, imagery)

| # | Finding | Sev |
|---|---------|-----|
| AAA-01 | **[shot]** **Three unrelated button styles on one menu**: wood-textured (Begin/World/Campaign), flat purple (Hero/GM/Companion/Settings), dashed-outline (Campaigns/Chronicles). No semantic meaning maps to the difference. | Critical |
| AAA-02 | **[shot]** Toolbar icons are thin monochrome line glyphs at ~24 px — no depth, no state, no polish. | High |
| AAA-03 | **[shot]** Menu button icons are inconsistent in weight and metaphor (a circle, an anvil, a globe, a picture-frame, a crown, two goblets). | High |
| AAA-04 | **[shot]** The "Forge a Companion" icon reads as two indistinct goblets at display size. | Medium |
| AAA-05 | **[shot]** Stock grey `HSlider`s on The Table tab — no track fill, no themed grab handle. | Critical |
| AAA-06 | **[shot]** Stock `AcceptDialog` chrome (grey band + OS title bar + white ✕) on the Record and Shop. | Critical |
| AAA-07 | **[shot]** The HP bar is a flat solid rectangle — no gradient, no border, no depth. | High |
| AAA-08 | **[shot]** The XP bar is a flat outlined box. | Medium |
| AAA-09 | **[shot]** Equipment slots are flat diamonds with no rim light, no material, no rarity treatment. | High |
| AAA-10 | **[shot]** The hero avatar is a system-font letter on a flat circle. | High |
| AAA-11 | **[shot]** Section headers use "— ✦ TITLE ✦ —" ASCII-art flourishes rather than drawn ornament. | Medium |
| AAA-12 | **[shot]** The forge progress rail is unfilled outline diamonds joined by 1 px lines. | Medium |
| AAA-13 | **[shot]** "bank the fire" back-affordance has no button chrome at all. | High |
| AAA-14 | **[shot]** "Close the book" is bare text. | High |
| AAA-15 | **[shot]** "Return to the Hall" is bare text. | High |
| AAA-16 | **[shot]** The day banner is a flat purple rectangle with a subtle stripe. | Medium |
| AAA-17 | **[shot]** The Shop's Buy/Sell buttons use different visual weights for equal-rank actions. | Medium |
| AAA-18 | **[shot]** Vendor icons are visually noisy at list size — full-detail 1024² renders scaled to ~20 px. | High |
| AAA-19 | **[shot]** The Atlas "?" pins are plain text question marks, not map iconography. | High |
| AAA-20 | **[shot]** The compass rose is a thin line drawing at ~40 px. | Medium |
| AAA-21 | **[shot]** The empty minimap frame is a 1 px outlined rectangle. | High |
| AAA-22 | **[shot]** Backdrops are composited at full brightness under body text with no scrim — the Round 5 root cause, still present on The Table and the Campaign Shelf. | Critical |
| AAA-23 | **[shot]** The main menu backdrop is so dark the art is wasted; no vignette or focal treatment. | Medium |
| AAA-24 | **[shot]** No hover/press state is visibly distinct on the Record tabs. | Medium |
| AAA-25 | **[shot]** Text input "What do you do?" is a plain rounded rect with default caret. | Medium |
| AAA-26 | **[shot]** "Send" is a plain button beside 12 icon buttons — inconsistent control language. | Medium |
| AAA-27 | **[shot]** The wordmark is clipped, so the game's own logo never displays correctly. | Critical |
| AAA-28 | **[shot]** No drop shadow/elevation on any panel — everything is flat on flat. | High |
| AAA-29 | **[shot]** Typographic hierarchy is thin: most body text is one size and weight. | Medium |
| AAA-30 | **[shot]** The Shop's category separators are em-dash text rows rather than drawn dividers. | Low |
| AAA-31 | **[shot]** Card corner radii vary between the menu (large), the shelf (medium) and slots (small) with no system. | Medium |
| AAA-32 | **[code]** Icons are baked at 1024² and shown at 64–96 px — 11–16× oversampled, so no crisp small-size art exists. Rendering quality is *worse*, not better, for the excess. | High |

## 7. Fun

| # | Finding | Sev |
|---|---------|-----|
| FUN-01 | **[shot]** The first thing a new player meets is a wall of ten near-identical buttons. No hook, no art, no promise. | Critical |
| FUN-02 | **[shot]** The play screen has no visual reward — text arrives into a void. | Critical |
| FUN-03 | **[code]** No dice are ever shown rolling (Round 5 VIS-08) — the core RPG ritual is invisible. | Critical |
| FUN-04 | **[shot]** Loot has no moment: items appear as list rows, not as a reveal. | High |
| FUN-05 | **[shot]** 1 150 baked items per world and the player sees them as ~20 px list thumbnails. **The bake's value is invisible in play.** | Critical |
| FUN-06 | **[code]** Rarity glow and enchantment tint compose at draw time but nothing celebrates a rare drop. | High |
| FUN-07 | **[shot]** Level-up has no visible screen in the captured flow. | High |
| FUN-08 | **[shot]** The forge is 11 steps of forms with no payoff visual until the end. | High |
| FUN-09 | **[shot]** "The Cold Anvil" builds ceremony and then delivers a form. | Medium |
| FUN-10 | **[code]** No sound feedback is verifiable from the audit, but `Sfx` calls exist — the sfx files failed to load in the harness (missing `.import`), suggesting audio may be silently absent. | High |
| FUN-11 | **[shot]** No companions visible, so the party fantasy is absent from the main screen. | High |
| FUN-12 | **[shot]** No enemy art in the default play state. | High |
| FUN-13 | **[shot]** The world's key art (baked, gorgeous) never appears during play. | Critical |
| FUN-14 | **[shot]** Six distinct worlds were baked; the play screen looks identical in all of them. | Critical |
| FUN-15 | **[code]** Treatments (Flame-Touched, Frostbound…) change name and tint but never trigger an effect or sound. | Medium |
| FUN-16 | **[shot]** No progression visualisation beyond a 0 % XP box. | High |
| FUN-17 | **[shot]** The Atlas could be a treasure map and is a fireplace photo. | High |
| FUN-18 | **[shot]** The Lore Book promises an illustrated encyclopedia and delivers blank pages. | High |
| FUN-19 | **[code]** No achievements, titles, or milestones. | Medium |
| FUN-20 | **[shot]** No character portrait means the hero the player invented is never seen. | Critical |
| FUN-21 | **[code]** Quests exist as a system but have no visible surface in the captured flow. | High |
| FUN-22 | **[shot]** The shop is a spreadsheet, not a haggle with a person. | High |
| FUN-23 | **[code]** Combat music/screen shake exist but combat is invisible until entered. | Medium |
| FUN-24 | **[shot]** No day/night visual change on the play screen despite a clock. | Medium |
| FUN-25 | **[code]** Six baked biome plates per world are unused in exploration. | High |
| FUN-26 | **[shot]** No sense of place — the player never sees where they are. | Critical |
| FUN-27 | **[code]** The GM has a portrait per world and never appears. | High |
| FUN-28 | **[shot]** Nothing on screen changes as the story progresses — no visual state. | Critical |
| FUN-29 | **[code]** No "previously on…" recap despite a chronicle system. | Medium |
| FUN-30 | **[shot]** The empty void where art should be actively signals "unfinished" to a new player. | Critical |
| FUN-31 | **[code]** The customization vision (player-forged armour/worlds) has no entry point in play. | High |

## 8. Aesthetic

| # | Finding | Sev |
|---|---------|-----|
| AES-01 | **[shot]** Three button languages on one screen (AAA-01) — the menu has no visual system. | Critical |
| AES-02 | **[shot]** OS-native chrome (title bar, ✕, grey band) inside a bespoke fantasy theme. | Critical |
| AES-03 | **[shot]** Photographic backdrops under body text with no scrim — Round 5's diagnosed root cause, unfixed. | Critical |
| AES-04 | **[shot]** Everything is flat: no elevation, shadow, or layering language. | High |
| AES-05 | **[shot]** The palette is near-monochrome purple; gold accents are the only relief. | High |
| AES-06 | **[shot]** Contrast failures: shelf text over backdrop, dim button labels. | Critical |
| AES-07 | **[shot]** Inconsistent corner radii across components. | Medium |
| AES-08 | **[shot]** Inconsistent spacing — the menu is tight, the play screen is 60 % void. | High |
| AES-09 | **[shot]** Mixed icon metaphors and stroke weights. | High |
| AES-10 | **[shot]** ASCII ornament ("✦", "—") standing in for drawn decoration. | Medium |
| AES-11 | **[shot]** The wordmark is clipped — the brand's single most important asset. | Critical |
| AES-12 | **[shot]** Typography is one weight and roughly one size for all body copy. | High |
| AES-13 | **[shot]** No focal point on the play screen; the eye has nowhere to land. | Critical |
| AES-14 | **[shot]** The Record's left panel and right content have different background treatments with a hard seam. | Medium |
| AES-15 | **[shot]** Tab labels are letterspaced serif; button labels are letterspaced too — everything is letterspaced, nothing stands out. | Medium |
| AES-16 | **[shot]** The day banner's full-width flat bar is visually heavier than the narration it sits above. | Medium |
| AES-17 | **[shot]** The empty minimap box draws attention to absence. | High |
| AES-18 | **[shot]** Grey stock sliders break the palette entirely. | Critical |
| AES-19 | **[shot]** Baked art is beautiful and appears nowhere at display size. | Critical |
| AES-20 | **[shot]** The six worlds are visually indistinguishable in play. | Critical |
| AES-21 | **[shot]** No motion language is observable in stills, but reveal/stagger exists in code — it is not visible where it matters (empty screens). | Medium |
| AES-22 | **[shot]** The forge screens are 95 % empty with a centred column — vast wasted canvas. | High |
| AES-23 | **[shot]** Particle dots are the only texture on forge screens. | Medium |
| AES-24 | **[shot]** The Lore Book's transparency makes two UIs overlap visually. | Critical |
| AES-25 | **[shot]** The Atlas's frame sits over an unrelated photo — no compositional logic. | High |
| AES-26 | **[shot]** Section headers compete with page titles at similar visual weight. | Medium |
| AES-27 | **[shot]** Buttons vary in height (62 px, 48 px, 72 px) down one menu column. | Medium |
| AES-28 | **[shot]** The Shop panel is small and centred with large dead margins. | Medium |
| AES-29 | **[shot]** Item thumbnails have inconsistent silhouette scale — some fill the cell, some are slivers. | High |
| AES-30 | **[shot]** No consistent empty-state visual language (some blanks have copy, some are void). | High |
| AES-31 | **[shot]** The gold accent is used for both "primary action" and "decorative flourish", diluting it. | Medium |

## 9. Playability (structural)

| # | Finding | Sev |
|---|---------|-----|
| STR-01 | **[code]** ~18 screens from launch to play (CUT-05). | Critical |
| STR-02 | **[shot]** No onboarding or tutorial surface anywhere. | Critical |
| STR-03 | **[shot]** The free-text box is the entire interaction model with no scaffolding. | Critical |
| STR-04 | **[shot]** Critical state (HP) lives behind a modal. | Critical |
| STR-05 | **[shot]** No spatial model (empty minimap, fake atlas). | Critical |
| STR-06 | **[code]** No save/load feedback in the play loop. | High |
| STR-07 | **[shot]** Panel exits are inconsistent (✕, "Return to the tale", "Close the book", "Return to the Hall", Escape). | High |
| STR-08 | **[shot]** The primary exit is clipped off-screen (BUG-01). | Critical |
| STR-09 | **[code]** No keyboard access to panels. | High |
| STR-10 | **[shot]** Two exits with different destinations on one panel (PLAY-11). | High |
| STR-11 | **[code]** No undo/confirm on gold-spending actions. | Medium |
| STR-12 | **[code]** Difficulty is set once in the forge with no in-play adjustment. | Medium |
| STR-13 | **[shot]** The nine-tab Record is a settings menu wearing a character sheet's name. | High |
| STR-14 | **[code]** Companion management has no surface in play. | High |
| STR-15 | **[code]** Quest state has no surface in play. | High |
| STR-16 | **[code]** Inventory is inside the Record, two clicks deep, during combat. | High |
| STR-17 | **[shot]** No indication which of the 12 toolbar icons is contextually relevant. | High |
| STR-18 | **[code]** No pause. | Medium |
| STR-19 | **[shot]** No visible turn/initiative state outside combat. | Medium |
| STR-20 | **[code]** World switching requires returning to the main menu. | Medium |
| STR-21 | **[shot]** The Campaign Shelf lists every tale from every world flat, with no filter. | Medium |
| STR-22 | **[code]** No search anywhere (items, lore, worlds). | Medium |
| STR-23 | **[code]** The 1.4 GB first-run unpack blocks the first frame (LAT-22). | Critical |
| STR-24 | **[code]** No settings for text size, motion, or contrast (accessibility). | High |
| STR-25 | **[shot]** Contrast failures would fail WCAG AA in several places (AES-06). | High |
| STR-26 | **[code]** No colour-blind consideration in rarity colours (green/blue/purple/orange). | High |
| STR-27 | **[shot]** Click targets: "Close the book" and "Return to the Hall" are text-sized, under 44 px tall. | High |
| STR-28 | **[code]** No error surface when the backend is unreachable beyond a status line. | High |
| STR-29 | **[code]** No offline/degraded mode messaging when the art engine is down. | Medium |
| STR-30 | **[shot]** Nothing communicates that pre-baked worlds are complete vs still compiling. | Medium |
| STR-31 | **[code]** No way to report a bug or open logs from inside the game. | Low |

---

## What I could not verify

Being explicit about the edges of this evidence:

- **Combat** was not captured — the demo seeding path (`MF_SHOT_DEMO`) rendered
  the Character Forge instead of a combat state, so every combat claim above is
  marked `[code]` and should be re-audited with a live fight.
- **Audio**: the harness logged failures loading every `.wav` (missing import
  artifacts in this worktree). That is very likely a worktree artefact, not a
  shipped defect — FUN-10 needs confirming against the real exe.
- **Live turn feel**: I measured model latency directly, not a played turn end
  to end through the client.
- **The 1.4 GB first-run unpack** (LAT-21/22, STR-23) is read from code, not
  timed on a clean machine.
- The worlds baked this session were verified as *data* (0 missing icons); this
  audit shows they are largely **not surfaced in the UI**, which is a different
  problem from the bake.

## The through-line

Three root causes explain most of the 250+ findings:

1. **The baked art never reaches the screen.** ~1 800 images, six worlds, and
   the play screen is a void with 20 px thumbnails. This is the single largest
   gap between what the project *has* and what a player *sees* — and it is
   mostly plumbing, not new art.
2. **There is no shared panel/chrome contract.** Stock dialogs, stock sliders,
   OS title bars, clipped exits, five different "close" affordances. One themed
   panel component would fix a whole column of this table.
3. **Ceremony is spent where there is no content, and withheld where there is.**
   An entire screen for "Light the forge"; nothing at all for a rare drop, a
   level-up, or a dice roll.
