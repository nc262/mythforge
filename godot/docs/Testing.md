# Testing

Five headless harnesses over the game, plus one over the *published download*.
The first three are offline and deterministic; the next two drive the real model
on the real GPU and are the only ones that can tell you an answer is *good*
rather than merely well-shaped.

```bash
GODOT=".../Godot_v4.7-stable_win64_console.exe"

$GODOT --headless --path godot res://tests/self_check.tscn      # SELF-CHECK OK
$GODOT --headless --path godot res://tests/click_driver.tscn    # CLICKDRIVE OK
$GODOT --headless --path godot res://tests/ui_playthrough.tscn  # PLAYTHROUGH OK
$GODOT --headless --path godot res://tests/local_stack.tscn     # real models
$GODOT --headless --path godot res://tests/bench_gm.tscn        # latency + repetition
```

**Re-export after any `godot/**` change** or the exe under test is stale.

| Harness | What it can prove | What it cannot |
|---|---|---|
| `self_check` | rules math, tag parsing, prompt composition, FSM legality, persistence round-trips | anything about how the game looks or feels |
| `click_driver` | every station is reachable **by a mouse** — it asks which control is topmost at a point, the same question a click asks | that the screen behind the click is correct |
| `ui_playthrough` | a scripted game through the real scenes: loot → equip → damage → combat → level-up → save | quality of the narration (there is none — replies are scripted) |
| `local_stack` | the model actually answers, with schemas honoured and concurrent calls kept apart | timing under load |
| `bench_gm` | turn latency and repetition across many turns | correctness of the rules underneath |
| `clean-room` | that a **stranger** can fetch all 13 downloads a first run needs | that any of it runs — no GPU, no Vulkan, no Windows in the container |

## The two that need a window

Headless uses a dummy rasterizer, so every capture comes back blank. These run
**windowed** and answer questions no assertion can:

```bash
$GODOT --path godot res://tests/doll_shot.tscn     # every loadout, cloth, forged garment
$GODOT --path godot res://tests/jiggle_shot.tscn   # the body knobs, the springs, a gesture
$GODOT --path godot res://tests/gesture_shot.tscn  # all 95 clips as contact strips

ONLY=mf BARE=1 $GODOT --path godot res://tests/gesture_shot.tscn   # one library, no sword
```

`ONLY` narrows the audition to one library while iterating on it, and `BARE`
drops the weapon — an emote judged with a blade in the hand is judged with the
blade in front of it, and a wave holding a sword is not a wave.

## The one that needs a window AND asserts

```bash
$GODOT --path godot res://tests/body_audit.tscn    # BODY-AUDIT OK
```

`body_audit` is the answer to a real failure of method: the MakeHuman candidate
body was judged by LOOKING at renders for most of a day. That is not a question
with a wrong answer. A bare figure on a black background hid a uv error
completely, and the one measurement taken by hand scored a **known-good pairing
at 57% broken**, because a nearest-surface normal test is not defined for an
open garment like a tunic.

So it runs the SHIPPING body first as a control. A check the shipping body fails
is a check that is wrong, not a body that is — which is the property that makes
the thresholds trustworthy rather than argued about.

| Goal | Asserts | Pack | MakeHuman |
|---|---|---|---|
| G1 RIG | every bone the pack body has, name for name | 75 | 75, 0 missing |
| G2 SKIN | no vertex left unweighted — one is a spike through the figure, and only in some poses | 0/7,281 | 0/14,517 |
| G3 STANCE | height and span within 6% of the pack body | 1.820 / 1.859 | +0.6% / +4.0% |
| G4 EYES | the eye mesh sits inside the skull rather than floating off it | ok | ok |
| G5 MASKS | a mask per worn garment, present **and** neither blank nor solid | 4 sane | 4 sane |
| G6 CLOTHED | **no skin visible through cloth** | 17 px | 317 px |
| G7 INTACT | **no skin deleted where nothing covers it** | 727 px | **2,769 px — unmet** |

**G6 and G7 use no colour heuristic at all**, which is what makes them worth
believing. G6 renders the dressed figure twice — once normally, once with the
skin mesh HIDDEN — and counts the pixels that change inside the torso. A hero
whose clothes cover them looks identical either way, because nothing of them was
showing; every changed pixel is skin that was visible through cloth, by
construction. G7 is its mirror: skin the bare figure draws, the masked figure
does not, and no cloth replaced — a hole.

G6 earned its place on the first run, catching the candidate at **5,722 px**
against the control's 17. That settled in one run what a day of renders could
not: the defect was SKIN, not the mangled belt it equally looked like.

**G7 is eroded by one pixel, and the shipping body is why.** Counted raw it
scored the pack at 1,491 — and the pack is the one figure known to be correct, so
that was the CHECK being wrong, not the body. The pixels were a one-deep rim:
along every garment edge the cloth and skin silhouettes land a pixel apart and
antialiasing puts both at partial alpha. A hole you can see is a region, so
requiring the four neighbours to qualify erases the rim exactly.

## What the audit proved about the candidate, and it is not what was hoped

`MASK_NEAR` looked like the fix for G6 and a sweep killed that idea:

| `MASK_NEAR` | G6 ≤400 | G7 ≤900 |
|---|---|---|
| 0.05 | 2,346 ✗ | 1,953 ✗ |
| 0.06 | 1,042 ✗ | 2,232 ✗ |
| 0.07 | 610 ✗ | 2,514 ✗ |
| 0.09 | **317 ✓** | 2,769 ✗ |
| *pack* | *17* | *727* |

The two move in opposite directions and **no value passes both** — at the
tightest setting G7 is still 2.7× the control. The threshold is not the problem;
it only chooses which failure to have. The garment refit is, and that is where
the next work goes.

So the MakeHuman body is marked a **candidate** in the harness: its goals are
measured and printed like any other, it does not fail the run — nothing in the
game loads it, and a permanently red suite is one people stop reading — and the
summary always states how many candidate goals are unmet, so adopting it means
making those numbers pass first.

`gesture_shot` exists because **the clip names lie**. `Idle_Rail_Call` might be
a wave or a man shouting over a fence; `NinjaJump_Start` might be a skip or it
might carry the hero out of frame. It renders six frames evenly across every
clip in the library, framed ONCE on the standing pose and never re-framed — so a
clip that travels shows the figure walking off the edge, which is exactly what
picking off names cannot tell you. Run it whenever the animation library
changes; the gesture table in `RIGS` is chosen from its output.

`jiggle_shot` does two things. It renders each soft-tissue knob at 0 / 50 / 100,
bare and dressed, from the angle that shows it — the only test that could have
caught the old `chest` knob, which widened a whole ribcage, passed everything,
and never made a chest.

Then it measures the springs, and **the way it does that is the point**. The
obvious version — run the idle twice, springs on and off, and diff the frames —
does not work: two real-time runs never land on the same animation phase, so the
whole silhouette lights up and the jiggle is lost inside it. It was tried, and
the difference image was a glowing outline of the entire figure.

So the pose is **frozen** and the figure is turned instead. Springs-off is then
perfectly static, every pixel that moves is the simulation, and the number means
what it says. It asserts on peak displacement, because a simulator that is wired
up and inert passes every other check in the repo: the node exists, the bones
resolve, and the strip renders sixteen identical frames.

Image engine, when a harness needs art:

```bash
pwsh scripts/start-image-sdcpp.ps1
```

## The clean room

```bash
pwsh installer/clean-room/run.ps1              # the published release
pwsh installer/clean-room/run.ps1 -Tag v1.0.0  # any tag
```

Docker, the stock PowerShell image, no Dockerfile. The container is the *point*,
not a convenience: it has no GitHub credentials, no `gh`, no browser session and
no cached tokens, so it fetches the release the way a stranger's machine will.
Every one of these URLs works on the dev box even when the release is private —
which is exactly the failure it exists to catch.

It checks status, size floor, size **ceiling**, and the leading magic bytes,
because a deleted asset or a typo'd name returns a 200 with an HTML error page
that content-length alone happily calls a pass.

**Why it exists.** On 2026-08-04 the repo's `latest` release was v1.0.0: a
1525 MB pre-split exe and six world packages that predated the tile bake, ~220 MB
lighter each. Every harness was green, the code was correct, and anyone following
the README got a stale game with no terrain. The fault was in the *published
artifacts*, which nothing in the repo builds or inspects. Run against v1.0.0 the
clean room fails 7 of 13 — the ceiling catches the bundled exe, the floor catches
all six tile-less worlds.

## What CI can honestly check

The real gates need the engine, ~5 GB of models and a GPU, so they run here, not
on a runner. CI checks that the Python and PowerShell tooling parses and that
nothing has reintroduced a server: an `"/api/` string in any `.gd` file, or a
launcher starting a web app, fails the build.

## Verifying a SHIPPED build

The harnesses all run from source, where `res://baked` exists whatever the
export settings say. So the one failure they structurally cannot see is a build
that ships without its worlds — and it fails silently: the game boots, the menu
draws, and New Adventure is empty.

```
Mythforge.exe --headless --mf-worlds
```

Prints the search paths, lists what it found, opens each archive, checks for
`world.json`, and exits non-zero if any of that fails. Run it on every artifact
before publishing; `installer/bootstrap.ps1` runs it after a first-run install
for the same reason.

## Two laws that came from being burned

**Assert what the failure looks like, not what a good answer looks like.** Three
separate metrics passed broken output: a vocabulary-overlap score rated three
identical sunset openings 19 % "OK"; a word splitter dropped words under four
characters, so "air" never reached the atmosphere detector; a sanity check
accepted `colors`, `dominant` and `#:7A288A` as materials. Each was measuring the
wrong thing confidently.

**A test that cannot tell whether the feature is plugged in is not testing the
feature.** The GM-model check re-implemented the ranking inline and passed for
weeks while the picker it was named for wrote to a key nothing read.

## What has never been tested

**Nothing on this list.** The five gaps were closed on 2026-08-04 and each is
now driven in `ui_playthrough`:

| Area | What now runs |
|---|---|
| Spells in play | Every L1 slot spent to empty, the **refusal** that fires with none left, a cantrip that stays free, and the long rest that gives them back |
| Merchants | A buy debits and delivers · a purchase the hero cannot afford moves nothing · a sale credits and removes |
| The Lore Book over a long campaign | 30 discoveries across 6 categories, a re-told fact deduped, and the book rendered **full** rather than empty |
| Equip / unequip | Two weapons contesting one hand, unequip returning the slot, armour raising AC, a shield stacking on it, two rings filling two fingers |
| Tone knobs at their extremes | All five knobs at 0 and 100, silence at 50, five clauses composing into one line, and a named style leading it |

### Every one was verified by mutation

Passing on the first run proves nothing. Each feature was deliberately broken —
the slot guard removed, the affordability check bypassed, lore dedup disabled,
the second ring finger taken away, the knobs' high end silenced — and the run
had to fail. It produced **13 failures across all five**.

**The shop check failed that verification the first time, and its failure is the
lesson.** A successful buy tells the GM, which starts a stream; while it streams
`Mode.can("panels")` is false and the next action returns before reaching
anything. So the can't-afford case never ran the guard: gold was unchanged and
the item absent *because nothing happened*, and both assertions passed. It now
waits for the game to go idle and **asserts the precondition** — a vacuous pass
has to be a failure, or the test is decoration.

Closing these is harness work, not feature work — which is why they live here
rather than in [Backlog.md](Backlog.md).

## Manual playthrough (milestone gate)

1. Title → Settings: toggle SFX and reduce motion, back.
2. New Adventure → forge a world (pillars + refine once) → craft a campaign.
3. Hero forge → Session Zero → the opening scene streams token by token.
4. Sneak or persuade something → check tag → dice moment → consequence.
5. Pick a fight → tracker: attack, Next through enemy and companion turns, take
   a hit (sheet HP drops), win → XP → killing-blow narration.
6. Buy and haggle; equip; cast a levelled spell (a slot spends); short rest.
7. Get dropped to 0 HP → death saves both directions (stabilise / die → epitaph).
8. Quit mid-fight → relaunch → Continue: the fight resumes where it stood.
9. Continue next day → "Previously…" shows real events; the codex has the cast;
   ask the GM to recruit an ally → the ally fights in the next combat.
10. Companion chat from the cast → no HUD, pure conversation.

## Regression invariants (never break)

Tags never visible in narration · input always re-enables after done or abort ·
no state mutation without a typed tag handler · a dead hero cannot act · money
floors at zero · companion wounds persist · reduce-motion kills animations ·
the FSM never lets an action run in a state that blocks it.
