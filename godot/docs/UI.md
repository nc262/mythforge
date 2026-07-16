# UI

## The forged pass (2026-07-15)
All chrome is procedurally forged at runtime — no image assets: buttons are
nine-patch steel slabs (gradient, black edge, gold trim, anvil highlight),
panels wear ornate double-trim frames with corner diamonds, long-form text
sits on parchment grain (FastNoiseLite), dialogs use the ornate Window
frame, titles are tracked serif with a candle-glow outline, and a radial
vignette keeps the light centered. The 🎒 inventory is a paper doll + 24-
cell rarity-lit slot grid with drag-and-drop.

## Design system ("Enchanted Arcane", ported from studio.css)
Tokens live in `Ui` (autoload/skin.gd) as three palettes that restyle the
entire client when a world is entered:
- **arcane/Embervale**: night `#0c0a1c`, candle gold `#e8c171`, amethyst
- **neonspire**: blue-black, cyan `#2de2e6`, magenta
- **everyday**: warm grays, café gold `#e0a96d`, soft blue

Type: serif (Palatino-stack) for brand/titles, sans (Inter/Segoe) for UI.
Radii 14/9; amethyst focus rings; gold accent buttons; parchment panels.
Theme variations: TitleLabel, HintLabel, AccentButton, BubbleGm/BubbleMe,
DicePanel/DieLabel. Reduce-motion honored everywhere (setting).

## Surfaces
- **Title**: brand + tagline over drifting starfield + last world's key art;
  Continue (caption) / New Adventure / Companion / Settings.
- **Worlds → detail**: key-art cards with kind chips; adventures, craft,
  cast; step banner ("Step 1 of 3 — world › campaign › hero").
- **The table (game.tscn)**: bubble thread over the living backdrop; combat
  tracker panel; accent roll bar; input row (Send · Sheet · 📜 · 🎲 · 🛒 ·
  🖼 · 🌙 · ⛺); right panel = sheet or codex; centered dice-moment overlay;
  ember battle tint.
- Dialogs: hero forge, Session Zero, world forge (pillars), campaign smith,
  continue-vs-new, ask-GM.

## Signature moments
Dice tumble on a gold-glow card · bubbles breathe in · backdrops crossfade
on scene changes · HP as colored bars (gold → danger under half) · epitaph
and THE-END cards.

## Keyboard map
Ctrl+S sheet · Ctrl+L codex · Ctrl+J journal (searchable) · Ctrl+M world
map · Ctrl+R retell · Space next combat turn (when not typing) · Esc focus
the message box · Enter send.

## Windows shipped
🛒 Trading post (wares/pack/purse/haggle, one GM beat per visit) ·
📖 Journal (quests+people+chapters, live search) · 🗺 World map (painted,
click-travel) · ⚡ Reaction dialog · 🎉 Level-up ceremony · ⚒ hero/world
forges · Session Zero / 🎛 retune.

## Production bar (M3 — the AAA pass)
Per the target directive, still owed: controller navigation (focus paths on
every surface), keyboard shortcuts (documented map), drag-and-drop inventory
grid + equipment paper doll, merchant window (beyond the chat bubble),
quest journal window with search, world map + minimap, tooltips everywhere,
animated window transitions, Steam-ready scaling (test 1080p/1440p/4K,
ui_scale setting). Rule: no placeholder-looking layouts ship; anything
below bar stays behind a flag until styled.
