# Future Ideas

Not commitments — a parking lot so ideas survive. Promotion path: idea →
FeatureMatrix row (with priority) → Roadmap milestone.

## Systems
- **Relationship & reputation web**: per-NPC disposition already extracts;
  add faction standing, remembered favors/slights folding into envelopes.
- **Engine-verified quest objectives**: extractor writes stages; engine
  checks named conditions (gold≥N, item held, foe slain) and pays rewards.
- **World simulation depth**: worldtick chains (NPC goals progressing over
  days), seasonal weather, festivals on the clock.
- **Crafting v2**: recipes from bestiary drops (typed components), world-
  flavored (tech-graft mods in Neonspire, preserves in Everyday).
- **Bestiary stat blocks**: full per-creature AC/HP/attacks/abilities from
  tier + world, replacing name-regex guesses.
- **Camp mode**: a rest scene with companion banter, watch order, ambush
  rolls played out on the grid.

## AI
- Model routing: big model for scene-setting turns, small for quick
  exchanges; per-turn latency budget.
- Structured NPC voices: per-cast-member speaking style enforced via
  persona snippets in the envelope.
- Vision loop: feed generated scene art back through /describe so the GM
  can reference what's actually in the picture.
- Local voice: TTS narrator per GM persona; STT push-to-talk play.

## Presentation
- Animated 3D dice (physics roll on the table surface).
- Character paper doll rendered from equipped items over the portrait.
- Cinematic finale sequence: key art slideshow + campaign stats.
- Photo mode / share-a-moment export (image + caption card).

## Platform
- Steam achievements mapped to engine events (first crit, world forged,
  campaign completed, death survived).
- Steam Workshop for exported worlds (.world.json already portable).
- Co-op party play over the existing polling protocol; voice via WebRTC.
- Bundled backend installer (one-click: Ollama + models + server).
