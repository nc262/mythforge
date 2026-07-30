# Save System

Saves are files. There is no server, no session, no sync and no slot the player
has to remember to press — the game writes on every mutation and a closed window
loses nothing.

## Where it all lives

| What | File |
|---|---|
| an adventure's whole state | `user://saves/<adventure-id>.json` |
| the shelf (which adventures exist) | `user://saves/adventures.json` |
| worlds, GMs and personas, shared by all adventures | `user://saves/_global.json` |
| campaign memory (beats + their vectors) | `user://memory/<adventure-id>.json` |
| chapters (narrated save-points) | `user://chapters/<adventure-id>.json` |
| banked heroes | `user://heroes.json` |
| generated art + sidecars | `user://art/`, `user://tiles/` |
| settings (chosen narrator, UI prefs) | `user://session.cfg` |

## The state kinds

One save file holds a dictionary of **kinds**:

```
sheet · inv · combat · clock · quests · codex · bmap · gm · world · notes
```

`GameState.save_kind(kind, value)` sets one and flushes the file. A kind that is
absent — or explicitly `null` — falls through `_merged` to its default, which is
what makes wiping an adventure a matter of nulling its kinds rather than
deleting anything.

## Write, then rename

Every write goes to a temp name and is renamed into place. Killed mid-save, a
half-written file is simply not there yet; without this, a truncated JSON
replaces a good save with one that still parses — as an empty campaign.

## The test drawer

Harnesses play `dm-embervale-freeroam`, a **real** adventure id, on purpose:
they are meant to exercise the shipped scenes. So `save_dir()` returns
`user://saves_test` whenever `Api.test_mode` is on, and `reset_test_saves()`
empties it at boot.

Both halves are load-bearing. Without the separate drawer, the first headless
run overwrote a live save. Without the reset, a run was seeded and then read
back whatever the *previous* run had left — three checks passed against state
nobody had set up.

## Chapters

`Chronicle.save_chapter()` asks the narrator to summarize the tale so far into
`{title, story_so_far, world_changes}` and appends it to the adventure's chapter
file. The Chronicle screen lists them; the recap card on resume is built from a
memory recall, not from a chapter.

## Flows

- **Continue** — the title screen shows the last adventure with hero · level ·
  day; more than one live tale opens the save-file screen with a latest badge.
- **Continue vs New game** — replaying an adventure either resumes it or nulls
  its state kinds for a fresh start. Other adventures are untouched.
- **Recap** — "Previously…" on resume, from `Chronicle.recall()`.

## Not built yet

Campaign export/import (`{slug}.world.json` for worlds, a JSON bundle for a
campaign) · multiple hero slots per adventure · a 🏁 complete badge.
