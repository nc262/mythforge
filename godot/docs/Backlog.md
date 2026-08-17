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

**The whole list, so it can be driven to zero.** Every log on the box was swept
on 2026-08-17 — 205 files, 307 matching lines, 30 distinct. **It produced no new
defects.** Four rows survive triage; everything else is historical or deliberate,
and is listed below so nobody triages the same thirty lines twice.

| Complaint | Seen in | Row |
|---|---|---|
| `N ObjectDB instances were leaked at exit` | click_driver, ui_playthrough | PL-8 |
| `N resources still in use at exit` | click_driver, ui_playthrough | PL-8 (same cause) |
| `Attempting to make child window exclusive…` | ui_playthrough | PL-6 |
| `Lambda capture at index 0 was freed` | click_driver | PL-5 |

**N varies — 2 and 1 in some runs, 6 and 3 in others.** It tracks how many
distinct sounds a session played, which is the strongest evidence for PL-8's
audio diagnosis and means the count is not a useful signal on its own.

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
| PL-10 | **The double BOS is EXONERATED, and so is the grammar-vs-await theory. Five real-model runs on 2026-08-17 replaced the whole premise of this row.** (a) **The proposed fix cannot be written.** `NobodyWhoModel` exposes exactly two properties — `model_path` and `projection_model_path` — and `NobodyWhoChat` four: `model_node`, `system_prompt`, `allow_thinking`, `context_length`. There is no `add_bos_token` on either, and the game hands `ask()` a plain string, so it never composes the BOS it was going to strip. Printed from `get_property_list()` on the live nodes in `local_stack`. (b) **The double BOS is not the cause of anything.** `check_double_bos_eos` appears **38 times in a run that exits 0 and prints `LOCAL STACK OK`**. One grep of the baseline log would have settled this before the row was written; it is the third time in this project a line in a *passing* log has been read as a defect. (c) **What actually aborts**, bisected with PL-9's `await _json_chat.worker_started` in place, one `local_stack` run per arm: **A** await + schema → abort after exactly 1 `Ask`. **B** await + `set_sampler_preset_json` → abort (note: that preset installs a default GBNF `Grammar` step of its own, so B was *not* the grammar-free arm it looks like). **C** await + schema, `reset_context` skipped → still aborts, so `reset_context` is exonerated. **D** await, no sampler config at all → **no abort** (it hung on unparseable output and was killed at 10 min). **E** await + a `NobodyWhoSamplerBuilder` chain with no grammar → **no abort**: generation ran to completion many times over 7 minutes, and only the JSON assertions failed, exactly as [LocalLLM-Tuning](LocalLLM-Tuning.md) predicts with nothing constraining the output. **So the await is exonerated too.** The abort needs a *constrained* sampler — `JsonSchema` or `Grammar` — reaching a worker that has genuinely started, as that worker's first act. (d) **And this is why the shipped game does not crash:** PL-9's "bug" is what shields it. In the passing baseline exactly **1** sampler config is dropped and **17** land, 11 of them `JsonSchema` — so constrained generation works perfectly well on that node once it has done one unconstrained turn. **That next experiment was run, arm F, and it FAILED.** Await `worker_started`, let a throwaway unconstrained `ask("Say OK.")` run to `response_finished` — it completed, printed, and the constrained call that followed aborted anyway. So "the node needs one unconstrained turn first" is **wrong**, and the sharpest statement the six runs support is this: *explicit* `start_worker()` + awaited readiness + a constrained sampler aborts, while a **lazy** worker start (what ships today) + the same constrained sampler is fine — eleven `JsonSchema` configs land and work in the baseline. The difference is no longer anything the game does with the sampler; it is what `start_worker()` leaves behind that a lazy start does not. **That is a NobodyWho-internals question and belongs to the `researcher` agent** (*"Rust cannot catch foreign exceptions" + `start_worker` + constrained sampler / GBNF + Vulkan*), not a seventh local run. **Three fix hypotheses have now been ruled out by measurement — warm earlier, bare await, await-plus-throwaway-ask — so stop guessing here.** Note also that the shipped behaviour is not broken, only warned about: the game's structured calls work. What is lost is the first one's constraint, and the 9.0 s first turn | P2 | M |
| PL-9 | **`start_worker()` is asynchronous, and the next two calls are thrown away.** In `LocalGM.complete_json()` the node is created, `start_worker()` is called, and then — in the same frame — `set_sampler_preset_constrain_with_json_schema()` and `reset_context()`. NobodyWho answers both: *"Worker not started, dropping sampler config"* and *"Attempted to reset context, but no worker is running. Doing nothing."* So on the **first structured call of a session** the schema constraint is silently discarded and the call is not stateless. `Parse JSON failed. Error at line 0: Unexpected character` appears in the same run, which is what an unconstrained call produces — this repo's own [LocalLLM-Tuning](LocalLLM-Tuning.md) records that a schema-constrained call is what makes JSON parse at all. Same shape at `local_gm.gd:169` for the narrator's `_chat` — and a **played session proves it is wider than one call site**: the log names `NobodyWhoChat::ask` and `NobodyWhoEncoder::encode` both starting their worker on first use, plus `reset_context` doing nothing. The narrator and the memory encoder each pay a lazy start, which is what makes `bench_gm`'s first turn 9.0 s against 2.4 s for the next. **ATTEMPT 2 FIXED IT AND THE FIX CRASHED THE ENGINE — the most important thing on this row.** `worker_started` is the readiness signal (found via `get_signal_list()` from `local_stack`; `worker_failed` was already used). Awaiting it before configuring made all three lines vanish, and the worker log proves the fix worked: `msg=SetSamplerConfig { … Grammar { … } }` then `msg=ResetChat` then `msg=Ask`. The config landed and the reset happened. **Then llama.cpp aborted** — `fatal runtime error: Rust cannot catch foreign exceptions, aborting`, exit `0xC0000409`, and `LOCAL STACK OK` never printed. **So the dropped config was accidentally shielding the game from a crash in grammar-constrained generation**, and "harmless warning" was exactly wrong. Reverted; a crash is worse than a warning. **That diagnosis was half right and was corrected on 2026-08-17 by five real-model runs — see PL-10.** The abort is not the await and not the double BOS (which appears 38 times in a run that passes) and not `reset_context`: the same await with an unconstrained sampler generates happily for seven minutes. What aborts is a **constrained** sampler reaching a worker that has genuinely started, as that worker's first act — and in the passing baseline 11 `JsonSchema` configs land and work, on a node that had already done one unconstrained turn. So the shape of the fix is: await readiness, spend one throwaway unconstrained `ask()`, then configure. Do not re-apply the bare await. **Attempt 1 measured three things worth having.** (a) `_chat.has_method("start_worker")` is **true** and the call fires — the narrator is already warmed at `_setup`, so the guarded call is not a no-op and the narrator is not the offender. (b) The remaining warnings come from nodes created and used in one breath: `_json_chat` in `complete_json`, and the encoder. (c) **Warming `_json_chat` at `_setup` is not sufficient** — extracted to an `_ensure_json_chat()` called from `_setup`, and all three lines still appeared, because `local_stack` issues its first structured call immediately and `start_worker()` is still in flight. Reverted. **So the fix must WAIT for readiness, not merely start earlier.** Next step is one probe: print `get_signal_list()` on the chat node **from `local_stack`** — `self_check` cannot, it runs in `Api.test_mode` where `_setup` never executes — and connect to whatever readiness signal exists before configuring. **THE INTENDED FIX CHANGED SHAPE 2026-08-17, and it is better.** Rather than racing the worker, **hold the loading curtain until it is ready** — which is what games do with a boot screen, and this project already has the machinery: `MythLoading.mark(fraction, line)` / `lift()` in `godot/ui/myth_loading.gd`, already driven by the boot at *"Recalling the tale…"* (0.6) and *"Setting the table…"* (0.9). Add a mark such as *"Waking the storyteller…"* and move `lift()` to after the worker reports ready. That turns a warning into a feature: the 9.0 s first turn stops being a frozen-looking sentence and becomes honest progress, the sampler config lands because the worker exists by then, and `reset_context` stops being a no-op — one change, and PL-9's three lines go with it. **Still to measure first:** the curtain needs something to wait ON, so the one probe above (`get_signal_list()` from `local_stack`) is still step one. If no readiness signal exists, poll a cheap property instead of sleeping a guessed number of frames. **Verify by the absence of those three lines in a `-Full` run** plus a first turn that shows progress, not by reading the code | P2 | S |
| PL-5 | **`Lambda capture at index 0 was freed. Passed "null" instead.`** in every `click_driver` run **and twice in a real played session** (confirmed 2026-08-17 from a captured play log, so this is not a harness artefact). A connected lambda outlives a node it captured, so it fires with a null capture. Harmless where the body only touches the capture through `is_instance_valid`, a crash or a silent no-op where it does not — and there is no way to know which without finding it. `game.gd` connects several capturing lambdas (`Art.art_ready`, `Chronicle.chronicle_updated`, the companion portrait, the clear-table button); the portrait one already guards with `is_instance_valid`, which is the pattern the others should follow | P3 | S |
| PL-6 | **Two exclusive child windows at once** — `Attempting to make child window exclusive, but the parent window already has another exclusive child`, raised from `_open_shop` during `ui_playthrough._build_windows`. Most likely a harness artifact: it opens every window back to back without closing. Worth ten minutes to confirm, because if a player can reach two modals at once the second one is unreachable and the first cannot be dismissed | P4 | S |
| PL-8 | **Every run leaks its audio.** `--verbose` names all six: three `AudioStreamWAV` and three `AudioStreamPlaybackWAV`, and the three resources are `ui_hover.wav`, `ui_click.wav`, `amb_embervale.wav` — exactly the sounds a session touched. `Sfx` is an autoload that preloads every WAV into a persistent `AudioStreamPlayer`; playing one leaves a playback alive in the AudioServer, which holds the stream past teardown. **Attempt 1 failed and measured why:** an `_exit_tree()` on `Sfx` that stops each player and nulls its stream changed nothing, and a `print()` inside it **never appeared in the log** — `_exit_tree` does not fire for an autoload on this quit path, so the hook was wrong, not the logic. Next: try `_notification(NOTIFICATION_PREDELETE)` or a `tree_exiting` connection, and confirm the hook runs *before* writing the body. Harmless at runtime; it is the loudest thing in a green log, which is how a real complaint learns to look like furniture | P3 | S |

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
