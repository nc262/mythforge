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
   it never invents them. This is the founding decision, and it exists because
   the failure driver in every AI-GM attempt is mechanical unreliability.
2. **The anti-amnesia campaign.** Pinpoint memory (embedded beats + recall),
   a cast codex, and a quest log keep long campaigns coherent. The GM
   remembers who you spared at the bridge.
3. **Worlds are cheap, personal, and beautiful.** The World Forge turns one
   idea line + five pillars into a playable world with lore, places, cast,
   beasts, campaigns, and painted key art.
4. **The table feels alive.** Generated scenes behind the parchment, dice
   that tumble, a sting when steel is drawn, per-world palettes (fantasy
   gold / neon cyan / everyday warm).
5. **The two Forges are pillars.** The Character Forge (forging a hero)
   and the Campaign Forge (the DM's war table) are cornerstone experiences
   with the weight of BG3's character creator — first-class on the main
   menu, each a full ritual (docs/forges/).
6. **Fully local, and it is not a mode.** The narrator, campaign memory, the
   forges and speech-to-text all run inside the game's own process on
   llama.cpp; images come from stable-diffusion.cpp beside it; saves are files.
   One PC, no cloud, no account, no subscription, and no second path that
   quietly phones somewhere when the local one is missing.

## Player promise
Nothing that matters is decided by vibes. Your HP, your gold, your death
saves, your level — all engine-owned, all persistent, all recoverable.

## Ship target
A Steam-ready Windows desktop build (Godot 4.7 export): one executable, an
installer that fetches the models and the image engine, and nothing to run
first.
