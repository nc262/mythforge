# ✦ Mythforge

A single-player tabletop RPG whose Game Master is a language model running on
your own machine. D&D-5e-style rules — real dice, real character sheets, real
consequences — with no cloud, no account and no subscription.

**Nothing here phones anywhere.** The narrator, campaign memory, the cast codex,
the quest log, the Worldsmith and speech-to-text all run *inside the game's own
process*. Your stories, heroes and saves are files on your disk.

## What's in the box

- **Worlds** — six built-in settings (high fantasy, cyberpunk, slice-of-life,
  drowned-pirate coast, Norse saga, gaslamp steampunk), each shipped fully
  pre-baked: thousands of world-true items, creatures and painted art, ready the
  instant you start. Plus a **Worldsmith**: describe any world in a sentence and
  it forges the realm, its people, its campaigns and its map.
- **A real Game Master** — narrates, plays every NPC, calls for checks,
  remembers your story, and never gets to decide a roll.
- **A real character** — 12 classes with per-level features you can *use* (Rage,
  Second Wind, Lay on Hands…), 8 backgrounds, spellbooks, an inventory with
  equipment slots, XP and level-ups.
- **Real combat** — initiative, attack rolls against AC, crits, cover, death
  saves, a tactical battle map, and enemy portraits painted as you fight.
- **The Lorebook** — an illustrated bestiary (with weaknesses the GM honours), a
  spell grimoire, a class guide, and living world lore.
- **A living world** — day and night, weather, factions, quests, companions who
  take wounds and hold grudges, random encounters, shops.

## The engine boundary

The model narrates. The engine decides. Every mechanical effect arrives as a
typed tag the engine applies — `[[check ability=DEX dc=13]]`,
`[[damage roll=2d6+3]]` — and the model is never permitted to state a dice
result, an HP total, or a success. That is the founding decision of the project,
and it is why the numbers on your sheet can be trusted.

## Install & play

Download **`Mythforge-Setup.exe`** from the
[latest release](../../releases/latest), run it, and click through. First launch
downloads the game, the models and the art engine for your machine — budget a
one-time ~10 GB and a coffee. After that it opens straight into the Hall.

Everything fetched comes from official sources: HuggingFace for the models,
GitHub for stable-diffusion.cpp and the NobodyWho extension.

## From source

```powershell
git clone <this-repo>
cd <repo>
powershell -ExecutionPolicy Bypass -File .\scripts\check-system.ps1   # what can this box do?
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1        # models + engines
.\play-mythforge.cmd                                                 # play
pwsh scripts\start-image-sdcpp.ps1                                    # art (optional)
```

### Requirements

Both engines run on **Vulkan**, so there is no vendor branch — the only question
is how much VRAM there is.

| | Text only | Comfortable | With generated art |
|---|---|---|---|
| CPU | any 4-core | any modern 6-core | any modern 6-core |
| RAM | 16 GB | 16 GB | 32 GB |
| Disk | 15 GB | 15 GB | ~45 GB |
| VRAM | none — runs on CPU, slowly | 8 GB (the narrator stays resident) | 12 GB |

A half-offloaded model is the single largest cost per turn, which is why 8 GB is
the number that matters most — see
[godot/docs/Performance.md](godot/docs/Performance.md).

## Docs

Start with [CLAUDE.md](CLAUDE.md) for orientation, then
[godot/docs/Architecture.md](godot/docs/Architecture.md). Read
[godot/docs/LocalLLM-Tuning.md](godot/docs/LocalLLM-Tuning.md) before touching
any model call.

## Credits

See [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md) — Godot, NobodyWho, llama.cpp,
stable-diffusion.cpp, the models, and sound effects from
[Kenney.nl](https://kenney.nl) (CC0).
