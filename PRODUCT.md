# Mythforge

## What this is

A single-player desktop RPG whose Game Master is a language model running inside
the game's own process. D&D-5e-style rules with real dice, real sheets and real
consequences, in worlds you can forge from one sentence. One executable, one
optional image engine, a folder of save files. No cloud, no account, one player.

## Who it serves

One person: the owner. Success is *"it feels like a finished game I want to keep
playing"* — engaging sessions, no waiting on the GM, no jank.

## Register

A game, not an app. Design serves immersion: a night-and-gold palette that
re-skins per world, serif display type, and generated key art, backdrops and
portraits wherever art can be generated rather than drawn in widgets.

## Hard constraints

- **The engine decides; the model narrates.** Every mechanical effect arrives as
  a typed tag. The model may never state a roll, an HP total or a success. This
  is the founding decision — it is why the sheet can be trusted.
- **Local only, and not as a mode.** Every model call happens in this process on
  the same Vulkan device that draws the frame. Latency is a design constraint,
  not a footnote: a GM turn is 3.7 s and it is expected to stay that way.
- **No second path.** A missing model is an honest failure the player can act
  on, never a quiet degradation into something worse.
- **One design system.** Reuse the `Ui` tokens and the `Myth*` components.
  Never a parallel widget for a job one already does.
- **Reduce-motion safe.** Every animation has an out.
- **Reuse before build.** Worlds, art, memory and the tag pipeline already
  exist; new features glue them together rather than duplicating them.

## The flow

Hall → world → campaign → hero → Session Zero → play.

Details: [godot/docs/Vision.md](godot/docs/Vision.md) ·
[godot/docs/Architecture.md](godot/docs/Architecture.md) ·
[godot/docs/DesignSystem.md](godot/docs/DesignSystem.md).
