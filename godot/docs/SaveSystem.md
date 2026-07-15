# Save System

## Layers
1. **World state (continuous)** — every mutation PUTs its kind to
   `/api/characters/studio/state/{cid}/{kind}`; the JSON store on the
   backend is the single source of truth. Closing the app mid-fight loses
   nothing.
2. **Transcript** — the chat session (`/api/session`, `/api/history/{sid}`);
   per-adventure session ids map in `user://session.cfg [sessions]`.
3. **Campaign memory** — embedded beats server-side (per owner+cid).
4. **Snapshots (save slots)** — backend `/snapshot` summarizes the last 60
   messages into `{title, story_so_far, world_changes}`; list/continue via
   the Chronicle. **Client wiring is an M2 row** (endpoints live, UI absent).

## Flows implemented
- **Continue** (title): last adventure with hero · level · day caption;
  several live tales → the save-file screen (latest badge).
- **Continue vs New game** on replaying an adventure: new game archives the
  session (`/archive`), clears the map entry, nulls the adventure's state
  kinds — old save recoverable server-side, other adventures untouched.
- **Recap** on resume: "Previously…" card from memory recall.

## Wipe semantics
`{"value": null}` per kind; `GameState._merged` treats null as absent →
defaults → hero forge gates the fresh start.

## Roadmapped
Chronicle UI (snapshot cards + continue-from-here + campaign export/import
JSON) · world export/import files (`{slug}.world.json`) · 🏁 complete badge
metadata · multiple hero slots per adventure.
