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

**The whole list, so it can be driven to zero.** A gate run produces exactly
five distinct complaints; one is raised on purpose:

| Complaint | Harness | Row |
|---|---|---|
| `6 ObjectDB instances were leaked at exit` | click_driver, ui_playthrough | PL-8 |
| `3 resources still in use at exit` | click_driver, ui_playthrough | PL-8 (same cause) |
| `Attempting to make child window exclusive…` | ui_playthrough | PL-6 |
| `Lambda capture at index 0 was freed` | click_driver | PL-5 |
| `art cache is THRASHING` | self_check | **intentional** — the harness drives the cache past its budget to prove the warning fires; filtered by name in `verify.ps1` |

| # | Item | P | E |
|---|---|---|---|
| PL-8 | **Every run leaks its audio.** `--verbose` names all six: three `AudioStreamWAV` and three `AudioStreamPlaybackWAV`, and the three resources are `ui_hover.wav`, `ui_click.wav`, `amb_embervale.wav` — exactly the sounds a session touched. `Sfx` is an autoload that preloads every WAV into a persistent `AudioStreamPlayer`; playing one leaves a playback alive in the AudioServer, which holds the stream past teardown. **Attempt 1 failed and measured why:** an `_exit_tree()` on `Sfx` that stops each player and nulls its stream changed nothing, and a `print()` inside it **never appeared in the log** — `_exit_tree` does not fire for an autoload on this quit path, so the hook was wrong, not the logic. Next: try `_notification(NOTIFICATION_PREDELETE)` or a `tree_exiting` connection, and confirm the hook runs *before* writing the body. Harmless at runtime; it is the loudest thing in a green log, which is how a real complaint learns to look like furniture | P3 | S |

| # | Item | P | E |
|---|---|---|---|
| PL-7 | **SOFT-LOCK: you cannot leave a merchant once you touch an item.** Found by playing the shipped build on 2026-08-14, not by a harness. Open a counter, click any ware — the detail card appears, and **"Leave the counter" is gone**. Escape does nothing, clicking outside does nothing, clicking where the button was does nothing, and the panel does not scroll. The only exit is killing the process, and the trade is already committed so the save keeps the gold. **Cause:** that button is the dialog's own OK button (`merchant_window.gd:40`, `ok_button_text`), not a child, and `min_size` is 720×480. Adding the detail card to `root` (line 152) grows the `AcceptDialog` *downward* from a position `popup_centered()` fixed when it was shorter, so the button row ends up outside the viewport. It never re-centres and nothing scrolls. **Three fixes were tried against the running game on 2026-08-14 and all three failed — reverted, and this is what they rule out:** (1) *the content cap never re-measures.* `Skin._cap_panel_content` exists for exactly this ("stop `wrap_controls` pushing the exit off the bottom") but runs deferred once at build time and thereafter only on **root resize**, so a strip revealed later re-measures nothing. Wiring it to `content.minimum_size_changed` changed nothing on screen — and measuring says why: `PANEL_RESERVE` is 76, so the cap is ~876 px against ~600 px of content. **The cap never binds. Nothing is too tall.** (2) *the window is too low.* `popup_centered()` centres once at the opening size and the dialog grows downward from that stale origin — plausible, but clamping `position.y` so the bottom stays on screen also changed nothing. (3) *the instrument, and this note was itself wrong once — corrected 2026-08-14.* A `print()` of `dlg.position/size` and the OK button's `get_global_rect()` reached no log, and that was written up here as "a windowed exported build does not flush `print()`". **It does.** Three unrelated things had hidden it: the process was force-killed (no flush), the title-bar X never actually closed it, and `max_log_files` was **5** while one `verify.ps1` run starts **four** Godot processes — so the gate rotated the play session's log away. Proven by closing a booted game with `CloseMainWindow()` and reading the 145-byte log it left. `max_log_files` is now 30. **So the instrument is available: `print()` the geometry, boot, reproduce, close cleanly, read the log BEFORE running the gate.** Do not guess a fourth time from screenshots. Not caused by this session; `_open_shop` and `merchant_window.gd` were untouched | P1 | M |
| PL-5 | **`Lambda capture at index 0 was freed. Passed "null" instead.`** in every `click_driver` run. A connected lambda outlives a node it captured, so it fires with a null capture. Harmless where the body only touches the capture through `is_instance_valid`, a crash or a silent no-op where it does not — and there is no way to know which without finding it. `game.gd` connects several capturing lambdas (`Art.art_ready`, `Chronicle.chronicle_updated`, the companion portrait, the clear-table button); the portrait one already guards with `is_instance_valid`, which is the pattern the others should follow | P3 | S |
| PL-6 | **Two exclusive child windows at once** — `Attempting to make child window exclusive, but the parent window already has another exclusive child`, raised from `_open_shop` during `ui_playthrough._build_windows`. Most likely a harness artifact: it opens every window back to back without closing. Worth ten minutes to confirm, because if a player can reach two modals at once the second one is unreachable and the first cannot be dismissed | P4 | S |

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
