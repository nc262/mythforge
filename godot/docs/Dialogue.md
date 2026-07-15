# Dialogue & Narration

## Two registers
- **DM play**: the GM narrates second-person present, voices NPCs in quoted
  dialogue, ends turns on actionable moments. Mechanics ride tags only.
  Craft rules live in the persona (compose_world_gm) + per-turn envelope.
- **Companion chat**: pure persona conversation — raw messages, no
  envelope, no tags, no chronicling. The HUD hides itself.

## Presentation
Streamed token-by-token into parchment bubbles (typing glyphs ✦ ✦ ✦ until
the first token); player lines in candle-gold bubbles right; system events
as centered whispers; images inline + as the living backdrop. Tags are
stripped mid-stream (never visible). ↻ retell drops the last GM reply and
re-streams the identical framed message.

## Tone control
Session Zero knobs → per-turn `[GM style — …]` directive (only extremes
speak: ≤25 / ≥75). Re-tunable mid-campaign via the GM panel — parity gap,
M2 (knobs persist in the `gm` kind already).

## Voice (roadmapped M3)
Server TTS route exists (`/api/tts/synthesize`); narrator voice + speed and
per-turn narration playback are FeatureMatrix rows. The web original used
browser speechSynthesis — the desktop client will use the server route.

## Parity gaps
Edit-message (inline bubble editing via `/api/session/{sid}/edit-message`) ·
speaker-name lines in group scenes · "How do you want to do this?" flourish
input on killing blows (currently auto-asks the GM without the player's
flourish text) · banter injections.
