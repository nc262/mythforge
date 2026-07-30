# Code Style

Match the surrounding code. This captures the conventions already in the repo.

## GDScript (`godot/`) — where everything that runs lives

- **Class docstrings** (`##` at the top of a file) say what the thing is and, more
  usefully, *why it is shaped this way*. The codebase has a strong "here is the
  trap we hit" comment culture; preserve it when you add a workaround.
- **Comments explain why, not what.** A comment restating the line below it is
  noise; a comment naming the bug that line prevents is the reason the file is
  maintainable.
- Type hints on signatures (`func foo(x: String) -> Dictionary`). `snake_case`
  functions and vars, `PascalCase` classes, private helpers prefixed `_`.
- **One system per autoload file**, registered in `project.godot` and documented
  in [Architecture.md](../godot/docs/Architecture.md). Scene scripts orchestrate
  UI; they do not hold rules.
- **Formulas live in `Rules`.** If a number is computed, it is computed there and
  asserted in `self_check`.
- **No colour, spacing or radius literals in a scene script.** They come from
  `Ui`. No emoji anywhere that renders — functional glyphs come from
  `ui/myth_icon.gd`.
- **Every persisted write is write-then-rename.** A crash mid-save must not
  replace a good file with a truncated one that still parses.
- Deliberate shortcuts get a `ponytail:` comment naming the ceiling and the
  upgrade path, plus a row in
  [TechnicalDebt.md](../godot/docs/TechnicalDebt.md) in the same commit.

## Model calls

Read [LocalLLM-Tuning.md](../godot/docs/LocalLLM-Tuning.md) first. The rule that
governs all of them: **never let one call both invent and serialise.** Think in
prose with the tuned sampler, then use a small schema to give that prose fields.

Structured calls go through `LocalGM.complete_json()`, which owns the one shared
JSON worker — two callers on one chat node interleave into a single garbled
answer that still parses.

## Python (`scripts/`) — developer tooling only

A player never runs any of this. It bakes art, fetches engines and migrates
saves.

- Module docstring saying what it is and when you would run it.
- `argparse` for anything with options; sane defaults; new behaviour behind a
  flag whose default preserves the old behaviour.
- Type hints on signatures. `snake_case`, private helpers prefixed `_`.
- Absolute paths, or paths derived from the script's own location — never the
  caller's cwd.

## PowerShell (`scripts/`, `installer/`)

- Header comment: what it does, when to run it, how to undo it.
- **Idempotent.** Check before acting — test the port before launching, test the
  file before downloading. Every one of these doubles as a repair tool.
- Absolute paths. A privileged script says up front that it needs admin and what
  exactly it changes.
- Long-lived servers are launched detached, never as a foreground call that
  would block.
- Downloads are resumable (`curl.exe -C -`) — a 4.6 GB fetch over a bad line
  must not start over.

## Naming & data

- Shipped game data is JSON under `godot/data/` and is committed. Generated
  content goes under `user://` and never enters the repo.
- Art keys are structural: `<world_id>` · `hero-<cid>` · `npc-<slug>` ·
  `item-<slug>` · `map-<place-slug>` · `chart-<world_id>`. Derive them through
  `Art`, never by string-building at the call site — six readers rebuilding
  `"hero-" + cid` by hand is how a hero ended up with two faces.
