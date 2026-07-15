# Vision

Mythforge is the definitive AI-powered D&D-style RPG: a **local** Game Master
with real teeth. The AI tells the story; the engine rolls the dice. Target
feel: **Baldur's Gate 3 × Divinity Original Sin 2 × Diablo IV × AI Dungeon**,
wearing a modern commercial-RPG interface.

## The one-sentence pitch
Every world is a door — forge a world in a minute, walk into it with a real
character sheet, and play a campaign where the dice, the economy, and death
are all real, narrated by an AI that never gets to cheat.

## Pillars (in priority order)
1. **The engine is the source of truth.** Combat, inventory, dice, time,
   economy, saves — deterministic code. The AI narrates outcomes it is told;
   it never invents them. (This is the founding decision — the original web
   product's #1 failure driver was AI mechanical unreliability.)
2. **The anti-amnesia campaign.** Pinpoint memory (embedded beats + recall),
   a cast codex, and a quest log keep long campaigns coherent. The GM
   remembers who you spared at the bridge.
3. **Worlds are cheap, personal, and beautiful.** The World Forge turns one
   idea line + five pillars into a playable world with lore, places, cast,
   beasts, campaigns, and painted key art.
4. **The table feels alive.** Generated scenes behind the parchment, dice
   that tumble, a sting when steel is drawn, per-world palettes (fantasy
   gold / neon cyan / everyday warm).
5. **Fully local.** Ollama for text, ComfyUI-ZLUDA (SDXL) for images,
   FastAPI for persistence — one Windows PC, no cloud, no subscription.

## Player promise
Nothing that matters is decided by vibes. Your HP, your gold, your death
saves, your level — all engine-owned, all persistent, all recoverable.

## Ship target
Steam-ready Windows desktop build (Godot 4.7 export), with the backend
either bundled locally or one-click self-hosted.
