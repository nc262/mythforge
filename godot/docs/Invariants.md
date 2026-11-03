# Invariants

Rules that must hold across the WHOLE repo, each with the check that enforces it.

**Why this file exists.** The codebase carries **147** references to past incidents
(`RCA`, `R6-…`, `PY-…`, `BLANK-…`) and, before this file, **21** structural checks.
The knowledge was written down every time and enforced almost never — so the same
root cause kept reappearing somewhere new, five times in one day:

- `env_resolved` scoped env art keys by world family. `race-`, `item-`, `beast-`
  and `map-` did not, so one world was served another's paintings.
- `item_tex` asked the compiled package before the cache. Five other sites spelled
  that fallback by hand in three different ways, two of them wrong in opposite
  directions.
- `roster_art`'s own comment calls itself *"the fourth appearance of this session's
  root cause"*. The fifth was found the same afternoon.
- The character screen's re-strike reported progress. The forge's copy did not.
- `item_flavor()` already trimmed a style anchor to its medium clause. The world
  backdrop prompt did not, and painted a signboard instead of a fjord.

Every one of those was **already documented at the site of the fix**, and a comment
is only discoverable if you are already reading that file.

## THE RULE THIS FILE IMPOSES — READ THIS ONE FIRST

**A check on your MECHANISM is not a check on the BUG.** This is the failure that
produced two wrong "fixed" commits in one day, both of them mutation-tested.

PY-14 was diagnosed from source as "self-drawn controls never repaint on a skin
change". A fix was written, a check asserted the fix was called, the check went
red under mutation — every step rigorous, all of it applied to the wrong cause.
The real one (a compiled world overlays its primary accent and leaves the
secondary behind) was found only when someone finally took a SCREENSHOT. PY-26
went the same way: the check proved the prompt describes rather than forbids,
which is true and irrelevant, because the screen draws the BAKED pack chart and
never reads the prompt at all.

So, before a commit says a row is fixed:

1. **Measure the SYMPTOM, not the mechanism.** "Turns went 6.1 s to 3.5 s" and
   "the button border is teal, not magenta" are symptoms. "`repaint_on_skin` is
   called" is a mechanism, and a green mechanism check next to a live bug is
   worse than no check, because it reads as proof.
2. **Confirm which PATH the screen actually reads.** Package or cache? Baked or
   generated? A prompt fix changes nothing for a world that ships a baked image.
3. **If it renders, look at it.** `tests/screen_shots.tscn` exists for this and
   has already overturned two conclusions that source-reading called certain.
4. **If the symptom was not measured, do not title the commit "fixed".** Say what
   was verified and what was not. "Not verified visually" in a commit BODY under
   a title saying FIXED is still overstating it.

## THE RULE THIS FILE IMPOSES

**An RCA comment without a check is unfinished work.** When you write "this cost us
X", you write the assertion in the same commit, and you add the row here. A row
with no check in the Check column belongs in *Not yet enforced* below, where it is
visibly a gap rather than invisibly a comment.

## Enforced

| Invariant | Check | What it cost |
|---|---|---|
| An art key whose PROMPT carries `world_flavor()` must carry the world family in the KEY. Build keys with `Art.race_key`/`item_key`/`beast_key`/`map_key`/`class_key`/`bg_key` — never by hand | `self_check` — *"art key '%s' is reused across worlds"* | A Tiefling painted in Embervale served back in Neonspire. The key was hand-spelled in six places; five drifted |
| A world's key art is asked for with `Art.world_tex()` — the compiled package FIRST, then the cache. Never spell that fallback inline | `self_check` — *"%s spells the key-art fallback by hand"* | Fifth appearance of one root cause. `world_forge` asked the cache only, `adventure_forge` the package only |
| Every world in `worlds.json` must be in `WorldSkin.BUILTIN` | `self_check` — *"shipped world '%s' is not in WorldSkin.BUILTIN"* | saltmarsh fell to the `fantasy` default and wore Embervale's entire art set |
| Generated art is PERMANENT. Nothing deletes a painting to reclaim space | `self_check` — *"_evict is back"* | Nothing regenerates from a sidecar, so eviction was deletion. A banked hero's face is unrecoverable — its source scratch key is overwritten |
| A derived image prompt stays inside SDXL's first 77-token chunk | `self_check` — *"prompt is ~%d tokens — past chunk 0"* | Past chunk 0 text never reaches the POOLED style vector, so worlds drift apart by different amounts |
| A style anchor must not lead with a concrete object noun, and is trimmed to its medium clause for landscapes | `self_check` (token budget) + `Art.world_prompt` comment | Three renders of fimbulreach: `rune-carved wood` got painted as a signboard, twice, before the anchor was trimmed |
| Guard on IN FLIGHT, not on FINISHED, before announcing work | `self_check` — *"_auto_portrait must skip a portrait already in flight"* | "Painting Cael Mercer…" printed twice; `has_art` is only true ~20 s later |
| A long operation must say it is working AND restore itself on failure | `self_check` — *"the re-strike must say it is working"*, *"func _on_quench_progress"* | 25 s of silence reads as failure. A failed paint emits no `art_ready`, so the naive fix hangs the button for the session |
| The narrator warms before the image engine is started | `self_check` — *"the image engine is started BEFORE the narrator warms"* | The engine's first image takes 6.6 GB it never returns |
| Cast art keys (`npc-`, `foe-`) carry the world too — `Art.npc_key()` / `foe_key()`, never by hand | `self_check` — *"builds a cast art key by hand"* | PY-28. Filed as nine sites; it was **fourteen**, and following the rule turned up a SIXTH leaking prefix (`foe-`, whose prompt carries `subject_style("char")`) |
| `--vae-tiling` on every path that LAUNCHES sd-server | `verify.ps1` — *"launches sd-server without --vae-tiling"* | 36.2 s of a 50.4 s image, for a pixel-identical result at the same seed |
| Never paint while the narrator talks — `Art.hold` set around the stream and released on every exit | `self_check` — *"nothing holds the art queue while the narrator streams"* | 3.5 s to 6.1 s per turn. VRAM peaked at 15310/16384, so nothing was evicted: they contend for shaders |
| Godot's RegEx is PCRE2 — a backslash-u escape does not exist there | `self_check` — *"uses a backslash-u escape in a RegEx"* | A pattern compiles clean and then silently matches nothing |
| **Never `call_deferred()` a lambda that captures nodes.** Defer a METHOD and pass the nodes as arguments, so the call site can check them | `pl5_probe` in the gate — dresses five dialogs and frees each in the same frame | PL-5. Nine wrong diagnoses over a year. A deferred lambda is bound to no object, so Godot cannot cancel it when the node dies |
| The Adventure Forge asks for the WORLD before the hero, and publishes it before spawning the child forge | `self_check` — *"the Adventure Forge asks for the hero before the world"* | PY-27. Kit, body and portrait were committed for a world nobody had chosen — the upstream half of PY-21, PY-22 and PY-23 |
| Card prose is cut with `Ui.trim()`, never `.left(N)` — at a word, with an ellipsis | `self_check` — *"truncates card prose with .left()"* | PY-11. "quiet adventu", "stolen blueprt", "answer them i" — the best writing in the game, amputated on four screens |
| Every dialog is dressed with `Ui.dress_dialog()`, and that assigns `theme` — a Window does not inherit one | `self_check` — *"is a dialog that never gets dressed"*, *"dress_dialog does not give the dialog the theme"* | PY-12. Three of five dialogs were never dressed, and the dressed ones still had engine-grey innards |
| A control that paints itself in `_draw()` calls `Ui.repaint_on_skin(self)` — a theme change does not invalidate it | `self_check` — *"paints itself but never repaints on a skin change"* | PY-14. 13 of 14 self-drawn controls never asked: themed widgets went magenta in Neon Spire while the toolbar, sliders and HP bar stayed gold |
| A trailing GM instruction that does NOT move the player carries `GameState.here_pin()`; one that does must not | `self_check` — *"is a stay-put instruction with no location pin"* | PY-7. The GM answered a merchant exchange and an Insight roll by inventing a new place. The pin existed for rest paths only |
| A world family may REPLACE era-locked item forms; universal shapes are shared | `self_check` — *"a cyber world is still offered"* | PY-23. Neon Spire shipped halberds, mail coifs and kite shields and offered no pistol, rifle or deck at all |
| An image prompt DESCRIBES what should be there; it never forbids. And the chart's ground is per family | `self_check` — *"the chart prompt still says"*, *"a megacity and a green valley get the same chart ground"* | PY-26. Every world got "open country", so a vertical megacity was a river valley — and the forbidding prompt produced "a painted city and two misspelled cartouches" |
| A compiled world overlays its accent PAIR, not just the primary | `self_check` — *"the secondary accent is not derived from the world's own"* | PY-14. Neon Spire ran an orange primary from its pack beside a magenta secondary from the palette — two unrelated hues, neither the authored cyan. Found by screenshot, not source |
| A SHIPPED world keeps its hand-authored accent; only a forged world takes its pack's | `self_check` — *"authored accent was overruled by its generated pack"* | Brasshaven, "brass, soot and secrets", rendered pale blue; Neon Spire rendered orange over an authored cyan. Two of four shipped worlds, found by screenshot |
| The chart prompt lives in `Art.chart_prompt()` — the bake and the runtime share it | `self_check` — *"the bake does not use Art.chart_prompt"* | PY-26 fixed the runtime copy; the compiler kept a hand-copy it called "the runtime twin", so every COMPILED world — which is all of them — still painted wilderness |
| Models are matched by NAME, not position | `self_check` + `verify.ps1` | Picking the wrong one fails silently rather than loudly |
| Every family in `WorldSkin.FAMILIES` has a row in `WorldTerrain.GROUND` | `self_check` — *"WorldTerrain.GROUND has no ground for the '%s' family"* | Caught on the check's FIRST run: the table had the six shipped families and `FAMILIES` has eight. A forged `space` or `horror` world would have drawn fantasy country. `Art.CHART_GROUND` already had all eight |
| An authored pin must SCORE on the ground beneath it, not merely avoid drowning | `self_check` — *"scores %.2f on %s - possible ground, but not ground of its kind"* | Asserting `suits` alone is asserting "not underwater", which seed 0 satisfies for every pin — so the seed search terminated immediately and Hearthwood Market, a shop, sat on a glacier |
| A world's terrain is deterministic — two calls give the same seed and sea level | `self_check` — *"terrain is not deterministic - two calls gave seeds %d and %d"* | The Atlas, the minimap and the compiler each ask separately. If two answers differ, the pins and the paper disagree, which is the defect this whole change exists to end |
| A place with no authored x/y is placed by SCORING the ground, never by `hash(name)` alone | `self_check` — *"was SEARCHED for and still only scores %.2f on %s"* | Saltmarsh is 46 % sea and hash-placed all three of its places, so each had ~2-in-5 odds of standing in open water — the same way every playthrough, because a hash never changes. Its quay now sits on the coast at 0.94 |
| No two places may occupy the same terrain cell | `self_check` — *"stand on the same cell %s - the placement tie-break has stopped spreading them"* | The tie-break is hashed per (name, cell) rather than a spacing pass, because spacing makes the answer depend on what else is placed and kills memoisation — and `mini_map._draw` calls `places()` every frame. This assertion is what the spacing pass would have bought |
| A place the tale NAMES is on the chart, unvisited — knowing of somewhere is not having been there | `self_check` — *"a place the tale NAMED is not on the chart"* | Fog was two-state and the rule said so: "hides what you haven't walked". So the GM could say "word reaches you of the Sunken Fort" and the Atlas would deny it existed — the map calling the narrator a liar, in a game that is nothing but a narrator |
| Visiting implies having heard of. Never demote a place the player has stood in | `self_check` — *"an OLD SAVE with `seen` and no `heard` demoted a visited place back to a rumour"* | Every save written before `heard` existed carries `seen` and nothing else. Mutation-tested: dropping the implication turns a walked place back into a rumour |
| A SETTLED place is never fogged; an unsettled one is, and its fog scouts the exits | `self_check` — *"a town you have just walked into is not a dungeon"*, *"standing at the way in does not scout what it opens onto"* | Fogging a friendly town means walking it to reveal streets — busywork wearing exploration's clothes, and no mainstream RPG does it. Reveal only where you stand and exploring is a random walk rather than a decision |
| A player can step inside a town from the IN-GAME Atlas, and the window shows the town | `ui_playthrough` — *"clicking the place you stand in is wired to nothing"*, *"the window for %s is EMPTY"* | The Atlas is a character-screen tab that wired travel and nothing else, so the town tier — plans, trades, GM sites, trouble clocks, a whole session of work — was unreachable in the game; the only function that could open it had no player caller since 45af4d6. Behind that, `_open_place_map` never parented its view, so the window it opened was empty. Every harness built the town map directly and could see neither. Mutation-tested: each fix removed on its own turns it red |
| A place is drawn at the scale its kind means: settlement = a town of quarters, tavern/shop/home = ONE building of rooms, the rest = a site to explore | `town_probe` — *"a %s is drawn as a %s"*, *"one building, and it sells %d trades of its own"*, *"a room you cannot walk to"*; `self_check` — *"BUILDING_KINDS and WorldSkin.ROOM_KINDS disagree"* | MEASURED 2026-09-17: of 29 shipped places exactly ONE was a settlement, and every tavern, shop and cottage was generated as a village — The Ember & Oak had four quarters, a wall, ploughland and its own Tavern inside it. The Worldsmith could not make a settlement at all (`LOC_KINDS` had no such kind), so forged worlds had no towns either. Mutation-tested |
| Every polygon the town sheet draws is one the renderer can draw: no shape crosses itself | `town_probe` — *"polygon(s) cross themselves"* | `draw_colored_polygon` ear-clips on the server and fails SILENTLY in the shipped build (headless it prints "triangulation failed"). Found when the retagged towns were generated for the first time: 2 buildings in each of three towns and one plaza were bow-ties, drawing nothing. `TownPlan.simple` replaces a folded offset with its convex hull, and the plaza filter uses the SAME repaired ring, or houses stand in the market square. Mutation-tested |
| A gate opens onto a street the square can reach: no gate into a building, and never more gates than high streets | `town_probe` — *"open straight onto a building"*, *"a gate the square cannot reach"* | The mouth test asked whether a point 3 units in was inside a WARD while the gate test asked whether a building was there; they disagreed and Hearthwood Market put a gate in a kitchen. Both conditions are required: outside the wards (the artery router treats ward interiors as solid) AND clear of buildings at the same depths the test probes. Dropping the ward half took arteries from 3/2/1/2/2/1 to 1/1/0/0/0/0. Mutation-tested |
| What a settlement can hold is gated by how big it is, and its size is what the world declared, not a dice roll | `site_probe` — *"a place chartered as a city came out tier %d"*, *"was allowed in a %s"* | A tale could charter a capital and the generator rolled it a hamlet, and a village could hold a Guildhall. `[[place ... size=]]` is kept when the engine knows the word; `add_site` refuses a trade above the tier and names the size it would take. A BUILDING is exempt: a fence in a tavern's back room is right. Mutation-tested |
| The player can ask a town for a place that is not on its map, and the answer is the GM's to give and the engine's to validate | `site_probe` — *"a legal answer was refused"*, *"the asked-after place is not on the town map"*, *"the same place was added to the town twice"*; `ui_playthrough` — *"has no way to ask after a place"*, *"asking after a place answered nothing"* | A generated map can only ever show what was generated, and the first thing a player asks a town for is the thing that is not drawn. Propose-and-validate: `Chronicle.ask_after` gets a schema-constrained decision, `GameState.answer_ask` checks kind, ward, name and size, and the refusal IS the answer the player reads. Mutation-tested |
| Every settlement size actually generates, a city included | `town_probe` — *"chartered as a %s and generated as a %s"*, and a city is probed in every world | A city has 11 quarters against a role list of 9, and the quay swap walked past the end of it: "Out of bounds get index '10'", which abandoned the whole ward pass (`ward_role` empty, `_plan_trades` dead) WITHOUT failing the gate — it printed as an engine complaint in a green run. No shipped place was ever a city, so the first one the game built was the first one chartered `size=city`. Mutation-tested |
| An ask the narrator answers badly is not an answer: unknown keys, a yes with no kind, or a sentence cut at the schema's ceiling never reach the player as truth | `site_probe` — *"an answer carrying keys nobody asked for was accepted"*, *"an answer with no kind was accepted"*, *"a cut-off answer reached the player as a stump"* | A schema call runs with NO sampler chain (LocalLLM-Tuning.md), so a bad turn returns rubble rather than a wrong answer: measured one in five, an object with invented keys and a paragraph of noise, plus a 180 s run to the deadline (now capped at 25 s for a call somebody is waiting on). Five asks with no world context gave five yeses including a spaceport in a fantasy valley; with the world and two refusal examples in the prompt, the spaceport is refused and the size gate answers the fence in-world. Mutation-tested |
| The town map and the story are one town: the narrator is told the town's quarters, trades, sites and trouble; it is taught [[site]]/[[trouble]]/[[clock]]; clicking inside a town asks for a turn; the tags in that turn change the map and the next context | `ui_playthrough` — *"the narrator is not told the quarters of %s"*, *"the GM is never taught %s"*, *"walking to %s asked the narrator for nothing"*, *"the GM's [[site]] did not reach the town map"*; `self_check` — *"the [[site]] kinds the GM is taught are not GameState.SITE_KINDS"* | Measured 2026-09-17: no prompt read `wards`/`trades`/`sites`/trouble, the three tags had handlers but no line in PROTOCOL, and a click inside a town posted a local line and no turn — each half worked alone, the loop between them did not exist. Mutation-tested: each of the three fixes removed on its own turns it red |
| A town whose trouble has ended can be troubled again — resolved erases it, came-to-a-head no longer blocks | `site_probe` — *"a trouble that came to a head still blocks the next one"*, *"a trouble pushed back to nothing is still on the record"* | `set_trouble` refused on any record and nothing removed one, so every town got exactly one trouble for the life of the save. `site_probe` printed the refusal and asserted nothing, and was not in the gate; both changed 2026-09-17. Mutation-tested |
| The player learns of a trouble by its reach: town on arrival, region anywhere in it, secret only by [[uncover]] or when it comes to a head; no screen shows one they do not know | `site_probe` — *"a SECRET trouble was announced"*, *"arriving in a troubled town did not announce the trouble"*, *"a region trouble was not heard"*; `self_check` — *"shows GameState.trouble_at - that includes SECRET troubles"*, *"the GM is never taught trouble reach=%s"* | The Atlas card and the town margin printed every trouble to anyone who had visited, so a conspiracy was spoiled before a single clue, and "Trouble is brewing in X" was said the moment the GM thought of one. A pre-reach save's troubles stay known, because they were already on the map. Mutation-tested, each branch alone |
| A trouble the player knows of is a quest the engine runs: filed when heard, tied to a real thread or a side matter, carrying its leads, failed when it comes to a head, never dropped or re-statused by the model's quest rewrite | `site_probe` — *"did not file it as an active side quest"*, *"did not fail its quest"*, *"a trouble naming a quest that does not exist was tied to something"*, *"the model's quest rewrite dropped or re-statused a trouble quest"*; `ui_playthrough` — *"is not an active quest on the log"* | The quest log is rewritten wholesale by a model pass every few turns; an engine quest without the `trouble` guard would be dropped or marked done while its clock still ran. Mutation-tested |
| Clues, rolls and days move a trouble by rule: the third clue exposes a secret and no earlier one names it; a trouble=1 roll moves the clock by its result; a day creeps what nobody worked, even where the party stands | `site_probe` — *"or its quest filed, before the third clue"*, *"gave the secret away"*, *"left the clock at %d, not 1"*, *"worked today crept overnight"*, *"standing in a troubled town without working it still protects it"*; `ui_playthrough` — *"did not arm a roll against the trouble"*, *"the GM's [[clue]] did not reach the trouble"* | Before: standing in a town froze its clock, so sleeping there saved it. Mutation-tested |
| A trouble that comes to a head changes the world the engine owns: road, trade, prices or law | `site_probe` — *"fallout=road turned no road into %s dangerous"*, *"fallout=law left the town's quarters as lawful"*; `ui_playthrough` — *"the shops of %s opened although its trouble shut them"*, *"fallout=prices did not raise the counter's prices"* | The first road check looped over `roads()` and passed with the fallout deleted: the shipped worlds have NO authored roads (measured, saltmarsh and embervale). Fallout now names the ways to the three nearest places; measured travel peril 0.20 -> 0.60. Mutation-tested |
| In real play a trouble is fed by reading the turn, not by the narrator's tags: a lead is recorded, effort counts the day as worked, and the next roll there counts against the clock — exactly once | `site_probe` — *"a lead read from the turn was not recorded"*, *"did not mark exactly the next roll"*, *"left an earlier turn's roll marked against it"*; `ui_playthrough` — *"a plain roll on a turn spent working the trouble did not move its clock"*; `self_check` — *"Chronicle.record no longer reads the turn for the trouble"* | MEASURED with the real narrator (tests/town_gm_probe, secret trouble, 4 investigating turns): 0 [[clue]], 0 trouble=1, while the prose did plant traces. With the read: 4 leads, 0 leaks, secret exposed on the third, 0.5-0.9 s per read. Mutation-tested |
| On the world chart, no place name is lettered across a region banner | `town_probe` — *"is lettered across the region banner"* | Banners were drawn by a pass the label solver never saw. Saltmarsh's "Gallows Quay" (place) sat across "GALLOWS QUAY" (region, named after its chief town) and read as a typo. Mutation-tested: removing the reservation turns it red on Saltmarsh AND on Fimbulreach, whose White Fjord crossed THE FJORDLANDS and had not been noticed |
| A town gate opens onto a STREET, never a building; every town has exactly one market square | `town_probe` — *"open straight onto a building"*, *"market squares"* | Gates were placed by bearing to a neighbour, so they landed wherever the wall crossed that angle — mostly the back of a house: 22 of 29 opened onto a building. And a quay swap written to put the Quay by the water traded it into the square's ward when a town had more roles than wards, deleting The Leaning Lantern's centre. Nothing failed for either; the second surfaced only because its high streets had nothing to route to |
| A ward id is STABLE: the same town rebuilds the same quarters in the same order | `town_probe` — *"ward ids are not stable across rebuilds"* | A `[[site]]` tag stores a ward INDEX in the save file. If the order moves, a fence the GM put in ward 3 changes quarters between sessions, and nothing would say so |
| No two wards of one town share a name, and no ward shares a name with a TRADE | `town_probe` — *"are both called"*; `self_check` — *"calls both a WARD and a TRADE"* | A town you cannot give directions in. Four families collided (space on Galley, steam on Guildhall, pirate on Chandlery AND Tavern, norse on Mead-Hall) and only `_add`'s de-duplicator kept them apart, as "The Chandlery (2)" |
| Every family fills every ward and trade socket, in its own words, and no two families fill them identically | `self_check` — *"has no word for the"*, *"name their wards IDENTICALLY"* | The generator asks `WorldSkin` for what this world calls its square. It used to string-match the family's prose on "cyber" or "steam", so eight families gave two vocabularies: a steampunk town got a NOODLE BAR, and a fantasy village and a pirate port drew byte-identical ward names |
| Every kind the GM may invent is one the map can draw | `self_check` — *"SITE_MARK has no mark for it"* | `SITE_KINDS` is a closed enum precisely so this can hold — the model picks a kind, it never names one. Leave a kind out of the mark table and that site renders as a bare dot |
| A bigger settlement never offers fewer trades than a smaller one | `self_check` — *"offers no more trades than tier"* | Size gating is the one economy rule every published system implements and none leaves to taste. A gate that does not gate is worse than none, because it looks like a rule |
| Every ward of every town is BUILT ON — no quarter comes out as bare ground, and none falls under 0.15 built-over-ward | `town_probe` — *"ward %d: area %.0f, NOTHING BUILT"*, *"fill %.2f below %.2f"* | `TownPlan.inset` was half-plane clipping, which is only an inset for a CONVEX polygon. Wards inherit one to four reflex vertices from `bounds` (a lobed ring cut back at the sea), and at a reflex vertex the edge’s infinite line runs through the body: a 0.6-unit inset took wards of 550/509/393/277 down to 103/322/**0**/13. Whole districts rendered as meadow and nothing failed. The recursion cap was the first suspect and was innocent — counters read nocut=0 onecut=0 cap=0 across all fourteen towns, which is the only reason the real cause was found |
| Every room in a local map is reachable from the way in | `self_check` — *"%d of %d rooms are cut off from the entrance"* | A node with no edge is a room the player can see and never enter, which reads as a broken map |
| Every family has its own paper and ink in `WorldTerrain.PAPER`, and the ink reads on it at 4.5:1 | `self_check` — *"draws %s ink on %s paper - %.1f:1, under the %.1f:1 the rest of this game is held to"* | The chart became ink on parchment, so the per-family table stopped being a terrain ramp and became a STOCK. The one thing that can silently go wrong is a hand-picked pairing nobody can read — pale ink on pale vellum, or dark ink on a dark blueprint. Contrast is checkable where taste is not, and below it the map is unusable. Replaces the old "a city is not green" row, which guarded a shaded-relief renderer that no longer exists |
| Both map tiers letter in `Ui.display` and draw through `MapInk` — one face, one symbol set | `self_check` — *"letters in its own font instead of Ui.display"*, *"draws its own marks instead of MapInk"* | `place_map` carried a second `_draw_mark` with four shapes of its own, which is two answers to "what does a ruin look like". A backlog row also claimed the project had no serif at all — `Ui.serif` had been in `skin.gd` the whole time, invisible to a grep because a `SystemFont` ships no file |
| **Nothing reads terrain out of a painting.** `world_map.gd` may not call `get_pixel`/`get_image`, and must route over `WorldTerrain` | `self_check` — *"the road router is reading terrain out of the painting again"* | Neon Spire's router called 73.2 % of a flat city expensive — night read as mountain, neon as rivers — and found 0.2 % water in a world whose prompt asks for canals. AT-4 forbade this at 13:01; the router landed at 15:04 the same day and undid it |
| `relief` drives what rough ground costs — compare the SAME class across worlds, never means | `self_check` — *"relief has stopped driving cost()"* | The first version of this check compared mean cost across two whole worlds and **survived mutation**: hardcoding the HILL/PEAK constants left it green, because the mean is set by how much water and high country a world has, which a different function decides |
| A trade on a town map carries a PROPER name — `WorldSkin.trade_title`, a sign, an owner or the town, seeded by town + trade, one owner per shop — and the brief says its trade word beside it. Never `"The %s" % trade_name` | `self_check` — *"is called '%s' - a role word"*, *"two trades run by %s"* | AT-17: "The Tavern" lost to a chart tavern's proper name; the narrator also invented "The Smith's Supply". Named: 17/20 probe turns used a map name, 0 invented |
| A calm settled town's turn is read for a NEW trouble (`read_trouble` falls through to `read_new_trouble`), and `apply_new_trouble` refuses a junk read | `self_check` — *"read_trouble no longer falls through"*, *"a read of '%s' became the town's trouble"* | AT-18: 0 [[trouble]] tags in 8 calm turns while the prose set one up in 3; nothing else starts a trouble, so the whole clock system starved |
| A tag example in `Composer.PROTOCOL` that a player question can ANSWER is a placeholder, not content — the narrator tells a concrete one as news | `self_check` — *"the [[trouble]] example is concrete again"* | Press-gangs on the quay in 8 of 16 calm turns, in an inland town. 0 of 8 with a placeholder |
| A Worldsmith object schema is CLOSED (`"additionalProperties":false`), and its copy step sends the schema through `LocalGM.compact_schema` — llguidance otherwise allows extra keys and unbounded whitespace | `self_check` — *"world, location and region objects are closed"*, *"the Worldsmith's copy step sends its schema on one line"*, *"a schema is sent with whitespace pinned at its root"* | PL-13: the forge took 252 s and made no cast and no campaign. The cast call wrote 53 386 chars of whitespace after `"cast"`; the story call invented keys for 82 063 chars. Both ran to the 180 s deadline |
| A forged place's `region` is the name the region list holds (`Worldsmith.place_in_regions`) — GameState matches region names exactly | `self_check` — *"a place's region resolves to the name the region list holds"* | PL-13: "Aquari Coast" beside "The Aquari Coast" — 0/7 places sat in a region, every one on the chart's centre ring |
| `ask_back` strips EITHER label from either answer — the copy step swaps them | `self_check` — *"ask_back strips either label from either answer"* | PL-13 probe: 3/3 swapped; one-line JSON kept the label, so a button read "B: Eternal, maddening servitude." |

## Not yet enforced — these are gaps, not decisions

| Invariant | What it cost | Why there is no check yet |
|---|---|---|
| **Never one model call that both invents and serialises** | Three wrong diagnoses; 95.8 s and a failure vs 1.5 s split in two | A grammar and a sampler chain REPLACE each other in NobodyWho. Hard to assert mechanically; needs a rule about which call sites may pass a schema |
| **Never return silently from a function that was asked to do work** | `request()` returned with no signal when it had no prompt, so half the worlds could never have key art and it looked like it worked | Not mechanically checkable in general; the specific case now pushes a warning |
| **A harness may not report success for work it did not do** | `terrain_probe` printed "OK 6 world(s)" while `WorldTerrain` failed to compile: a parse error in a `class_name` file is silent at the call site, every probe aborted on its first line, and the summary counted what was ASKED FOR. `screen_shots` learned the same lesson about flat frames | Each harness now counts its own completed work, but there is no repo-wide check that a summary line is derived from a measured count rather than an input list |

## Known limits, measured

**A negative prompt is the only thing that removes chrome, and it is not total.**
MEASURED on the chart re-bake, 1024x1024, same checkpoint:

| | frame | legend | text |
|---|---|---|---|
| neonspire (`holo-map`) | — | — | **gone entirely** |
| brasshaven (`chart`) | **gone** | **gone** | title caption remains |

`/v1/images/generations` has no `negative_prompt` field; `/sdapi/v1/txt2img`
does, and `_paint` switches dialect when one is supplied. That removed the
decorative frame and the legend blocks outright — the two things that actually
fight the pins the map draws on top — and left brasshaven a "BRASSHAVEN"
caption. Both `title` and `caption` were already in the negative, so more
synonyms is not the answer: "chart" plus steampunk evidently pulls hard toward an
antique map SHEET. If that caption ever has to go, change the flavour word or
crop, do not write a longer negative.

Superseded, kept because the reasoning still holds for the POSITIVE half:
**Positive description beats forbidding, but does not suppress text.** The chart
prompt used to end "no buildings, no settlements, no text labels"; describing the
ground instead fixed the picture (a megacity renders as a city, verified by
eye) — and the repainted Neon Spire chart STILL carries glowing pseudo-lettering
along a canal. The real route is an endpoint change, not more wording:
`/v1/images/generations` accepts no `negative_prompt` field at all; only
`/sdapi/v1/txt2img` does, and the game already speaks that dialect for img2img
(`art_cache.gd:I2I_PATH`). Read from the sdcpp routes at our pinned commit.

**A prompt fix does not reach a world that ships a BAKED image.** `world_map`
draws `Compiler.chart_art()` — the pack's own `art/chart.png` — and only falls
back to the cache when there is none. That is correct (package before cache, the
rule above) and it means changing a PROMPT changes nothing for a compiled world
until its pack is re-baked. PY-26's city chart was verified in the cache and the
game still drew the baked valley. Check which path a screen actually reads before
believing a prompt fix landed.

## This file is CHECKED against reality

Rows go stale. Three of these did, within an hour of the file being written — they
sat in "Not yet enforced" while their checks were being committed the same
session. That is exactly the "looks like information" failure that got a 107-row
feature matrix deleted from this repo.

So `self_check` parses this file: **every check name quoted in the Enforced table
must actually exist** in `tests/self_check.gd` or `scripts/verify.ps1`. A row that
claims a check it does not have turns the gate red, so adding a row is not free —
the check comes first.

*It cannot verify the reverse:* that a rule under "Not yet enforced" really has no
check. Moving a row up when you write its check is still a human step, and it is
the step that failed within the hour.

## PL-5 — SOLVED 2026-08-24, and how

Nine wrong diagnoses over a year, four more disproven in one day. It was never a
leaked signal connection. It was **the only deferred lambda in the codebase**:
`skin.gd:_cap_panel_content` ended with `apply.call_deferred()`, and `apply`
captured `dlg` and `content` — the index-0/index-1 PAIR every report described.
Free the dialog before the next idle and both captures are dead when Godot
rebinds them.

**Why nine people looked straight at it and saw nothing.** `apply` opens with
`if not is_instance_valid(dlg) or not is_instance_valid(content): return`. That
guard reads as correct and is useless here: Godot validates captures when the
Callable is INVOKED, before any body runs. A guard inside the lambda can never
prevent this error. The fix had to move to the call site, into a method taking
the nodes as ARGUMENTS — arguments are checkable, captures are not.

**What found it, after four theories that could not:** elimination by
measurement, in this order.

1. Count every autoload signal's connections at the start and end of a
   playthrough. **None grew** — so the whole "an unowned lambda stays connected
   and later fires" family is false, not merely unproven.
2. Add the root `Window`, which outlives every scene and is not an autoload.
   **Still none.**
3. Therefore the lambda is invoked by something that is NOT a connection.
   `grep` for deferred lambdas returned exactly one line.
4. Build the scenario on purpose: dress five dialogs, free each in the frame it
   was dressed. **10 errors, 10/10 runs, indices alternating 0,1** — the first
   deterministic reproduction in the bug's life. Zero after the fix.

**The lesson worth more than the fix.** Every earlier attempt, mine included,
proposed a mechanism and then looked for agreement. Twenty-plus clean runs were
read as evidence on both sides of every theory. What worked was ruling mechanisms
OUT with a census that could not lie, until only one candidate remained — and
then making it fail on demand before fixing it.

`pl5_probe` stays in the gate. It exists to fail.

