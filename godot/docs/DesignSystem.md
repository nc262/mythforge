# Mythforge Design Language (MDL)

**The single source of truth for every UI element in the game.**

## The Five Pillars (every component must satisfy all five)

1. **Physicality** — constructed from believable materials that exist within
   the game's world (forged steel, parchment, carved stone, candle-light).
2. **Hierarchy** — the eye knows where to look first, second, and third
   without conscious effort.
3. **Feedback** — every interaction acknowledges the player through motion,
   light, sound, or subtle animation.
4. **Reusability** — every visual pattern is implemented once and reused
   everywhere.
5. **Delight** — opening any menu is enjoyable, even when no important
   decision is being made.

A component that is functional but not memorable is not done — keep refining.
No screen may define its own colors, spacing, radii, motion timing, fonts,
tooltips, or one-off components. Screens are *applications* of this system.

Code homes:
- **Tokens, surfaces, theme, motion** → `autoload/skin.gd` (the `Ui` autoload)
- **Components** → `godot/ui/myth_*.gd` (preload and compose)
- **Gallery / visual regression** → `tests/ui_gallery.tscn` (every component,
  one screen — screenshot it before and after any system change)

---

## 1. Tokens (Ui constants — the only numbers allowed)

| Token | Values | Use |
|---|---|---|
| `Ui.SPACE` | xs 4 · s 8 · m 14 · l 22 · xl 34 | every separation/margin |
| `Ui.TIME` | fast 0.12 · base 0.22 · slow 0.45 · breath 3.2 | every tween duration |
| `Ui.RADIUS` | s 4 · m 9 · l 18 | every corner |
| `Ui.RARITY` | common/uncommon/rare/epic/legendary → palette roles | every rarity tint (`Ui.rarity_color(r)`) |
| `Ui.c(role)` | night, night2, surface, surface2, sheet, border, border_soft, ink, ink_soft, ink_dim, gold, gold_soft, amethyst, amethyst_deep, ember, danger | every color — palette-driven, retinted per world |

Type scale (theme-owned): Title 30 display-serif tracked · Header 16 tracked
caps gold · body 15 sans · hint 13 dim · hero numbers 19+.

## 2. Surfaces (procedural — nothing is a flat rect)

| Builder | Feel | Used by |
|---|---|---|
| `forged_tex` | anvil-struck slab: gradient, edge, trim, bevel | all buttons |
| `ornate_frame_tex` | double trim + corner diamonds | windows, panels, tooltips |
| `grain_tex` | parchment whisper-noise | reading surfaces, GM bubbles |
| `sb_socket(lit)` | carved dark well; gold-lit when filled | equipment slots |
| `sb_card(rarity)` | night steel + rarity halo shadow | item/entity cards |
| `glow_tex()` | radial halo (modulate to tint) | rarity glows, milestones, portrait rims |
| `leather_tex` / `sb_leather()` | worn leather with gold-thread stitching | pack surface, merchant counter |

## 3. Motion vocabulary (Ui functions — all honor `reduce_motion`)

| Verb | What | Rule |
|---|---|---|
| `Ui.polish(root)` | hover-lift 1.045 + press-dip 0.96 on every Button under root | one call per screen `_ready`; call again after building dynamic dialogs |
| `Ui.reveal(ctrl, delay)` | fade-in + settle from 98.5% scale | entry of panels/dialog content |
| `Ui.reveal_children(box, stagger)` | staggered reveal | menus, card racks |
| `Ui.breathe(ctrl)` | 3.2s luminance sine | ONE monumental element per screen, max |
| `Ui.pulse(ctrl)` | one-shot attention pop | a slot fills, a chip lands, a node unlocks |
| `Ui.rise_text(parent, txt, color, at)` | rising fading ghost text | damage, gold, XP moments |
| `Ui.ritual_open(dlg)` | THE window ritual: world dims (anticipation), contents settle staggered (reveal), scrim lifts on close (graceful exit) | every dialog/window, no exceptions |

**Rituals:** every major screen gets a ritual doc (and mounts its EAS environment first) in `docs/rituals/` (emotions,
beats, UX flow, wireframe) BEFORE implementation. First: rituals/Inventory.md.

Audio hooks: motion verbs are the mount points — `Sfx` tick/thud samples are
in the make_sfx backlog; when they land they attach inside `polish`/`pulse`,
never per-screen.

## 4. Components (`godot/ui/`)

| Component | Contract |
|---|---|
| `MythCard` | THE face of anything ownable (item, save, world, spell). `setup(payload, tex, glyph)`; rarity halo from payload; hover lift; qty badge; `activated` (double-click), `context_requested` (right-click); framed tooltip from `payload.tip_title/tip_rows`; drag source (payload as drag data). |
| `MythSocket` | Carved equipment well. Ghost glyph when empty, gold-lit + art when filled; drop target emitting `dropped(data, slot_key)`; `pulse` on fill. |
| `MythTooltip.build(title, rows, rarity)` | The only tooltip in the game. Framed, title tinted by rarity, rows = `[text, role]` pairs (comparison rows use `gold`/`danger` roles with ▲/▼). |
| `MythHeader` | `✦ SECTION ✦` with gold wing-lines — the only section header. |
| `MythGauge` | Drawn strap bar (capacity, HP, XP) — rim-lit fill, centered caption. Never a stock ProgressBar. |
| `MythPortrait` | Round art disc + colored ring + optional halo glow; optional vitals arc + turn ring. Tokens, sheet, dialogue speakers, initiative chips. |
| `MythCamera` | The pan/zoom camera every map-like surface shares (wheel toward cursor, drag pan, clamped edges). |
| `MythFold` | Collapsible section (gilded ▸/▾ header, content reveals) — hide complexity until wanted. |

Composition rules:
- Components reference each other via `preload` consts (no class-cache coupling).
- Components never touch `GameState`/`Rules` — screens feed them data
  (payloads, tip rows). The system stays domain-free.
- Components read `Ui` at build time; screens rebuild on `Ui.changed`
  (world retint) — same contract screens already follow for the theme.

## 5. The Environmental Art System (EAS)

**The world is the interface.** Every screen begins by answering "where is
the player?" — never "what controls belong here?" UI is layered INTO an
illustrated environment, not floated over chrome.

- **`MythEnvironment`** (ui/myth_environment.gd) is the mount: a generated
  generated painting of the room (cover-fit, clipped, whisper of mouse parallax),
  a legibility scrim + edge vignette, breathing volumetric light shafts,
  flickering candle anchors, and drifting particles (dust or embers). With
  no key it is a pure atmosphere overlay for screens that already own art.
- **Environments live in `Art.ENV_PROMPTS`** and generate through the same
  queue as all art (cached forever in user://art): env-wartable (Campaign
  Forge) · env-forge (Character Forge) · env-pack (inventory) ·
  env-merchant (trading post) · env-journal (the manuscript) ·
  env-maptable (the living map's table) · env-fireside (the Hero's Record;
  dialogue later). Per-world variants are a matrix row.
- **Procedural backdrops are the fallback only** — first run, while the
  painting is on the easel; never the destination.
- **Camera thinking**: background (the painting) · midground (scrim,
  shafts) · foreground (UI + particles). One lighting direction per room.
- Rule: every new screen MOUNTS an environment first
  (`MythEnvironment.mount(host, key, mood, lights)`), then lays UI into it.

## 6. Laws

1. No one-off colors, spacing, radii, durations, fonts, tooltips, headers,
   bars, or cards. If a screen needs a new pattern, it is added HERE first.
2. No visible GridContainer-of-empty-boxes. Empty space is composed
   (texture, gauge, silhouette), not cell borders.
3. No OS-default tooltip ever reaches the player.
4. No instant pop-in: anything that appears, `reveal`s.
5. One `breathe` per screen. Motion seasons; it never shouts.
6. Every rarity color comes from `Ui.RARITY`. Every world retint must survive
   with zero screen changes (palette-driven only).
7. The gallery (`tests/ui_gallery.tscn`) is updated with every new component
   and screenshot-verified with every system change.
