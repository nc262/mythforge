# Ritual: Opening the Pack

*The first ritual document. Every major screen gets one of these before any
code changes (docs/DesignSystem.md — Implementation Rules).*

## 1. Experience — what the player should feel

**Emotions: preparedness · adventure · ownership.**

You are not opening a menu. You are swinging your pack off your shoulder and
kneeling over it at the campfire. Your things are *yours* — the dagger you
haggled for in the square, the potion that saved you in the crypt. Checking
your gear should feel like the quiet minute before the door gets kicked in.

**Material identity:** worn leather, canvas, iron buckles, stitching.
Equipment feels heavy; items feel valuable. (Palette-driven: Neonspire reads
as a coated tactical satchel, Everyday as a canvas messenger bag — same
primitives, world-tinted.)

## 2. The ritual beats

| Beat | What happens |
|---|---|
| **Anticipation** | The world dims behind a night scrim — the table clears for the pack |
| **Reveal** | The pack settles in (fade + settle); contents stagger onto the leather one by one, like being laid out |
| **Focal point** | The hero: portrait glowing softly, name beneath — *whose* pack this is. Then the carved equipment sockets. Then the goods |
| **Interaction** | Drag a piece to a socket (it pulses gold as it seats), double-click to equip, right-click for Equip / Inspect / Sell, hover lifts a card toward the light with its framed story (and the ▲/▼ verdict vs what's worn) |
| **Reward** | Equipping chimes and the stat that changed rises off the ledger ("+1 AC"); selling clinks gold into the purse line |
| **Graceful exit** | "Close the pack" — the scrim lifts, the world returns |

## 3. UX flow — every interaction

- **Open**: 🎒 button / Ctrl+I → scrim + reveal ceremony (≤0.4s total; reduce_motion skips all of it)
- **Hover card**: lift 1.07 + shadow deepen; framed tooltip: name (rarity color), type, stats, comparison row, sell value
- **Hover socket**: filled → same tooltip; empty → ghost glyph brightens
- **Drag card → socket**: legal (type match; weapons may go off-hand) → seats + gold pulse + chime; illegal → nothing moves (no error dialog — the world just doesn't take it)
- **Drag socket → pack surface**: unequips
- **Drag card → card**: reorders (insert at target)
- **Double-click card/socket**: equip/unequip toggle
- **Right-click card**: Equip/Unequip · Inspect (large art, its story, slow settle) · Sell (price shown in the menu, world currency)
- **Capacity**: a strap gauge under the goods — fills as the pack fills; never a cell count of empty boxes
- **Keyboard**: Esc closes; tooltips reachable by focus (Godot focus ring preserved)
- **Exit**: Close button ("Put the pack away") or Esc

## 4. Wireframe — layout and focus order

```
┌──────────────────────── Your Pack ────────────────────────┐
│                 │                                          │
│   ( PORTRAIT )  │   ✦ THE GOODS ✦                          │
│    hero name    │  ┌ leather surface, stitched ─────────┐  │
│                 │  │ [card][card][card][card]            │  │
│  ✦ EQUIPPED ✦   │  │ [card][card]        (only items —   │  │
│  [⚔] [🥋] [🗡]   │  │                     no empty cells) │  │
│      [⛨]        │  └─────────────────────────────────────┘  │
│  AC · HP · ATK  │  ═══ strap gauge: Pack 6/24 ═══           │
│   (the ledger)  │  hint line                                │
│                 │                          [ Close pack ]   │
└───────────────────────────────────────────────────────────┘
Focus order: portrait (1) → sockets (2) → goods (3) → strap (4)
```

## 5. Visual mockup

In-engine with fake data — the MDL gallery carries card/socket/gauge/portrait
faces; this ritual composes them on the new leather material. Verified by
screenshot before ship (see Testing.md).

## 6-8. Polish, testing, documentation

- Polish: hover/press (Ui.polish), one breathe (portrait halo), equip pulse,
  reward rise_text, chime hooks; reduce_motion honored everywhere.
- Testing: self_check (state logic unchanged), gallery screenshot, inventory
  screenshot at 1280 and 1024×600, mouse + keyboard paths.
- Documentation: DesignSystem.md (leather material, ritual_open primitive),
  FeatureMatrix U1 row, Roadmap, KnownIssues.
