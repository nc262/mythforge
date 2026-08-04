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
