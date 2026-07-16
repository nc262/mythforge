# Known Issues

| # | Issue | Impact | Workaround | Fix plan |
|---|---|---|---|---|
| 1 | ↻ retell function exists but has no visible button yet | Can't retell without dev knowledge | — | M1: input-row button |
| 2 | Combat attack rolls don't play the dice-moment overlay (tracker rolls are internal) | Less drama in combat | — | M2 grid pass |
| 3 | `Rules.attack_mod` couples to `GameState.inv()` when inv omitted at call sites; sheet-only callers must pass inv explicitly | Subtle wrong bonus if forgotten | pass inv everywhere (done at known sites) | FSM refactor adds a typed context object |
| 4 | Companion recruit assigns generic Fighter/AC13 kit regardless of NPC role | Flavor mismatch | GM narration carries flavor | M2: class inference from codex role |
| 5 | Multiple missing world key arts generate sequentially on menu load; on a cold cache the GPU queue can lag chat image requests | Slow first menu | wait, or play (per-world guard exists) | M3: art queue with priority lanes |
| 6 | `_show_saves` fetches state per save serially | Slow with many saves | few saves today | batch endpoint or parallel awaits |
| 7 | Session map lives in `user://session.cfg` — deleting it orphans (not loses) server sessions | Continue caption resets | replay adventure → Continue choice reappears | M2 snapshots UI makes recovery visible |
| 8 | Backend auth uses a single shared cookie file per OS user | Fine solo; multiplayer later | — | M4 party work |
| 9 | Harness screenshots need a windowed run (headless can't render) | CI can't do visual diffs | local screenshot harness | acceptable |
| 10a | Pack leather surface reads flat at a glance (stitch detail subtle at 1x) | polish gap vs the five pillars | — | material refinement pass in U1.1 |
| 10 | Godot 4.7 shutdown prints benign RID/StringName leak noise in headless runs | Log noise only | grep-filtered in harnesses | upstream |

Retired issues live in git history; resolved rows are deleted here only
after the fix ships AND the harness covers the regression.
