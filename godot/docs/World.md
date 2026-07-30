# World Systems

## Worlds
Three built-ins (extracted to `data/worlds.json` with lore, cast, stories,
locations, backdrop prompts): **The Embervale** (high fantasy), **Neon
Spire** (cyberpunk), **Everyday** (slice of life). Forged worlds (`cw-*`)
persist in `_global/cworlds` with the same shape + `custom: true`.

## The World Forge
Idea + five pillars (magic / technology / era / beasts / tone, with
suggestion chips + surprise-me) → the Worldsmith (two constrained-JSON
calls) → name, kind, tagline, lore, backdrop prompt, 5-7 locations, cast of
3 (with personas), 2 campaigns, 3 setting-specific creatures. Preview →
✎ refine (revises the full prior) / ↻ another take / create. Key art
generates on creation. Campaign smith (mode=story) grafts new campaigns
onto any world.

## Time, weather, world motion
7-step day clock (`clock` kind), per-world weather tables rolled each dawn,
timed conditions wane as hours pass; long rest sleeps to next dawn.
`[[time advance=N]]` from the GM; auto-advance every 3 turns is a parity
gap (FeatureMatrix). The **worldtick** endpoint ("Meanwhile…" off-screen
events between days) exists server-side — client wiring roadmapped M3.

## Scenes & art
Key art per world (menu cards, in-game backdrop from first breath); the
`[[scene place=…]]` tag repaints the backdrop as you travel; 🖼 conjures on
demand; NPC portraits generate from codex appearance anchors. All cached
under `user://art/`.

## Travel & atlas (M2)
Locations data is loaded (name/kind/lore/shop, x/y for the map). Planned
per the original: atlas panel with "you are here" tracking from narration,
travel action (backdrop swap + 20% road encounter), location-aware vendors
(shop/tavern trade counters), world-map vs battle-map tabs.

## Finale
"THE END" in narration triggers the completion card + fanfare; free roam
continues after. Complete-badge on the Continue caption is a parity gap.
