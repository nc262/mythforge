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

**PL-5 IS CLOSED — 2026-08-24, reproduced deterministically before it was fixed.**
It was never a leaked signal connection. It was `skin.gd:_cap_panel_content`
ending with **`apply.call_deferred()`** — the only deferred lambda in the
codebase — where `apply` captures `dlg` and `content`, which is the
index-0/index-1 PAIR every report carried. A deferred LAMBDA is bound to no
object, so Godot cannot cancel it when the dialog dies; it flushes on the next
idle and rebinds two dead captures. Close a panel in the frame it opens and you
get one pair, reliably.

`apply` already began with `if not is_instance_valid(dlg) ...: return`, which is
why nine diagnoses looked at it and saw nothing wrong. **That guard cannot work
here:** the error is emitted when the Callable is INVOKED, before its body runs.
The fix moved the guard to the call site, into `_apply_when_built(dlg, content,
apply)` — a method whose nodes are ARGUMENTS, which are checkable.

Found by elimination, not by theory: a census of every autoload signal's
connections across a playthrough showed **none grew** (killing the whole leaked-
connection family), the root Window showed none either, therefore the lambda was
reached by something that is not a connection — and grep found exactly one
deferred lambda. `tests/pl5_probe.tscn` then made it fail on demand: **10 errors,
10/10 runs**, zero after the fix. It is in the gate now and exists to fail.

The four theories disproven on the way, and why each looked like evidence, are in
[Invariants.md](Invariants.md). The short version: 20+ clean runs were read as
support on BOTH sides of every theory, and none of them could ever make the bug
happen.

**The original entry, kept because its lesson stands:**

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
| PY-7 | **FIXED 2026-08-24 (2045ce0).** `GameState.here_pin()` already said exactly what this row asks — and its own RCA comment IS this bug, written for a camper who woke in a mead-hall. It was applied to the three REST paths and nowhere else, so the merchant counter and the roll result carried nothing. Four stay-put instructions pinned (the sweep found two more than reported); travel, resume and session-zero deliberately NOT pinned, and the check asserts that too. Mutation-tested both ways. Original report: **The GM relocates the player with no travel, and `counter_left` invites it.** A successful Insight roll *inside Mercer's clinic* was answered by a scene opening *"You stand outside the dimly lit entrance of Vex's Den"* — no transition, and the roll's own outcome never narrated. Later, leaving the merchant put the player in a *Night Market in The Sprawl* with Vex somehow present, then the next turn was back in the club. `_on_counter_left` asks the GM to "briefly color the exchange" and the GM answers by inventing a **place**. The prompt should name where the player is and forbid moving them | P2 | M |
| PY-8 | **MEASURED 2026-08-24: the generation half does NOT reproduce.** A new harness, `tests/art_probe.tscn`, drives the real engine headless and reports the state machine at every step. Twice — once under its own key and once under the exact `heroprev` PY-8 names — a commission went `queued → painting → ready` in **20.5 s / 20.6 s** and wrote its PNG (`user://art/heroprev.png`). `Art.hold` was `false`; `pending` returned to 0. **So the pipeline is healthy and "the image is generated and discarded" is not what it does** — the pump saves BEFORE `_finish` is called, and cancellation only suppresses the callback, never the file. That also means the reporter's "no PNG landed" was checked after `Art.forget("heroprev")` had already deleted the previous one, so an absent file proved less than it looked. **What is left:** either the DISPLAY path (before today the Appearance stage listened through an unowned lambda, converted in `f180e8c` — so this may already be fixed as a side effect), or something in the forge context a headless probe cannot enter, most plausibly `Art.hold` stuck true, which stalls `_pump` for up to 180 s in silence. **Closing it needs a windowed forge run**, which is a human call. Root cause found on the way: `local_stack`, the only harness that touches the GPU, never exercised art at all — `art_probe` now runs in `verify -Full`. Original report below | P2 | M |
| PY-8 (original) | **"Envision this hero" is inert.** In the Appearance rune, with text in the box, it produced no portrait, no spinner, no error. It is not doing nothing: sd-server went from 102 MB idle to 124 MB and burned **16 s of CPU**, and no PNG landed anywhere under `user://`. The image is generated and discarded. **"Re-strike the portrait" on the final rune works** and gave a good likeness in ~25 s — two buttons for one job, and the prominent one is broken | P2 | M |
| PY-11 | **FIXED 2026-08-24 (00b5135).** Not a layout bug at all — six card payloads called `.left(90)`/`.left(60)` on prose and severed it in CODE. "with no ellipsis" was the tell: clipping hides characters, it does not remove them. `Ui.trim()` cuts at a word in one place; the House Rules placeholder WAS genuinely clipped and is shorter copy now. Mutation-tested. Original report: **Card text clamps to three lines and cuts mid-word, with no ellipsis.** Barbarian ends *"answer them i"*, Bard *"mock their w"*, The Embervale *"quiet adventu"*, Neon Spire *"never sleeps or for"*, The Mercer Job *"stolen blueprt"*. Even the House Rules **placeholder** is truncated: *"(or leave the table's r"*. The writing on these cards is among the best things in the game and it is amputated on four separate screens | P3 | S |
| PY-12 | **FIXED 2026-08-24 (b5f031e).** A Window does not inherit a theme in Godot 4, so every PanelContainer inside a dialog fell back to engine grey — that is the "grey debug-looking box". Three of five dialogs never called `dress_dialog` at all, and `dress_dialog` never set `theme`, so even the dressed ones had unstyled innards. Both halves mutation-tested. **Not verified visually** — structural only. Original report: **An unstyled flat panel is used in at least four places** — Session Zero, the adventure preview, the merchant, and as a bare empty rectangle over the background art on the Heritage rune: hard-edged, borderless, unrounded, against a UI where every other panel has all three. Session Zero is the worst case, a grey debug-looking box over a fully skinned neon screen | P3 | S |
| PY-13 | **FIXED 2026-08-24 (f180e8c).** `bank_hero` asked `hero_portrait_key` for its copy SOURCE — the one function written never to return "heroprev" — so a menu-forged hero was never pinned and the roster asked the same refusing function for ever. 2 of 4 heroes in the real save were stranded. Also fixed: a null `id` read back as the string "<null>" and sailed past the empty-id guard. Mutation-tested. Original report: **Roster cards do not show portraits that exist.** A hero forged and painted seconds earlier showed the generic flag glyph on "Who Plays Tonight?", while the pre-made Corin Vale showed his face. The portrait renders correctly on the Record, so the art is there and the card is not asking for it | P3 | S |
| PY-14 | **FIXED 2026-08-24 (82c5981).** Not a palette problem: Neon Spire's `gold` role IS cyan. The split is THEMED vs SELF-DRAWN — Godot re-runs `_draw()` only on `queue_redraw()`, so 13 of 14 self-drawn controls held the old accent. `myth_icon` is the toolbar, `myth_gauge` the HP bar, `myth_stage_rail` the sliders — the three the report names. `Ui.repaint_on_skin()` now. Mutation-tested. **Not verified visually.** Original report: **The world accent is only half applied.** In Neon Spire the title, input border and primary buttons go magenta; the eleven-icon toolbar, the Session Zero sliders and the HP bar stay gold — two accents on one screen | P3 | S |
| PY-15 | **FIXED 2026-08-24 (e61359c, 8bd62d2).** Two causes. `WORLD_PROMPTS` held 3 entries for 6 worlds and `request()` returned SILENTLY for the rest; prompts are derived from the world's own kind+tagline now, so a forged world gets key art too. And key art lives in two places — package and cache — with the fallback hand-spelled at five sites in three ways, two wrong in opposite directions; `Art.world_tex()` is the one spelling. All six worlds have backdrops. Original report: **Elyrien has no key art** (a generic diamond where the other seven worlds have paintings), and the world grid's bottom row is **clipped by its container** — Elyrien's "2 tales + free roam" is sliced in half | P3 | S |
| PY-16 | **FIXED 2026-08-24 (965080e).** `_auto_portrait` guarded on `has_art`, true only when the paint FINISHES ~20 s later, so every codex update inside that window narrated again. The work was never duplicated — only the line. Guards on `Art.status()` now. Mutation-tested. Original report: **Duplicate art-progress lines** — "Painting Cael Mercer…" appeared twice, identically, in the log | P3 | S |
| PY-17 | **FIXED 2026-08-24 (965080e).** The forge re-strike went silent for the ~25 s it paints and stayed pressable. It names the work and disables now — plus a failure path the report did not ask for: a failed paint emits no `art_ready`, so the naive fix would have hung the button for the whole session. Original report: **No progress while the forge paints.** "Re-strike the portrait" takes ~25 s with no ghost state, no spinner, no line of text — the exact failure `myth_plate.gd`'s own comment names ("silence for 25 s is indistinguishable from failure"). In play the system *does* narrate ("Painting Cael Mercer…"); the forge does not | P3 | S |
| PY-18 | **Two of the ten forge runes ask nothing.** *Ruleset* offers one selectable option, already pre-chosen (the other two read "a future forging"); *The Voice* is a placeholder that "wakes when the provider does". *The Party* is a single toggle. The ritual is this game's signature and should not contain steps that are a click for nothing | P4 | S |
| PY-19 | **NEEDS A WINDOWED LOOK — 2026-08-24.** The mechanical layer is already correct: the chat `Scroll` carries `size_flags_vertical = 3` and expands. The dead space is content top-aligned inside an expanding container, so where it SHOULD go (bottom-anchor the log like a chat app? grow the body render?) is a design decision across three screens, not a missing flag. Not fixable blind, and headless cannot see the result. Original report: **Large dead vertical space.** The chat log is a band across the top with the middle ~40 % of the window empty; the Record leaves its left panel empty below the equipment list and its right column empty below the saving throws; the 3D body in the Appearance rune renders as a thumbnail in a large empty panel though seven sliders drive it | P4 | M |
| PY-20 | **NEEDS A WINDOWED LOOK — 2026-08-24.** No code cause found: there is no custom titlebar, nothing sets a min_size or window mode on the MAIN window (every `min_size` in the repo is on a dialog), and `project.godot` sets no resizable/mode flags. An OS titlebar button cannot be reproduced or measured headlessly. Original report: **The titlebar maximize button did not respond** to a direct click, while double-clicking the titlebar worked. Ten minutes to confirm it is not a dead control | P4 | S |

### Waiting on a five-minute read, then an hour of GPU

| id | what | pri | size |
|---|---|---|---|
| AT-10 | **DONE 2026-08-27.** `MapInk` is the one home for the symbol set — a house with a chimney for an inn, a stall for trade, towers behind a wall for a settlement, a broken arch for a ruin, a pillar for a landmark. Paper shows through each one rather than a solid fill, because an engraver leaves the sheet inside a symbol and a blob loses its silhouette at 12 px. SILHOUETTE CARRIES THE WHOLE KIND now: `KIND_MARK` paired colour with shape because the palette does not hold seven separable hues, and on a one-ink chart there is no hue left at all — a stronger version of the same accessibility rule, not a relaxation. Original report: **The chart is INK ON PARCHMENT now — the pins are not.** The paper, the coastline, the shore hatching, the drawn peaks and trees, the lettering and the key are all ink on a stock chosen per family. The PLACE MARKS are still UI: a purple diamond, an orange ring, a cyan dot, sized for a dark panel. On a book map a settlement is a little tower, a ruin is a broken arch, an inn is a cup — DRAWN symbols in the same ink as everything else. `KIND_MARK` already pairs colour with shape for accessibility, so the replacement must keep a distinct silhouette per kind and stop relying on hue, which is easier in ink than it was in UI colour | P2 | M |
| AT-11 | **DONE 2026-08-27.** `local_paper.gdshader` is the paper half of `chart_paper` — the Atlas shader reads a height field and a town has none, so the sheet is shared and the geometry is not. The town sea is hatched with lines PARALLEL TO THE SHORE rather than off a depth field, which is what the same engraver would do at that scale. Streets are the paper between the buildings edged in ink; footprints are outlines with a few inked solid; a scouted room is a DASHED wall, the way a surveyor draws what was reported rather than measured. `place_map` also carried its own copy of `_draw_mark` and now shares `MapInk`. Original report: **The local tier is still coloured relief while the world chart is a book map.** `place_map` draws green ground, blue water and beige buildings; the Atlas above it is parchment. Two tiers of one atlas must be drawn on the same stock. The generator underneath is fine — it is only the rendering that predates the style, and `WorldTerrain.PAPER` plus `ink_colour()` are already the one place to ask | P2 | M |
| AT-12 | **WRONG WHEN FILED, and DONE 2026-08-27.** The claim was false: `Ui.serif` (a `SystemFont` over Palatino Linotype / Book Antiqua / Georgia) and `Ui.display` (a `FontVariation` over it with glyph spacing already set) have been in `skin.gd` all along. I grepped for font FILES, found none, and concluded there was no serif — a SystemFont ships nothing and resolves at runtime, so it leaves no artefact to grep for. The Atlas letters in `Ui.display` now, and the cartouche letterspaces it further by hand because `draw_string` has no tracking. Original claim: **No serif face anywhere in the project.** `theme.default_font` is a built-in sans, and a chart wants a serif — the reference lettering is what sells a book map as much as the linework does. Region names already fake it with hand-rolled letterspacing (`draw_string` has no tracking). A single licensed serif in `godot/ui/fonts/` would lift every label on the Atlas, the local maps and the Lore Book at once | P3 | S |
| AT-15 | **The town tier, what is left after AT-14.** The plan, the trades, the wards, the countryside and the trouble clock all landed; these are the known gaps, in payoff order. (a) **A landmark is still a mark, not a building** — a named place borrows a `ROLE_MARK` silhouette and stands on an ordinary lot. Watabou reserves the whole Voronoi patch BEFORE subdividing and picks it by a per-class `rateLocation` cost function; the equivalent here is to reserve a lot at 3-5x and give a church a nave, a keep corner towers. (b) ~~No street hierarchy~~ **DONE 2026-09-16** — gates snapped to real street mouths (22 of 29 had opened onto buildings) and high streets routed gate-to-square through the gap network on `AStarGrid2D`. Was: `MAIN_STREET`/`REGULAR_STREET`/`ALLEY` exist as constants and only two are used; the reference computes `arteries` once (every gate-to-square and gate-to-countryside path) and tiers each edge by set membership, NOT by subdivision depth — my first instinct was depth and it is wrong. (c) ~~The square is a label over houses~~ **DONE 2026-09-16** — the square ward keeps an open plaza and each high street is cut through into it. (d) ~~Empty lots render as bare ground~~ **DONE 2026-09-16** — unbuilt plots are kept as gardens and drawn as plan-view canopies. (e) ~~The ruin tier never got scaled up~~ **FILED WRONG, measured 2026-09-16.** Inferred from one screenshot of The Sunken Fort, where a small cluster sat at the sheet's edge. Measured across all 15 shipped ruins, layouts span 36-73 x 59-90 of the 100-unit plate — they were never tied to the town radius, and what the shot showed was FOG (2 of 6 rooms visible, as designed). The one real number: rooms cover only 6-10 % of the plate, so a fully explored ruin is small boxes on a big sheet. Whether that reads as sparse is taste, not a defect — ask before enlarging. (f) ~~Region banner overlaps a place label~~ **DONE 2026-09-16** — the chart solver reserves region banners; the check also caught Fimbulreach's White Fjord across THE FJORDLANDS. | P2 | L |
| AT-14 | **DONE 2026-09-15.** The town plan is Watabou's algorithm rather than an imitation of its output: wards cut out of the boundary by longest-edge splitting, each inset to leave its street, each subdivided recursively to a log-normal area target with **no reject step** — density is structural, not tuned. Every building is a sub-polygon of its block, so a wall facing a street is parallel to it by construction and there is no align-to-road pass. STREETS ARE NEVER DRAWN: each cut opens a physical gap, so a road is the ground nobody built on and a building cannot cross one. Two silent-loss bugs died on the way, and the second is the one that mattered: `inset` was half-plane clipping, which is an inset only for a CONVEX polygon — wards carry reflex vertices from the shoreline, and the clip took wards of 550/509/393 down to 103/322/**0**. Rewritten as a vertex-bisector offset; wards now keep ~90 % of their area and building counts went 147 → 226 on Gallows Quay. `town_probe` is in the gate and fails on any ward that comes out bare. Original report: the first generator subdivided an axis-aligned RECTANGLE and discarded every lot that fell on a street, in the water or outside the wall — so every lot was a box and most candidates were thrown away, which is why the result read as graph paper with a hamlet scattered on it | P2 | L |
| AT-5 | **DONE 2026-08-27.** `LocalMap` generates the interior, seeded from world+name, and INHERITS ITS SITE from `WorldTerrain.klass()` at the place's cell — Gallows Quay stands on a COAST cell, so its town has a Quay, and the local map cannot contradict the world map about the ground it is built on. `place_map.gd` draws it in the Atlas's own visual language. Clicking the place you are ALREADY STANDING IN was a free gesture (it did nothing) and is now the way in. Original design: **The local tier: click a place, get its own map.** THE LOCAL MAP IS THE WORLD MAP RECURSED — `world_map.gd` is already nodes + edges + fog + click-to-travel + pan/zoom, and a dungeon is rooms and corridors while a town is buildings and streets. Same component, a different generator and scale. <br><br>**A room is a NODE you click, not a token you walk.** This game travels between discrete points and the GM narrates arrival; continuous movement would mean inventing input, collision and encounter triggers, and would contradict every other screen. Point-crawl reuses ~700 lines instead. <br><br>Two generators by kind: SETTLED (settlement/tavern/shop/home) gets a town plan — streets, blocks, a square, walls above a size, the shore if its world cell is COAST; UNSETTLED (ruin/wilds) gets rooms and corridors. Both seeded from `world_id + name`, deterministic, and both take their site from `WorldTerrain.klass()` at the place's cell so the local map cannot contradict the world map. Watabou's Medieval Fantasy City Generator is the reference for the settled case (recursive ward/block subdivision, street polylines, after Parish &amp; Müller) | P2 | XL |
| AT-6 | **WORLD-MAP HALF DONE 2026-08-27; the local half waits on AT-5.** Three states — unknown / heard of / visited — with precedent: Baldur's Gate II updates the world map from dialogue alone ("Your world map has been updated"), Pillars of Eternity greys a location learned by being told about it, Skyrim draws known-unvisited black against visited white. HEARD is clickable, following BG2 rather than Pillars. The "?" cloud is GONE: a point-crawl has no surface to sweep, so a place either has a pin or it does not, and clouds would import a busywork failure this design is immune to by construction — never add a "map revealed" percentage either. Hollow-vs-filled rather than a hue difference, so the state survives colour-blindness. Original design: **Fog models IGNORANCE, not distance.** A settlement, tavern, shop or home is **never fogged** — people live there, there is signage, you can ask, so the plan is whole on arrival. A ruin, wilds or dungeon **is** fogged, because nobody is there to tell you; reveal as you go. The rule derives entirely from `kind`, which every place already carries, so it needs no authored data and explains itself in a sentence. <br><br>Revealed stays revealed. RTS-style re-shrouding punishes exploration; single-player RPGs use the permanent form because permanence rewards it. The world map's existing `fog`/`seen` machinery is node-granularity already, which is what point-crawl fog wants — see the minimap research | P2 | M |
| AT-7 | **DONE 2026-08-27.** A coin badge beside any known place carrying a `shop`, and a "trades here" row in the legend drawn by the same `_draw_trade` as the pins — two drawings of one badge is how a legend starts lying. A badge rather than a colour or shape, because both of those already carry `kind` and trade is orthogonal to it. Original report: **The Atlas never reads a place's `shop` field.** Grepped 2026-08-27: `world_map.gd` mentions "shop" only as a KIND (`KIND_MARK`, `KIND_LABEL`), never `l.get("shop")`. So a settlement or tavern that carries a vendor shows no trade mark and the player must travel there to find out. `merchant_window` matches `shop` against `here` and works fine; the map simply never asks | P2 | S |
| AT-8 | **DONE 2026-08-27.** Extent is a Voronoi over the region hearts, solved analytically IN THE SHADER rather than baked to an index texture — a 96x64 index map steps in 7 px blocks at the Atlas's own size and worse as you zoom, while the analytic boundary is exact at every magnification for less work. Each heart's distance field is warped by its own fbm offset, because a plain Voronoi over three sites draws dead-straight radials that read as debug wireframe. The edge is drawn in INK, not the region hue: the first version took its colour from the hue and gave a saturated green hairline that shouted over a muted map. The colour belongs to the area, the line belongs to the map. Fog-gated by reusing `_region_anchor`'s INF, so a tint appears exactly when its name does. Original report: **Regions have no extent.** They are real in data — name, lore, biome, position, GM-chartered via `[[region]]` — but `_draw_regions` draws only floating letterspaced text. No boundary, no tint, no area; the sole spatial expression is dimming everything outside a focused one. "Different regions" currently reads as words lying on grass. Now that terrain is data, a region can own the cells nearest its heart (a Voronoi assignment over the terrain grid) and be drawn as a tint and an edge | P2 | M |
| AT-9 | **Hovering a place gives 80 characters of raw lore and nothing else.** `world_map._draw` prints `lore.left(80)` as bare text — no title, no kind, no vendor, no quest state, no visited/unvisited. There is no click-for-detail and no player notes. The pins already know all of it | P3 | M |
| PY-29 | **The cyber armoury is written but not painted, and the naming wants a redline first.** `FAMILY_FORMS["cyber"]` in `world_compiler.gd` replaces the era-locked forms for a cyber world — 7 weapon families and 7 slots, ~30 ids: `monoblade`, `arc_sabre`, `shock_baton`, `shock_lance`, `service_pistol`, `smart_rifle`, `scatter_gun`, `frag_disc`, `emp_charge`, `deck`, `drone_rig`, `mono_whip`, `visor`, `rebreather`, `crash_helm`, `collar_rig`, `grip_gloves`, `cyber_digits`, `cargo_pants`, `shock_leggings`, `shin_plates`, `street_boots`, `mag_boots`, `blade_runners`, `riot_shield`, `field_emitter`, `holdout_blade`, `stim_kit`. **Those are Claude's words, not the game's.** <br><br>**Do the read BEFORE the bake, not after.** `_stage_parts` paints one icon per form × material (embervale owed 267, so ~1.2 h of GPU per world) and every icon is keyed by its FORM ID — renaming `monoblade` after the bake orphans its icons and costs the hour twice. <br><br>Then: `rebake_charts.tscn` is the pattern for a targeted re-bake — `bake_worlds` skips a POPULATED world outright, so it will not repaint anything on its own. The other five families (steam, norse, pirate, everyday, space) are unwritten and want the same read | P2 | L |

### The fifth leaking prefix, found while fixing PY-16

| id | what | pri | size |
|---|---|---|---|
| PY-28 | **FIXED 2026-08-24 (63512f6).** Filed as nine hand-spelled sites; it was FOURTEEN, and working from Invariants.md turned up a SIXTH leaking prefix nobody had noticed: `foe-`, whose prompt carries `subject_style("char")`. All six prefixes go through `Art.*_key()` now. Mutation-tested. Original report: **`npc-` keys are not world-scoped, and the prefix is hand-spelled in nine places.** `2b1aee9` fixed exactly this for `race-`, `item-`, `beast-` and `map-`: the PROMPT carries `world_flavor()` but the KEY did not carry the world, so the first world to paint a name owned it everywhere. `npc-` was missed. Its prompts are world-flavored too — `lore_book.gd:209` appends `Art.world_flavor()`, `game.gd:2703` picks a style word by world id — and the key is built by hand at nine sites (`art_cache` ×4, `campaign_forge`, `persona_forge`, `lore_book` ×3, `game.gd`), which is the same duplication that let five spellings of `"item-" + nm` drift apart. **Two things make it more than a repeat:** (1) `Compiler.roster_art(world_id, key)` parses the slug back out of the key, so it needs the `fam_base` treatment `beast-` got; (2) it carries a DESIGN question the others did not — two campaigns in different worlds with an NPC of the same name would currently share one face, and whether that is wrong is a call about whether a name is an identity. Route every site through an `Art.npc_key()` once that is decided | P3 | M |

### The skin stops at the surface — found by re-reading the session, then the code

Three things looked wrong in the screenshots and all three were real. Chasing
them found one shared cause: **the world skin dresses the UI and the vendor, and
almost nothing underneath it.** These are filed separately because they are
separate fixes, but PY-22, PY-23 and PY-27 are one story.

| # | Item | P | E |
|---|---|---|---|
| PY-23 | **MECHANISM FIXED 2026-08-24 (f3d56f8); FIVE FAMILIES AND A BAKE REMAIN.** Not a Worldsmith job — forms are handcrafted constants (89 of them), taken from the seed on purpose because the 8B collapsed on the ask. A family may now REPLACE its era-locked forms and inherits the rest; `cyber` is authored as the worked example and the check bans every era-locked shape from it. **Still open:** (1) the cyber naming is Claude's voice, not the game's — wants a redline; (2) steam, norse, pirate, everyday and space are unwritten; (3) **making any of it visible costs ~1.2 h of GPU per world**, because `_stage_parts` paints an icon per form × material (embervale: 267 owed). None of that GPU has been spent. Original report: **Every world ships the identical 77 item forms, and all of them are medieval.** neonspire, brasshaven, everyday, fimbulreach and embervale each carry the same list: `halberd, mail_chausses, kite_shield, coif, crossbow, greaves, glaive, war_axe, breastplate, jerkin…`. **Zero cyber forms in Neon Spire** (no pistol, rifle, deck, drone, nano, visor — searched), and *Everyday*, whose own card reads "no magic, no chrome — just real people, real days, real talk", ships halberds and mail chausses. Materials are the same story — Neon Spire's are `aetherstone, brine_iron, drakon_skin, frostbite_mail, veldor_steel`. The Backlog already records that weapon *forms* stopped being the seed's job on purpose ("30 handcrafted weapon shapes across 7 families now always apply"); the consequence, unrecorded until now, is that a non-fantasy world has no non-fantasy gear to give | P2 | L |
| PY-26 | **FIXED 2026-08-24 — VERIFIED BY EYE.** Two bugs stacked. (1) The chart asked EVERY world for "open country — terrain, water, forest, hills and coast", so a vertical megacity rendered as a neon river valley; ground is per-family now and the repainted Neon Spire chart is dense blocks, arterials, bridges and spires. (2) The prompt FORBADE rather than described — and `ensure_item_icon`'s RCA is about this exact prompt ("the chart bake proved that at scale, producing a painted city and two misspelled cartouches from a prompt that forbade both"). Eighth time today a measured lesson existed and had been applied in one place only. **CORRECTION, 2026-08-25 — the fix does not reach a COMPILED world.** `world_map` draws `Compiler.chart_art()`, the BAKED `worlds/<id>/art/chart.png`, and only falls back to the cache when the pack has none. Neon Spire is compiled and ships a baked wilderness chart, so the game still draws a river valley; the city chart verified by eye was `chart-neonspire.png` in the CACHE, which is the uncompiled path. Every shipped world needs its chart re-baked for this to land — GPU, and not spent. Caught by a windowed screenshot of the actual map, which is the only thing that could have. **Residual, measured:** text still appears on the chart. Positive description beat forbidding but does not suppress lettering; the real route is `/sdapi/v1/txt2img`, the only endpoint that accepts a `negative_prompt` — see Invariants.md "Known limits". Original report: **The chart paints wilderness for a metropolis.** The minimap during a scene set in The Undercity and The Sprawl shows a neon-tinted river valley — sinuous water and landmass, no streets or blocks. That is the chart plate behaving as designed (the Atlas notes say it "paints terrain, water and coast and nothing that claims a position"), which is the right call for Embervale and the wrong picture for a city. A world whose `kind` is a metropolis needs district shapes, not a coastline. Related and already half-known: `mini_map.gd`'s own header says it "floats above the transcript … and costs the player words", and the fix taken was to hide it when there is no chart — not to stop it overlapping (see PY-5) | P3 | M |
| PY-27 | **ALREADY DONE — the row was stale, not the code.** The rail opens on **The Campaign**, which is itself two steps with the world first (`_camp_world`); the hero is stage 1. The fix carries its RCA at `adventure_forge.gd:16` and was already GUARDED: `self_check` asserts the forge does not ask for the hero before the world, AND that the chosen world is PUBLISHED before the hero forge spawns (without that, `world_flavor()` reads whatever was last played). Recorded so the next pass does not re-investigate it. Original report: the rail opened on "The Hero" and committed kit, body and portrait before the game knew the world | P2 | M |

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

**CORRECTION 2026-08-27 — that objection died with the painting.** It was right
while the chart was generated art: a street tier would have meant *authoring*
the data and then *painting* it, twice per place, forever. Neither is true now.
A town plan is generated data seeded from `world_id + place name`, exactly as
`WorldTerrain` is — and it inherits its SITE from the world terrain cell the
place stands on, so a town on a coast cell gets a shore that agrees with the
world map for free. That agreement is the whole dividend of inverting the
pipeline, and it is unavailable to any authored or painted approach.

See AT-5 below. Nothing in the repo has to be reused-or-invented first: there is
no dungeon or interior system today (`interior` is art-prompt strings and a
battle-map biome label; `dungeon` is one icon name in `world_skin`).

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
