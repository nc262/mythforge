# Backlog

**The single list of open work.** If something could be worked on, it is here.
Resolved work is not kept — the code is the record of what shipped.

Three neighbours, so nothing has two homes:

- [KnownIssues.md](KnownIssues.md) — limitations that will **not** be fixed, and why.
- [TechnicalDebt.md](TechnicalDebt.md) — deliberate shortcuts, each with its ceiling.
- [Testing.md](Testing.md) — what the harnesses can and cannot prove, including coverage gaps.

Priority **P1** (blocks play) → **P4** (nice to have); effort **S/M/L**.

---

## Play and correctness

The rows below were found by making the gate print engine complaints from
**passing** runs — they had been in every green log for an unknown length of
time, on a stream nothing read.

**PL-5 IS NOT CLOSED — reopened the same day by playing the game.** The fix below is real and the harness number was real, but the harness was the wrong instrument. `click_driver` went 1 -> 0, and a forty-minute played session on the exported build (exe stamped 18:39, fix committed 16:11, so the fix IS in it) produced **eleven** freed-capture errors: six at index **1** and five at index **0**, from two distinct call sites (`gdscript_lambda_callable.cpp:242` and `:110`). So there is at least one more index-0 lambda the harness never reaches, and a whole separate index-1 capture nobody has looked at. The play log holds nothing else at all — those eleven lines are the entire error output of a real session. **The lesson is the one this repo keeps paying for:** a green harness means the paths it walks are clean, not that the game is. The next attempt should drive the FORGE and the merchant from `click_driver` (both were walked by hand here) rather than trusting the existing stations.

**2026-08-24 — a THIRD theory, also disproven, and the ownership rule is not
sufficient.** All fourteen lambdas on `Art.art_ready`/`art_progress` were
classified by whether they reach a member of `self` (bound, auto-disconnected)
or capture only locals (owned by nothing, outlives the scene). Four were
genuinely unowned: `main_menu`'s banner, `world_forge`'s sky, and `game.gd`'s
companion face and hero ring. Their capture layouts predicted the error pattern
exactly — banner captures a single Object, so index **0**; the other three have
a String or Dictionary first and the Object second, so index **1** — which is
the backlog's own "six at index 1 and five at index 0, from two distinct call
sites", and the 2-per-run the gate prints.

**It is still wrong.** Restoring the banner lambda ALONE and running
`ui_playthrough` three times produced **zero** errors. So being unowned is not
sufficient to fire this; something about WHEN the captured node is freed matters
more, and that mechanism is still unknown. The four were converted anyway
(correct on Godot's rules, costs nothing) but that is hygiene.

**Two failed conversions in one day, both looking like evidence.** The morning's
set (`character_forge`) turned out to be self-bound already — `_status.text`
reaches a member — so three things that were never broken were "fixed", and six
green runs were taken as confirmation. Do not accept green runs here: the bug is
intermittent and the harness has produced 5+ clean runs either side of every
theory so far. **Only a mutation that reproduces it counts**, and no theory has
managed one yet.

What is still unmeasured, and is probably the way in: an instrument rather than
a fourth theory. Hook `NOTIFICATION_PREDELETE` on the captured nodes, or dump
`get_connections()` on every autoload signal at each scene transition, and catch
the leak FORMING instead of waiting for it to fire.

**2026-08-21, later — the SECOND call site was not it, and here is the negative
result so nobody spends the afternoon on it again.** `character_forge.gd` held
three `Art.art_ready.connect(func(k): …)` lambdas reaching no member of `self`.
`Art` is an autoload that never dies, so on the stated Godot rule those
connections are owned by nothing and outlive the scene — the same shape as the
`skin.gd` root-window leak, which DID reproduce. This one does not:

  · the gate went red once with the lambdas present (2 errors, index 0 and 1)
  · six `ui_playthrough` runs green after converting all three to methods
  · **restoring one lambda failed to reproduce it** — 2 runs, 0 errors
  · a probe counting `Art.get_signal_connection_list("art_ready")` at the end of
    a playthrough reported **"1 conns, 0 ownerless" WITH and WITHOUT** the
    lambda. Nothing accumulates on that signal by end of run.

So the accumulation theory is not supported by the one instrument that can see
it directly, and green runs prove nothing here — this row has nine wrong
diagnoses on it precisely because six clean runs kept getting promoted to a fix.
The lambdas were converted anyway (correct on ownership semantics, costs
nothing) but that is HYGIENE, not the fix. Whatever produces the pairs is still
unfound.

Worth knowing for the next attempt: commissioning art for all three forge racks
(9 heritages + 12 classes + 8 backgrounds instead of one clicked card) made
`art_ready` fire ~29x more often per forge, and THAT is what turned the gate red
— so the reproduction rate is now much higher than it was. Run the gate several
times rather than once.

**2026-08-21 — a real cause found, and it fits the eleven.** `Ui.dress_dialog`
→ `_cap_panel_content` connected its `apply` lambda to **`dlg.get_tree().root`'s
`size_changed`**. Root is the signal's EMITTER and never dies, and Godot only
tears a connection down when the emitter does — so the connection outlived every
dialog that made it, and the next window resize called `apply` with `dlg` and
`content` already freed. That lambda captures exactly two objects, which is why
the errors come in index-0/index-1 pairs; five-and-six across a session is that
one lambda firing five or six times. The `is_connected(apply)` guard never
caught it because **each call builds a fresh lambda**, so no two are ever the
same Callable — one permanent connection per dialog ever dressed, which is also
why it grows with session length. Fixed by disconnecting on `tree_exited`
(`skin.gd`). The gate caught the original on a doc-only run, and three
`ui_playthrough` runs are clean after.

**Still open, and here is the honest reason.** Three clean runs is weak evidence
against an intermittent failure, and there is no deterministic check. One was
written — count `root.get_signal_connection_list("size_changed")` across three
dressed-and-freed dialogs — and it **counted 0 with the fix and 0 without**, so
it proved nothing and was removed rather than shipped as false coverage. Why the
count comes back empty headless is itself unknown and is the next thing to
learn; until then `verify.ps1`'s regression list is the only watcher, and it only
sees the error when a resize happens to follow a freed dialog. The backlog's own
advice above still stands: drive the FORGE and the merchant from `click_driver`,
and close this on a played session, not a harness.

The original entry, still accurate as far as it goes: PL-5's filed mechanism was wrong — the ninth
mis-reported row in this backlog's history. The row blamed `game.gd`'s
capturing lambdas on `Art.art_ready` / `Chronicle.chronicle_updated`. Every one
of those was ruled out by dumping `get_connections()` on all three autoload
signals and putting a marker in each non-`self` lambda: none of them fires. **A
lambda that captures `self` is bound to `self`, so Godot disconnects it
automatically when the node frees** — the whole premise was backwards. The real
offender was `Skin.ritual_open`'s `lift`, which is deliberately called
**twice** (once on hide, once on `tree_exited`) and frees its own scrim on the
first call. Its `is_instance_valid(scrim)` guard cannot help: GDScript raises
the error when the Callable is *invoked* with a dead capture, before a line of
the body runs. Fixed by holding the scrim in an Array — the idiom `closed` in
that same function already used — so the capture is RefCounted and can never be
"freed". **The check is in the gate, not the harness:** `verify.ps1` now has a
short list of complaints that go RED instead of yellow, because `click_driver`
printed `CLICKDRIVE OK` through every run of this bug and would have kept doing
so. Proved by reverting the fix and watching the gate fail on a passing
harness.

**PL-9 is closed** (2026-08-17), in two halves that needed different fixes. The
correctness half was the await: all three lazy-worker sites now wait for
`worker_started` — `complete_json`'s `_json_chat` and the memory encoder — and
a `-Full` run prints none of the three lines it was filed for. The latency half
was NOT the await, and measuring said so: with the await in and nothing else
changed, `bench_gm` turn 1 was **8.8 s against the 9.0 s filed**. The row's own
note that "the narrator is already warmed at `_setup`" was wrong twice over —
there is no `_setup` in `local_gm.gd` at all, and the narrator's nodes were
built lazily by the first `stream()`, so a ~4.6 GB load sat inside the player's
first sentence. The fix is the one the row eventually proposed:
`LocalGM.warm()` builds the narrator and waits for readiness, and
`_open_the_adventure` holds the curtain over it at *"Waking the storyteller…"*
(0.95). **Measured: 4.5 s of labelled progress on the loading screen, and turn
1 from 9.0 s to 3.6-4.2 s** — in line with turns 2 and 3 rather than three
times them. The seconds did not vanish and the code says so; they became
visible. `bench_gm` warms first now, because the shipped game does, so its old
"turn 1 includes model load" caveat is gone. `self_check` asserts the order
structurally — nothing offline can drive a real model — and both mutations were
watched failing: removing the warm, and moving it after `lift()`.

**PL-10 is closed** (2026-08-17) and it was never this project's bug. Six local
runs had narrowed it to "a constrained sampler on an explicitly-started worker
aborts"; the `researcher` agent then found the mechanism upstream, and it
explains every arm. NobodyWho ran the GBNF grammar **after** the truncation
samplers, so when top-k/top-p left no grammar-valid token, llama.cpp threw a
C++ exception across the FFI boundary and Rust aborted — `Rust cannot catch
foreign exceptions`, 0xC0000409. That is why the unconstrained chain ran clean
for seven minutes, and why the shipped lazy start looked safe: its first config
was *dropped*, so the first `ask()` ran unconstrained and later ones landed in
a context that happened not to collide. `start_worker()` was a confound, not
the cause. Upstream issues #421 and #487, fixed by PR #644, shipped in
**nobodywho-godot-v9.6.0**; this project was pinned to v9.5.0. Bumped the pin
in `fetch_nobodywho.py` and in `installer/clean-room/check-downloads.ps1`,
re-fetched, and the arm that aborted after exactly one `Ask` now reaches `LOCAL
STACK OK` at exit 0. **Do not re-pin below v9.6.0** — the crash returns and it
is silent.

**PL-6 is closed** (2026-08-17) and the row's guess was right: a harness
artefact. Measured rather than assumed — printing every `Window` child of the
play screen at the moment the shop opens named a live, `exclusive`, unfreed
`levelup_window.gd`, left up by the ceremony because the harness never pressed
"Embrace it". A player cannot reach that state twice over: `Mode` refuses
`shop` during `LevelUp`, and an exclusive modal eats the click anyway — the
harness only got there by forcing `Mode.enter("Exploration")` by hand. It now
dismisses the ceremony the way a player must, which deleted that crowbar (the
game restores the mode itself), bought coverage of the ceremony's exit path,
and left two checks behind: that "Embrace it" actually closes the window, and
that no exclusive modal is still up afterwards. Both watched failing first.

**PL-7 is closed** (2026-08-17). The three failed attempts had all been reasoned
from screenshots; the fourth started with an instrument and took twenty minutes.
`click_driver` already opened the counter — it had simply never *touched a ware*,
so it audited the one state where nothing is wrong. Clicking row 1 reproduced the
soft-lock headless on the first run. The measurement: 86 px of new content grew
the dialog from **541 px to 1002 px** against a contents minimum of **627**,
because a `Window` only ever grows to its contents and never shrinks back, and it
grows *downward* from the origin `popup_centered` fixed when it was shorter. That
put "Leave the counter" at **y=875 on an 800 px screen**. Both earlier theories
were half-right and that is why neither moved anything: a re-fit alone still
hangs off a stale origin, and a clamp alone cannot place a 1002 px window on an
800 px screen. `Skin._cap_panel_content` now does both, and runs on
`content.minimum_size_changed` as well as root resize. Two checks were left
behind and both were watched going red first: `click_driver` now measures every
button in **root** coordinates (its old check asked the button's own viewport,
which for a dialog *is* the dialog, so an exit carried off the bottom still read
as on-screen), and it asserts the counter actually closes. It also pins the
headless root to the shipped 1280x800 — headless was reporting a square 1280x1280
guess, so every "does this fit" question had been asked of a screen no player owns.

**IT IS AT ZERO.** Every log on the box was swept on 2026-08-17 — 205 files,
307 matching lines, 30 distinct — and on the same day the four rows that
survived triage were all closed. `verify.ps1` now prints no engine complaint
from any harness: PL-5 fixed at its real cause, PL-7 fixed, PL-8 proved
unfixable from the game and moved to [KnownIssues](KnownIssues.md) #10 with its
three dead bodies recorded, and PL-6 confirmed to be exactly what it was
suspected of being — the harness's own posture. **Three of the four had a wrong
mechanism filed against them**, and every one of those was caught by an
instrument rather than an argument. The historical and deliberate complaints
stay listed below so nobody triages the same thirty lines twice.

*(The table of surviving complaints that used to sit here is empty — see above.)*

**Cleared, do not re-file:**

- `Mode: transition Combat → LevelUp is not declared` (18×), `Mode drift: a fight
  is active while the FSM sat in Exploration` — **fixed** 2026-08-14 (PL-4 and the
  LevelUp declarations). Historical logs still carry them.
- `Invalid access to property or key '_streaming'` (7×), `Assertion failed: forge:
  a forged hero carries its body onto the sheet`, and eleven `PLAYTHROUGH check
  failed: multiclass/spells/equip/shop/features` — all **transient breakage from
  the refactors of 2026-08-14**, red at the time, green now.
- `Assertion failed: art budget: a shipped terrain tile…` — a **mutation test**
  deliberately breaking the code to prove the check fails.
- `art cache is THRASHING` (27×) — **intentional**: `self_check` drives the cache
  past its budget to prove the warning fires. Filtered by name in `verify.ps1`.
- `MF-WORLDS <world>: CANNOT OPEN …/mf-boot-*/baked/*.zip` (12×) — **intentional**:
  `check-bootstrap` seeds text files named `.zip` to prove the probe catches an
  unreadable world.

**`local_stack` was swept on 2026-08-17** (`-Full`, real model on the GPU) and it
was the one worth running — ten complaints nobody had ever read, and they are not
noise. See PL-9. `bench_gm` is healthy in the same run: 2.4 s and 3.1 s per turn
after a 9.0 s first turn that carries the model load, vocabulary overlap 16 %,
and **0/3 openings on atmosphere** — the CRAFT line still holds.

**The gap is closed.** `verify.ps1` passes `--log-file` on every Godot
invocation, so harness runs no longer evict `user://logs`, and a played session
was captured on 2026-08-17: resume a save, a live GM turn, the Lore Book, the
pack, clean exit. **It printed no error class the harnesses had not already
shown** — but it did settle two open questions:

- **PL-5 happens in real play**, twice in one short session. Until now it had
  only ever been seen in `click_driver`, and this row explicitly said there was
  no evidence about play. There is now.
- **PL-9 is wider than filed.** The lazy worker is not only `complete_json`'s:
  the log names `NobodyWhoChat::ask` *and* `NobodyWhoEncoder::encode` starting
  their workers on first use, and `NobodyWhoChat::reset_context` doing nothing
  because no worker was running. So the narrator and the memory encoder pay it
  too, and the first turn of every session carries a load the warning itself says
  to avoid: *"You may want to call `start_worker()` ahead of time."* `bench_gm`
  measures that first turn at **9.0 s against 2.4 s** for the next one.

| # | Item | P | E |
|---|---|---|---|

Empty. All three items were audited on 2026-08-04 and none survived — see the
mis-reported table below. `Rules.attack_mod` now requires its `inv` argument, so
a caller that forgets it fails to compile rather than silently returning the
unarmed number.

## Played by hand, 2026-08-17 — Neon Spire, "The Mercer Job"

A real session: a Tiefling Warlock forged from Raw Metal through all ten runes, a
world and tale chosen, six GM turns of real dialogue, a purchase at a merchant,
and the sheet read. Roughly forty minutes. Everything below was seen on screen or
measured, not inferred.

**The narrator is the best thing in this build.** It lifted the *ledger* out of a
class backstory typed twenty minutes earlier and made it the first image of the
opening scene, held an NPC's voice across four turns, and honoured a house rule
("my patron never speaks directly") without being reminded. The world skin is
convincing too: the currency reads *credits*, the merchant sells Mono-Knives and
Riot Shields, and the starting kit arrives reskinned — Bedroll → Thermal Blanket,
Torch → Glowstrip, Hempen Rope → Grapple Line.

**The failures are almost all at the seams**, not in the model: numbers the
narrator should never have written, tags that leaked as raw text, a skill rolled
against the wrong ability, and a currency the envelope never told it about.

| # | Item | P | E |
|---|---|---|---|
| PY-7 | **The GM relocates the player with no travel, and `counter_left` invites it.** A successful Insight roll *inside Mercer's clinic* was answered by a scene opening *"You stand outside the dimly lit entrance of Vex's Den"* — no transition, and the roll's own outcome never narrated. Later, leaving the merchant put the player in a *Night Market in The Sprawl* with Vex somehow present, then the next turn was back in the club. `_on_counter_left` asks the GM to "briefly color the exchange" and the GM answers by inventing a **place**. The prompt should name where the player is and forbid moving them | P2 | M |
| PY-8 | **"Envision this hero" is inert.** In the Appearance rune, with text in the box, it produced no portrait, no spinner, no error. It is not doing nothing: sd-server went from 102 MB idle to 124 MB and burned **16 s of CPU**, and no PNG landed anywhere under `user://`. The image is generated and discarded. **"Re-strike the portrait" on the final rune works** and gave a good likeness in ~25 s — two buttons for one job, and the prominent one is broken | P2 | M |
| PY-11 | **Card text clamps to three lines and cuts mid-word, with no ellipsis.** Barbarian ends *"answer them i"*, Bard *"mock their w"*, The Embervale *"quiet adventu"*, Neon Spire *"never sleeps or for"*, The Mercer Job *"stolen blueprt"*. Even the House Rules **placeholder** is truncated: *"(or leave the table's r"*. The writing on these cards is among the best things in the game and it is amputated on four separate screens | P3 | S |
| PY-12 | **An unstyled flat panel is used in at least four places** — Session Zero, the adventure preview, the merchant, and as a bare empty rectangle over the background art on the Heritage rune: hard-edged, borderless, unrounded, against a UI where every other panel has all three. Session Zero is the worst case, a grey debug-looking box over a fully skinned neon screen | P3 | S |
| PY-13 | **Roster cards do not show portraits that exist.** A hero forged and painted seconds earlier showed the generic flag glyph on "Who Plays Tonight?", while the pre-made Corin Vale showed his face. The portrait renders correctly on the Record, so the art is there and the card is not asking for it | P3 | S |
| PY-14 | **The world accent is only half applied.** In Neon Spire the title, input border and primary buttons go magenta; the eleven-icon toolbar, the Session Zero sliders and the HP bar stay gold — two accents on one screen | P3 | S |
| PY-15 | **Elyrien has no key art** (a generic diamond where the other seven worlds have paintings), and the world grid's bottom row is **clipped by its container** — Elyrien's "2 tales + free roam" is sliced in half | P3 | S |
| PY-16 | **Duplicate art-progress lines** — "Painting Cael Mercer…" appeared twice, identically, in the log | P3 | S |
| PY-17 | **No progress while the forge paints.** "Re-strike the portrait" takes ~25 s with no ghost state, no spinner, no line of text — the exact failure `myth_plate.gd`'s own comment names ("silence for 25 s is indistinguishable from failure"). In play the system *does* narrate ("Painting Cael Mercer…"); the forge does not | P3 | S |
| PY-18 | **Two of the ten forge runes ask nothing.** *Ruleset* offers one selectable option, already pre-chosen (the other two read "a future forging"); *The Voice* is a placeholder that "wakes when the provider does". *The Party* is a single toggle. The ritual is this game's signature and should not contain steps that are a click for nothing | P4 | S |
| PY-19 | **Large dead vertical space.** The chat log is a band across the top with the middle ~40 % of the window empty; the Record leaves its left panel empty below the equipment list and its right column empty below the saving throws; the 3D body in the Appearance rune renders as a thumbnail in a large empty panel though seven sliders drive it | P4 | M |
| PY-20 | **The titlebar maximize button did not respond** to a direct click, while double-clicking the titlebar worked. Ten minutes to confirm it is not a dead control | P4 | S |

### The fifth leaking prefix, found while fixing PY-16

| id | what | pri | size |
|---|---|---|---|
| PY-28 | **`npc-` keys are not world-scoped, and the prefix is hand-spelled in nine places.** `2b1aee9` fixed exactly this for `race-`, `item-`, `beast-` and `map-`: the PROMPT carries `world_flavor()` but the KEY did not carry the world, so the first world to paint a name owned it everywhere. `npc-` was missed. Its prompts are world-flavored too — `lore_book.gd:209` appends `Art.world_flavor()`, `game.gd:2703` picks a style word by world id — and the key is built by hand at nine sites (`art_cache` ×4, `campaign_forge`, `persona_forge`, `lore_book` ×3, `game.gd`), which is the same duplication that let five spellings of `"item-" + nm` drift apart. **Two things make it more than a repeat:** (1) `Compiler.roster_art(world_id, key)` parses the slug back out of the key, so it needs the `fam_base` treatment `beast-` got; (2) it carries a DESIGN question the others did not — two campaigns in different worlds with an NPC of the same name would currently share one face, and whether that is wrong is a call about whether a name is an identity. Route every site through an `Art.npc_key()` once that is decided | P3 | M |

### The skin stops at the surface — found by re-reading the session, then the code

Three things looked wrong in the screenshots and all three were real. Chasing
them found one shared cause: **the world skin dresses the UI and the vendor, and
almost nothing underneath it.** These are filed separately because they are
separate fixes, but PY-22, PY-23 and PY-27 are one story.

| # | Item | P | E |
|---|---|---|---|
| PY-23 | **Every world ships the identical 77 item forms, and all of them are medieval.** neonspire, brasshaven, everyday, fimbulreach and embervale each carry the same list: `halberd, mail_chausses, kite_shield, coif, crossbow, greaves, glaive, war_axe, breastplate, jerkin…`. **Zero cyber forms in Neon Spire** (no pistol, rifle, deck, drone, nano, visor — searched), and *Everyday*, whose own card reads "no magic, no chrome — just real people, real days, real talk", ships halberds and mail chausses. Materials are the same story — Neon Spire's are `aetherstone, brine_iron, drakon_skin, frostbite_mail, veldor_steel`. The Backlog already records that weapon *forms* stopped being the seed's job on purpose ("30 handcrafted weapon shapes across 7 families now always apply"); the consequence, unrecorded until now, is that a non-fantasy world has no non-fantasy gear to give | P2 | L |
| PY-26 | **The chart paints wilderness for a metropolis.** The minimap during a scene set in The Undercity and The Sprawl shows a neon-tinted river valley — sinuous water and landmass, no streets or blocks. That is the chart plate behaving as designed (the Atlas notes say it "paints terrain, water and coast and nothing that claims a position"), which is the right call for Embervale and the wrong picture for a city. A world whose `kind` is a metropolis needs district shapes, not a coastline. Related and already half-known: `mini_map.gd`'s own header says it "floats above the transcript … and costs the player words", and the fix taken was to hide it when there is no chart — not to stop it overlapping (see PY-5) | P3 | M |
| PY-27 | **The Adventure Forge is hero-first, and that is why the kit has no world.** The rail opens on "The Hero"; the world is chosen two stages later. The repo's own audit note says both entrances are world-first ("the menu's `_show_worlds()` announces *Step 1 of 3 — world › campaign › hero*"), so either the doc or this flow is stale. It is not cosmetic: the kit, the body and the portrait are all committed before the game knows whether it is painting a wizard or a runner, which is the upstream half of PY-21, PY-22 and PY-23 | P2 | M |

## The Atlas

Empty. The map has names, a legend with distinct marks, a compass, fog, quest
pull, click-to-travel, a chart plate of its own, **named roads that change what
travel costs**, and **region names you can focus** — AT-2, AT-3 and AT-4 all
done 2026-08-04.

**Realm → region, and no street tier.** AT-3 asked for realm → city → street.
Two of those exist in the world model and the third does not: a place is a
*point* with a region and a kind, and there is nothing inside a place at all. A
street tier means inventing the data and then painting it, which is a content
project rather than a map feature. What was genuinely missing was the tier the
data already had — regions were invisible, so the GM could charter one with
`[[region]]` and the player would never see it appear.

**No scale bar, deliberately.** Locations are percentages of a painted chart,
not positions on ground. A scale would be a drawn lie.

**The chart plate is ground, not a map** (AT-4, done 2026-08-04). It paints
terrain, water and coast and nothing that claims a position — so the engine's
pins and named roads are the only statement about where anything is, and the
paper cannot disagree with them. Asking the model for a *layout* was never the
answer: a spatial arrangement is strictly harder than a silhouette, and
[KnownIssues](KnownIssues.md) #5 already records how that ends.

## Distribution

| # | Item | P | E |
|---|---|---|---|
| DI-1 | **The ~10 GB first-run fetch has never run on a clean machine.** Narrowed twice. 2026-08-04: the *installer* is proven (compile → silent install → uninstall, no residue). 2026-08-14: `bootstrap.ps1`'s own logic is proven — `installer/check-bootstrap.ps1` runs the real script against throwaway roots and asserts the repair path skips all six worlds by name, a missing world is named rather than swallowed, `baked/` is created, an unreadable zip is caught by the `--mf-worlds` probe, and an incomplete payload throws instead of shrugging. Mutation-tested both ways. **What is left is only `scripts/install.ps1`** — GPU detection, the three models, the image engine — which needs a clean machine and a real connection, and nothing on this box can stand in for either | P2 | M |

## Not built

Each with the reason it is not merely undone:

- **TTS narration.** The client wiring exists; there is no local voice engine in
  the stack. It needs one chosen and shipped the way the narrator and whisper
  were — speech goes in today, nothing comes out.
- **A non-fantasy CUT for the figurine.** The pack ships Peasant and Ranger in
  male and female, and nothing else exists as CC0 on this rig — Quaternius has
  one outfit pack and it is the fantasy one. Four families now wear that cut in
  the world's own **poured cloth** (see [CharacterRender.md](CharacterRender.md)),
  which fixes the substance and not the silhouette: a Neon Spire hero is in grey
  technical weave, but still in a sleeveless tunic with thigh straps. New
  geometry is the only real answer, and image-to-3D is not available on this
  machine — the stack is Vulkan precisely because there is no CUDA here, and
  every image-to-3D model worth using is CUDA-only.
- **Co-op.** No networking design exists, and the local-first architecture is
  not obviously compatible with one.

## Parked

Relationship/reputation web · engine-verified quest objectives · world-sim depth
(NPC goals, seasons, festivals) · camp mode with banter · animated 3D dice ·
cinematic finale slideshow · photo/share mode.

---

## The audit that emptied this list

Every reported defect — P1 through P4 — was audited against the code between
2026-07-30 and 2026-08-04, fixed, and left a check that FAILS if it returns.
Each was verified by reverting the fix and watching the check fail. Nothing was
marked done on inspection.

**Eight were mis-reported**, and the only reason that was caught is that they
were *rendered or measured* rather than reasoned about. The whole Play section
was stale: all three of its rows described code that had already changed.

| Filed as | Actually |
|---|---|
| "Skills/Powers/Story leave ~700 px empty" | A horizontal problem — centred headers at x=820 over left-aligned text at x=400. Vertical centring is a no-op in a ScrollContainer and would have been wrong anyway. |
| "a Shortblade drawn as a cruciform arming sword" | The shipped prompt drew **a lit candle on a hilt** — `world_flavor()` ends in "candlelit", and at 512 px the atmosphere clause becomes the subject. The filed bug was the smaller half. |
| "Time divider on the first long rest only" | The divider only ever came from the `[[time]]` **tag**, so it appeared when the GM remembered. Rests move the clock inside the engine and printed nothing. |
| "The Atlas is decoration — no names, legend, compass" | It had all three. What it lacked was distinguishable pins — and that was a regression introduced during this very audit. |
| "Two front-ends, 9% of the repo is the game" | True at the time, and the workspace it measured is gone. |
| "The `everyday` world is content-thin — 2 weapon forms, 30 items, 6 icons" | Measured against the shipped packs: **1310 catalogue entries** (2nd of six), 9 creatures (tied 1st), 25 icons, 471 images. `weapon_forms` is not in *any* pack — forms stopped being the seed's job, and 30 handcrafted weapon shapes across 7 families now always apply. The row was describing a world format that no longer exists. |
| "Tale and world are coupled — you cannot pick a tale then choose its world" | Fixed on 2026-07-22 by `913184a`, *before the audit that filed the row*. Both entrances are world-first: the menu's `_show_worlds()` announces "Step 1 of 3 — world › campaign › hero", and the Adventure Forge runs `_stage_campaign_world()` → `_stage_campaign_tale()`. The one tale-first path is the Campaign Shelf, which exists **on purpose** to browse premises across every world, and whose cards carry their world. |
| "`Rules.attack_mod` falls back to `GameState.inv()`" | It defaulted to `{}` — so a caller who forgot `inv` got the *unarmed* number, not a stale one. Real bug, wrong mechanism. Fixed by making `inv` required; the check is the compiler. |
| "The tile library is ~1.3 GB generated per install — ship it or make every player pour it" | Already shipped. Every world package carries **272 tiles across 170 roles, ~220 MB**; six worlds is the 1.3 GB the row was counting. `bootstrap.ps1` already downloads them and `board_paint._tile()` reads the package first. `user://tiles` fills only for a world the **player forges**, where generation is the only option there is. |

## The method notes worth keeping

**Assert what the failure looks like, not what a good answer looks like.** A
metric that scores broken output as fine is worse than no metric. Three did:
a vocabulary score rated three identical sunset openings 19 % "OK"; a word
splitter dropped words under four characters so "air" never reached the
atmosphere detector; a sanity check accepted `#:7A288A` as a material.

**A test that cannot tell whether the feature is plugged in is not testing the
feature.** The GM-model check re-implemented its ranking inline and passed for
weeks while the picker wrote to a key nothing read. The Atlas colour check
asserted every kind *had* a colour, never that the colours *differed* — and let
two duplicated pairs through.

**Render it.** Five of the last dozen fixes changed shape once the thing was
screenshotted or generated. Reading the code told the wrong story every time.
