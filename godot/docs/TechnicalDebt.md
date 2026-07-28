# Technical Debt

Deliberate shortcuts, each with its ceiling and upgrade path. (Grep
`ponytail:` in sources for in-code markers.)

| Debt | Where | Ceiling | Upgrade path | When |
|---|---|---|---|---|
| ~~Implicit game modes~~ PAID M1: `Mode` FSM owns flow; `_streaming` remains as a local mirror of `Mode.busy` until the game.gd split | state_manager.gd | — | remove `_streaming` alias during M2 split | M2 |
| game.gd is a god-script (~1.3k lines: chat+combat UI+sheet+shop+forge) | scripts/game.gd | hard to grow M2/M3 features | split: chat_view / panels / dialogs as child scenes under the FSM | M1–M2 |
| State writes are fire-and-forget PUTs, no debounce/retry | GameState.save_kind | a dropped PUT silently loses a mutation until next write of that kind | write-through queue with retry + dirty flags (web had 600ms debounce) | M2 |
| Enemy stats by name-regex tiers + level multiplier | Combat.enemy_hp_guess | flavorless foes vs rich bestiary data | stat blocks derived from bestiary tiers; per-world threat tables | M2 grid |
| Companion kit generic (Fighter, AC 13) | GameState.add_companion | wrong flavor | class inference from codex role (web _companionClass) | M2 |
| No debounced sheet edits (immediate PUT per mutation) | GameState | chatty under rapid UI edits | same write-queue as above | M2 |
| Shop is a chat bubble, not a window; markup is session-local | game.gd _open_shop | fine until merchant window (M3) | merchant mode in FSM + window | M3 |
| Art cache never evicts; portraits keyed by name slug | art_cache.gd | disk growth; renamed NPCs re-generate | manifest with sizes + LRU; key by codex identity | M3 |
| SFX are 4 synthesized wavs, no bus/volume setting | sfx.gd | can't mix music later | AudioBus layout + settings volume sliders | M3 |
| Tests hit the live backend (e2e/playthrough) | tests/ | can't run in CI without the stack | mock SSE server fixture for CI lane; live lane stays for the box | M3 |
| cstories simplified into world graft (no global registry) | main_menu campaign smith | built-in worlds' crafted campaigns persist only as dm- templates | port `_global/cstories` map | M2 |
| Envelope rebuilt as strings each turn | prompt_composer.gd | fine at 2.5k chars | context budgeter when sections grow (memory of web: llm num_ctx 8192) | M4 |

Paying debt follows the same workflow as features: plan → document → land
with a check. New shortcuts must add a row here in the same commit.

- ~~**Terrain sampler is a color heuristic** (combat.gd bake_terrain)~~ — **paid, R10.** Deleted along with the `[[terrain]]` GM tag. `lay_battlefield()` builds the field from roles and the painting follows the field, so there is nothing left to misread. See [Terrain.md](Terrain.md).
- **Object tiles carry an opaque dark-grey background**: a boulder tile pasted into a snowfield brings its own grey square. Squat objects that generated their own ground fringe (firepit, chasm) blend; the rest do not. Upgrade path: composite the object over the cell's ground role at draw time, or key the flat background out at bake time.
- **Mode drift self-heal** (game.gd _can_fight): combat clicks force-enter Combat if a fight is active but the FSM drifted (RCA: fight started from Dialogue state locked every combat action, silently). Real fix is declaring Combat as a legal target from every in-game state.
- **world_map still carries its own pan/zoom** (predates MythCamera): duplicate of ui/myth_camera.gd. Upgrade: adopt MythCamera in world_map.gd next time that file is touched.
- **Both forges duplicate the ~60-line stage scaffold** (rail/title/nav/clear): extract a ForgeFlow base when a third staged experience appears.
- **SVD generation is ~35min/clip** under the stack's ZLUDA-stability flags (--use-quad-cross-attention): quad attention crawls on temporal layers. The video is pre-built and shipped, so players never pay this; regenerating (scripts/make_opening_video.py) does. Lever if ever needed: a separate ComfyUI launch profile with pytorch attention for video jobs.
