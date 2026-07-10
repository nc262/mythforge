# Character Studio — audio assets (all CC0 / public-domain)

Drop real sound files here and they override the built-in synthesized SFX
automatically. If a file is missing, the studio falls back to the Web-Audio
synth — so the game always has sound, with or without these assets.

**License policy: CC0 / public-domain only.** No attribution-required assets.
Good sources: Kenney.nl (all CC0), OpenGameArt.org (filter → CC0),
Freesound.org (filter → CC0).

## SFX — `static/audio/sfx/`
The loader tries `.ogg`, then `.mp3`, then `.wav` for each name:

| file (any ext) | plays on            |
|----------------|---------------------|
| `dice`         | rolling the dice    |
| `crit`         | natural 20          |
| `loot`         | picking up an item  |
| `gold`         | gold changes / sell |
| `level`        | levelling up        |
| `victory`      | winning a fight     |
| `potion`       | drinking a potion   |
| `quest`        | completing a quest  |

Keep them short (< ~1.5 s) and normalized. Missing files → synth fallback.

## Music — `static/audio/music/` (looping ambience per world)
The loader tries `.ogg`, `.mp3`, then `.wav` for the world id; **missing → the
built-in Web-Audio synth pad** (the game is never silent). Files ship below.

| file        | world                   | mood                         |
|-------------|-------------------------|------------------------------|
| `embervale` | The Embervale (fantasy) | warm D-minor hearth + harp   |
| `neonspire` | Neon Spire (cyberpunk)  | cold A-fifths drift + blips  |
| `everyday`  | Everyday (modern)       | mellow F-maj7 lofi ease      |
| `combat`    | (any fight)             | driving C-minor ostinato     |

Music loops quietly and follows the 🔊 SFX toggle. If the browser blocks
autoplay, music starts on the first interaction.

### Installed music (CC0 — generated originals)
The four `.wav` loops are **original compositions synthesized offline** with
`scripts/gen_world_music.py static/audio/music` (numpy additive synthesis) — authored for this
project, so **public-domain / CC0** with no attribution or licensing strings.
They're perfectly seamless (whole-cycle length + wrap-added decays + a tail↔head
crossfade). To swap in a downloaded CC0 track, just drop `<world>.ogg`/`.mp3`
alongside — the loader prefers it over the `.wav`.

## Installed SFX (CC0, from Kenney.nl)
These were pulled from Kenney's CC0 packs — free for any use, no attribution
required (provenance noted here as courtesy):

| our file      | source pack (kenney.nl, CC0)      | original            |
|---------------|-----------------------------------|---------------------|
| `gold.ogg`    | RPG Audio                         | handleCoins         |
| `loot.ogg`    | RPG Audio                         | dropLeather         |
| `hit.ogg`     | RPG Audio                         | chop                |
| `quest.ogg`   | Interface Sounds                  | confirmation_001    |
| `potion.ogg`  | Interface Sounds                  | glass_001           |
| `level.ogg`   | Music Jingles                     | jingles_NES00       |
| `victory.ogg` | Music Jingles                     | jingles_NES07       |
| `crit.ogg`    | Music Jingles                     | jingles_HIT00       |

`dice` intentionally uses the built-in synth (no clean CC0 match). Auditioned
by filename, not by ear — swap any that don't fit by replacing the file.

Music loops (`music/`) are still empty: Kenney's jingles are stingers, not
seamless ambient loops. A proper CC0 ambient loop can be dropped in later.
