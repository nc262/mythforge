# Coding Standards

## Language & style
- GDScript, Godot 4.7, tabs, typed where inference fails (`var x: bool = …`
  when the RHS is Variant — untyped-inference is a hard parse error).
- One system per autoload; scene scripts orchestrate UI only.
- Names: snake_case funcs/vars, PascalCase classes/autoloads, `_private`.
- Comments state constraints the code can't ("server is truth", "HTTPRequest
  can't stream"), never restate the line. Deliberate shortcuts carry a
  `ponytail:` marker naming the ceiling and the upgrade path.

## Hard rules (learned the expensive way)
1. **Server is the source of truth.** Every state mutation goes through
   `GameState.save_kind`. No client-only persistence of game state.
2. **SSE must use raw `HTTPClient`** — `HTTPRequest` buffers whole bodies.
   Byte-buffer line splitting (UTF-8 chars straddle chunks).
3. **Never trust model prose for state.** Mutations happen only via typed
   tag handlers. Prose regexes may *ask* the player (roll bar), never write.
4. **Escape everything into BBCode** (`_bb`: `[` → `[lb]`) — model text can
   inject markup.
5. Autoload names must not shadow Godot classes (`Skin` broke; hence `Ui`).
6. Python patch scripts against the codebase run with `-X utf8` (em-dashes
   corrupt via cp1252 stdin otherwise).
7. `char` is a GDScript built-in — not an identifier.
8. Every stream path sets `_last_player_msg` (memory beats) and re-enables
   input on done AND on watchdog abort.

## Definition of done (per feature)
- [ ] Compile-clean: headless scene run shows no SCRIPT ERROR
- [ ] `tests/self_check.tscn` green (extend it when logic is added)
- [ ] Live path exercised (e2e/playthrough harness or manual) when it
      touches streaming/state
- [ ] Backlog.md updated if it opened or closed work; Architecture.md if a boundary moved
- [ ] Committed with a message that explains *why*
- [ ] Claude memory updated when an architectural decision was made

## Testing philosophy
Non-trivial logic leaves one runnable check behind. The three harnesses
(unit / live-e2e / full playthrough) are the regression net — a change that
can't be verified by one of them gets a new check, not a pass.
