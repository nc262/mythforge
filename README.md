# ✦ Mythforge

A self-hosted, AI-run tabletop RPG. A local LLM is your Game Master; a local
image model paints your heroes, monsters, and worlds. D&D-5e-style rules —
real dice, real character sheets, real consequences — with zero cloud and
zero subscriptions.

**Play it like an online game:** one person hosts (the machine with the GPU),
friends join from a browser. Or run your own server.

## What's in the box

- **Worlds** — three built-in settings (high fantasy, cyberpunk, slice-of-life)
  plus a **Worldsmith**: describe any world in a sentence and the AI forges the
  realm, its people, campaigns, and map. Refine it, export it, share it.
- **A real Game Master** — narrates, plays every NPC, calls for checks,
  remembers your story, and honors the rules.
- **A real character** — 12 classes with per-level features you can *use*
  (Rage, Second Wind, Lay on Hands…), 8 backgrounds, spellbooks, inventory
  with equipment slots, XP and level-ups.
- **Real combat** — initiative, attack rolls against AC, crits, death saves,
  a tactical battle map, combat music, screen shake, and enemy portraits
  generated as you fight.
- **📖 The Lorebook** — an illustrated bestiary (with weaknesses the GM
  honors), spell grimoire, class guide, and living world lore.
- **A living world** — day/night, weather, factions, reputation, quests,
  companions who take wounds and hold grudges, random encounters, shops.
- Generated art everywhere: portraits, backdrops, items, monsters, key art.

## Join a server (the easy way)

You need: **a browser.** That's it.

1. Get invited to the host's [Tailscale](https://tailscale.com) network
   (free; it's a private VPN — nothing is exposed to the internet).
2. Open `http://<host-name>:7000`, create your account.
3. **New Adventure.** Your campaigns, heroes, and saves are yours alone.

## Host your own server

### Requirements

| | Text adventure (no generated art) | Full experience (with art) |
|---|---|---|
| CPU | any 4-core | any modern 6-core |
| RAM | 16 GB | 32 GB recommended |
| Disk | 15 GB | ~45 GB (models) |
| GPU | none needed | **NVIDIA** 8 GB VRAM (RTX 2060+; 12 GB comfortable) or **AMD** RDNA2+ with 12 GB (RX 6700 XT+, via ZLUDA) |
| OS | Windows 10/11 (Linux/macOS: see upstream docs) | Windows 10/11 |

Not sure? The check script tells you exactly what your machine can do:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-system.ps1
```

### Install

```powershell
git clone <this-repo>
cd <repo>
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

The installer analyzes your hardware and takes the right path automatically:

- **NVIDIA** → ComfyUI + CUDA, fully automated (optional 6.5 GB SDXL download).
- **AMD** → ComfyUI-ZLUDA, automated clone + a guided one-time finish
  (HIP SDK install + `scripts\fix-zluda-elevated.ps1`). Budget 30–60 min.
- **No capable GPU** → the full game, text-only (art disabled).

Then:

```powershell
.\start-odysseus.ps1        # game server → http://localhost:7000
.\start-image-stack.cmd     # art engine (skip on text-only)
```

### Hosting for friends

Install [Tailscale](https://tailscale.com), sign in, and invite your friends'
devices from the admin console. They browse to `http://<your-machine>:7000`.
Turn on **require login** in the app's auth settings so each friend gets their
own account (and their own campaigns).

Honest capacity note: one GPU serves everyone — 2–4 players is comfortable;
image generation queues one at a time.

## Credits

Built on [Odysseus](https://github.com/pewdiepie-archdaemon/odysseus) (MIT),
a self-hosted AI workspace — see `docs/odysseus-upstream-README.md` and
`LICENSE`. Sound effects from [Kenney.nl](https://kenney.nl) (CC0).
Everything runs locally; your stories never leave your machines.
