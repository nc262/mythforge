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

## 3. Motion vocabulary (Ui functions — all honor `reduce_motion`)

| Verb | What | Rule |
|---|---|---|
| `Ui.polish(root)` | hover-lift 1.045 + press-dip 0.96 on every Button under root | one call per screen `_ready`; call again after building dynamic dialogs |
| `Ui.reveal(ctrl, delay)` | fade-in + settle from 98.5% scale | entry of panels/dialog content |
| `Ui.reveal_children(box, stagger)` | staggered reveal | menus, card racks |
| `Ui.breathe(ctrl)` | 3.2s luminance sine | ONE monumental element per screen, max |
| `Ui.pulse(ctrl)` | one-shot attention pop | a slot fills, a chip lands, a node unlocks |
| `Ui.rise_text(parent, txt, color, at)` | rising fading ghost text | damage, gold, XP moments |

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
| `MythPortrait` | Round art disc + colored ring + optional halo glow. Tokens, sheet, dialogue speakers, initiative chips. |

Composition rules:
- Components reference each other via `preload` consts (no class-cache coupling).
- Components never touch `GameState`/`Rules` — screens feed them data
  (payloads, tip rows). The system stays domain-free.
- Components read `Ui` at build time; screens rebuild on `Ui.changed`
  (world retint) — same contract screens already follow for the theme.

## 5. Laws

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
