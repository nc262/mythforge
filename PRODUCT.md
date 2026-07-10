# Odysseus — Character Studio

## What this is
A self-hosted AI game console. Odysseus (the app) has been repurposed into two
experiences: **Character Studio** — a full D&D-5e-style adventure game run by a
local LLM Game Master with generated art, and **Companions** — persistent
one-on-one AI character chats. Everything runs on one Windows PC (FastAPI +
Ollama + ComfyUI image gen); no cloud, no accounts, one player.

## Who it serves
One person: the owner. Success = "it feels like a finished game I want to keep
playing" — engaging sessions, no waiting on the GM, no jank.

## Register
Game UI. Design serves immersion: night-and-gold fantasy palette
(`.studio-root` tokens in `static/studio.css`), serif display type, generated
key art/backdrops/portraits over hand-drawn CSS wherever art can be generated.

## Hard constraints
- **Local only.** All inference/gen is local GPU; latency budget matters —
  narration on a fast 8B model, extractors on small models, art async.
- **One design system.** Reuse `--st-*` tokens and existing panel/overlay
  patterns (`chronicle-overlay`, `st-btn`, `gm-row`) — never a parallel system.
- **Reuse before build.** The app already has chat, personas, image gen,
  world-state persistence; new features glue these, not duplicate them.
- **Reduced-motion safe.** Every animation has a `prefers-reduced-motion` out.
- The title screen and game flow: title → world → campaign → hero → Session
  Zero → play. See [docs/character-studio-roadmap.md](docs/character-studio-roadmap.md).
