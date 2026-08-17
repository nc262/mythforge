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

**PL-5 is closed** (2026-08-17), and its filed mechanism was wrong — the ninth
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
| PL-9 | **The correctness half shipped; the LATENCY half did not, and the number says so.** All three lazy-worker sites now await `worker_started` — `complete_json`'s `_json_chat`, and the memory encoder in `local_memory.gd` — and a `-Full` run prints **none** of the three lines (`Worker not started, dropping sampler config`, `Attempted to reset context…`, `Worker was not started yet…`). `LOCAL STACK OK`, exit 0. **What did NOT move: `bench_gm` turn 1 is 8.8 s against the 9.0 s filed** — noise, not an improvement — because the narrator's `_chat` already called `start_worker()` at `_setup`, and the ~4.6 GB load happens inside `ask()` regardless of when the worker was asked to start. Starting early is not the same as being loaded. **So the row's own better idea is what remains, and it is a UI change, not a model one:** hold the loading curtain until the worker reports ready — `MythLoading.mark(fraction, line)` / `lift()` in `godot/ui/myth_loading.gd`, already driven by the boot at *"Recalling the tale…"* (0.6) and *"Setting the table…"* (0.9). Add a mark such as *"Waking the storyteller…"* and move `lift()` to after readiness, so those 8.8 s read as honest progress instead of a frozen first sentence. The readiness signal is known and proven: `worker_started`. **Verify by a first turn that shows progress, and do not claim the seconds went away — they did not, they became visible** | P3 | S |

Empty. All three items were audited on 2026-08-04 and none survived — see the
mis-reported table below. `Rules.attack_mod` now requires its `inv` argument, so
a caller that forgets it fails to compile rather than silently returning the
unarmed number.

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
