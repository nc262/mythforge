# ✦ Mythforge

A self-hosted, AI-run tabletop RPG. A local LLM is your Game Master; a local
image model paints your heroes, monsters, and worlds. D&D-5e-style rules —
real dice, real character sheets, real consequences — with zero cloud and
zero subscriptions.

**Play it like an online game:** one person hosts (the machine with the GPU),
friends join from a browser. Or run your own server.

## What's in the box

- **Worlds** — six built-in settings (high fantasy, cyberpunk, slice-of-life,
  drowned-pirate coast, Norse saga, and gaslamp steampunk), each shipped fully
  pre-baked: thousands of world-true items, creatures, and painted art, ready
  the instant you start. Plus a **Worldsmith**: describe any world in a sentence
  and the AI forges the realm, its people, campaigns, and map. Refine it, export
  it, share it.
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

## Download & play (the easy way)

The desktop edition is a **single installer**. Download it, double-click, click
through — it sets everything up on your machine and leaves a **Mythforge**
shortcut. No accounts, no cloud, no separate downloads to chase.

1. Download **`Mythforge-Setup.exe`** from the
   [latest release](../../releases/latest).
2. Run it. On first launch it downloads and configures everything **for your
   hardware, automatically** — the local AI Game Master (Ollama + model), the
   art engine (ComfyUI, on the right backend for your GPU), and the game itself.
   Budget a one-time ~10 GB download and a coffee; after that it's instant.
3. Click the **Mythforge** shortcut and play. Every launch quietly starts the
   engine, opens the game, and shuts the engine down when you quit — you never
   touch a server or a terminal.

**What "for your hardware" means:** an NVIDIA card gets CUDA, an AMD card gets
the ZLUDA path, and a machine with no capable GPU still plays the full game —
all six worlds ship with their art pre-baked, so the story, combat, and worlds
never wait on a GPU. Generated art (new items the GM invents, your own forged
worlds) is the only thing that needs one.

> Everything is local. Your stories, heroes, and saves never leave your machine.
> The only things fetched are the open-source engine and models, from their
> official sources.

Building the installer yourself (maintainers): see
[`installer/`](installer/) — an [Inno Setup](https://jrsoftware.org/isdl.php)
script wrapping the lean backend, plus a launcher and a first-run bootstrap that
reuses [`scripts/install.ps1`](scripts/install.ps1).

## Play in a browser instead (join a host)

Prefer the browser client, or joining a friend who hosts? You need **a browser.**

1. Get invited to the host's [Tailscale](https://tailscale.com) network
   (free; it's a private VPN — nothing is exposed to the internet).
2. Open `http://<host-name>:7000`, create your account.
3. **New Adventure.** Your campaigns, heroes, and saves are yours alone.

## Host your own server (from source)

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
