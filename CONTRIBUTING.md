# Contributing to Mythforge

Focused changes, easy to review, easy to test. One bug fix or one feature per
pull request; avoid broad rewrites and formatting-only churn unless the issue is
specifically about structure. For anything large, open an issue with the
approach first.

## Setup

Windows, Godot 4.7, and about 5 GB of models.

```powershell
git clone <this-repo>
cd <repo>
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1   # runtime, models, image engine
.\play-mythforge.cmd
```

There is no server, no database and no virtual environment to activate. Python
exists only for the tooling in `scripts/`, which a player never runs.

## Running checks

The five harnesses are in [godot/docs/Testing.md](godot/docs/Testing.md). The
minimum for any change under `godot/`:

```bash
godot --headless --path godot res://tests/self_check.tscn
godot --headless --path godot res://tests/click_driver.tscn
godot --headless --path godot res://tests/ui_playthrough.tscn
```

If you touched a model call, also run `local_stack` and `bench_gm` — they are
the only harnesses that can tell you the answer is *good* rather than merely
well-shaped.

**Re-export after any `godot/**` change** before playtesting, or you are testing
a stale exe.

Say in the PR what you ran. If you could not run something, say that too.

## The rules that are not style preferences

1. **The engine decides; the model narrates.** A model reply may propose
   mechanics through `[[tags]]`. It may never state a dice result, an HP total,
   or a success. Every mutation goes through a typed tag handler.
2. **No second path.** If the narrator model is missing, the game says so. A
   quieter fallback hides the fault instead of fixing it, and the fallback ends
   up being the path everyone actually runs.
3. **Never let one model call both invent and serialise.** A grammar and a
   sampler chain replace each other in NobodyWho, so a schema-constrained call
   runs with no sampler at all. Think in prose, then serialise. Read
   [godot/docs/LocalLLM-Tuning.md](godot/docs/LocalLLM-Tuning.md) before
   touching a model call — it has the measurements.
4. **Assert what the failure looks like**, not what a good answer looks like.
   Three metrics in this repo's history passed broken output confidently.

## Code conventions

See [docs/code-style.md](docs/code-style.md). In short: a new system is a new
autoload registered in `project.godot` and documented in
[Architecture.md](godot/docs/Architecture.md); scene scripts orchestrate UI and
do not hold rules; formulas live in `Rules`.

Mark deliberate simplifications with a `ponytail:` comment naming the ceiling
and the upgrade path, and add a row to
[TechnicalDebt.md](godot/docs/TechnicalDebt.md) in the same commit.

## Visual changes

The game has an intentional visual language, and it is written down:
[DesignSystem.md](godot/docs/DesignSystem.md) is the contract, with one doc per
ritual under `godot/docs/rituals/`.

Before submitting anything that changes what the game looks like:

1. **Run it and look at it.** Harnesses assert screens are reachable; they do
   not assert a screen is right.
2. **Attach a screenshot.** `tests/screenshot.tscn` will take one.
3. **Reuse the tokens.** Colours, spacing and radii come from `Ui`. Do not
   introduce new literals.
4. **No emoji in the UI.** Functional glyphs come from the drawn icon library
   (`ui/myth_icon.gd`); garnish is deleted.
5. **Do not add a parallel component.** Extend the `Myth*` one that already
   exists.

If you are unsure whether a change is visual, it is.

## Commits

[Conventional Commits](https://www.conventionalcommits.org):
`type(scope): summary` — `fix`, `feat`, `refactor`, `docs`, `test`, `chore`,
`ci`. Short, imperative subject; the "why" goes in the body when it is not
obvious.

## Issue reports

Include: what you ran (source or installer), your GPU and VRAM, exact steps to
reproduce, expected vs actual, and any logs. For anything about the narrator's
behaviour, include which `.gguf` is in `user://models` — the model matters more
than anything else in the report.

## Security

Do not post secrets, private logs or personal documents in issues or pull
requests. For security reports, follow [SECURITY.md](SECURITY.md).
