# Ritual: Unrolling the Map

*U3 — the living map. Emotions: wonder · exploration · scale.*

## 1. Experience

You unroll a chart on the table and lean over it. It is not a diagram — it is
the world seen from a hawk's height: parchment, ink, cloud shadows drifting
across the land, a compass rose. Places you have walked glow warm and named;
the rest of the world sits under fog, marked only by rumor. Somewhere, a
quest pulls at you — its destination beats like a heart on the paper.
Choosing where to go next should feel like adventure, not selection.

## 2. The ritual beats

| Beat | What happens |
|---|---|
| **Anticipation** | The map opens through the shared window ritual (world dims) |
| **Reveal** | The chart with drifting cloud shadows; visited places lamp-lit, the unknown fogged |
| **Focal point** | You-are-here: a gold ring breathing on your current place |
| **Interaction** | Wheel zooms into the paper (toward the cursor), drag pans; hover a known place → its lore + an animated dashed route from here; click → travel |
| **Reward** | Quest destinations pulse gold with a ✦; arriving somewhere new burns its fog away forever (the map remembers) |
| **Graceful exit** | Close the map — the scrim lifts |

## 3. UX flow

- **Zoom**: wheel in/out (1×–2.6×), centered on the cursor; pan by dragging;
  map never shows its edges (offset clamped).
- **Fog of war**: unvisited places are shrouded — dark cloud blob, gray dot,
  name hidden ("somewhere unknown"), no lore, still clickable (the road is
  how you learn). Visited set persists in world state (`world.seen`).
- **Quest pull**: active quest text is matched against place names — matches
  get a gold ✦ and a slow pulse.
- **Route preview**: hovering a place draws an animated dashed line from
  here to it, curving gently.
- **Living paper**: two soft cloud shadows drift; the compass rose sits in a
  corner; the here-ring breathes. All motion honors reduce_motion.

## 4. Wireframe

```
┌──── 🗺 Embervale ─────────────────────────────┐
│ ~cloud~          ✦(quest, pulsing)            │
│   ●Emberhollow Inn      (fog)◦?               │
│        \··routes··                            │
│   ◎you-are-here (breathing ring)   (fog)◦?    │
│              ~cloud~                🧭compass  │
└───────────── wheel zoom · drag pan ───────────┘
```

## 5-8

Mockup = screenshot harness on the demo world. Implementation entirely in
`world_map.gd` (+ `world.seen` written on travel in game.gd). Polish: pulse
phases via one `_process` clock; clip_contents (the overdraw lesson).
Docs: Features.md, KnownIssues if anything deferred.
