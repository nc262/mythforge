# Character Studio — Roadmap

Where the game stands and what's left to build. Updated 2026-07-04.

## Shipped in the "core D&D mechanics" pass (2026-07-04)

Audited the game against real 5e and filled the biggest genuinely-missing
CORE systems:

- **Heritage / species** — 9 heritages (Human, Elf, Dwarf, Halfling, Half-Orc,
  Tiefling, Dragonborn, Gnome, Half-Elf) in the character creator, each with
  ability-score bonuses (applied before HP is rolled), speed, darkvision, and
  signature traits. Fed to the GM to honor (advantages, resistances, darkvision).
  **Relentless Endurance** (Half-Orc) is a real mechanic: a killing blow leaves
  you at 1 HP once per long rest. *Verified live.*
- **Spellcasting statistics** — each caster class has a casting ability (Wizard
  INT, Cleric/Druid/Ranger WIS, the rest CHA). Spell save DC (8 + prof + mod)
  and spell attack bonus are computed, shown on the sheet, and fed to the GM so
  "make a save against my spell" uses real numbers. *Verified: L3 Wizard → DC 13,
  atk +5.*
- **Concentration** — you hold one concentration spell; casting a new one drops
  the old, and taking damage forces a CON save (DC 10 or half the damage) to
  keep it. Wired into both the auto-damage detector and the combat tracker's
  damage button. *Verified live: held at DC 10 with a passing save, and rode
  alongside Relentless Endurance on a killing blow.*
- **Passive Perception** — 10 + WIS + prof, shown on the sheet and fed to the GM
  for noticing hidden things.

### Still on the 5e checklist (future passes, roughly by impact)
- **The 15 conditions with mechanical effects** — currently freeform text;
  applying real effects (prone → melee attackers have advantage; poisoned →
  disadvantage on attacks & checks; restrained, stunned, frightened, etc.).
- **Feats** as an ASI alternative at level-up (Great Weapon Master, Sharpshooter,
  Lucky, Alert, Tough…).
- **Damage types + resistances/immunities/vulnerabilities** on monsters (the
  bestiary already narrates weaknesses; make them mechanical).
- **Weapon properties** (finesse partly done; add versatile, two-handed, heavy,
  light/two-weapon fighting, reach, thrown).
- **Exhaustion track** (6 levels), tied to rest-risk and forced marches.
- **Cover** (½ / ¾ / full) and **ranged range bands**.
- **Cantrip damage scaling** at levels 5/11/17.
- **Subclasses** as real mechanics (currently narrative feature text).

## Shipped in the "progression & endgame" pass (2026-07-04)

- **Learn new spells on level-up** — casters (and half-casters at L2) choose up
  to 2 spells they can reach at the new level, from their class list, excluding
  what they already know; picks land on the sheet and caster slots grow.
  *Verified: a L2→L3 Wizard was offered 2nd-circle spells, learned Misty Step +
  Sleep atop 4 existing, gained L2 slots.*
- **Renown & treasure tiers** — the sheet summary now tells the GM how the WORLD
  should treat this hero: an unknown newcomer at L1 vs a living legend at L10+,
  with a matching treasure tier (humble coin → rare gear → epic → legendary
  relics). Leveling changes the story, not just the numbers.
- **Legendary-loot fanfare** — epic/legendary pickups play the crit sting and a
  toast (⚡ Legendary find — …). *Primitives proven live; toast + rarity regex
  verified.*
- **Campaign finales** — a "🏁 Conclude the tale" button in the quest log sends
  the GM a forceful finale prompt (climax + epilogue, end on "THE END"); auto-
  detection marks the campaign complete on that phrase, with fanfare, a Chronicle
  auto-archive, a 🏁 THE END objective chip, and a "· 🏁 Complete" tag on the
  title-screen Continue caption. *Verified: completion + archive + chip fired.*
  - Caveat: the 8B model doesn't always obey the finale prompt (it wrote a
    continuing scene in testing), so completion is **player-driven** — a
    persistent "🏁 Mark 'THE END'" button guarantees closure regardless of what
    the model writes; auto-detection is the bonus when it cooperates.


## Shipped (the game as it stands)

**The flow** — title screen (rotating generated key art, Continue / New Adventure /
Companions) → choose a world (3 prebuilt + player-forged) → choose a campaign
(prebuilt, AI-crafted, or free roam) → create your hero (the adventurer editor:
portrait gen, class, roll/standard-array stats, class kit) → Session Zero
(tone/difficulty knobs) → play.

**The engine** — D&D-5e-style rules: abilities/skills/saves with proficiencies,
d20 checks with advantage/disadvantage, HP/AC, conditions that expire, death
saves + game-over, XP/leveling with ASI, **real class features per level**,
spell slots with progression, rests (short/long, with rest risk), equipment
that affects combat, encumbrance, consumables.

**The world** — server-persisted world state per campaign: quest log + objective
HUD, NPC codex with portraits/goals/dispositions, cross-session bonds,
factions & places (realm screen), world atlas with travel + "you are here",
world clock synced to the fiction, off-screen world ticks, shop economy,
**companions who join your party and fight beside you**.

**The feel** — combat immersion mode (enemy stage w/ portrait + HP, auto damage
rolls, screen shake, battle map auto-open, combat music), per-world generated
backdrops, item art, NPC portraits, CC0 SFX + synth fallback, TTS narration,
notebook, animations for loot/gold/level/spells/rest, "Previously on…" recaps.

**Creation** — Worldsmith (describe a world → AI builds realm/cast/campaigns/
locations/backdrop) and Campaignsmith (describe a story → AI drafts premise +
opening scene) for any world, prebuilt or forged.

## Shipped in the "full game" pass (2026-07-02)

- **Player combat actions** — ⚔ Attack per foe (d20 + ability + prof + weapon
  vs AC, crits double dice, Rage bonus) and 🏃 Flee (DEX vs DC 12); damage
  lands on tokens, victory triggers itself, aftermath prompts lootable spoils.
- **Starting spellbooks** — every caster class begins with cantrips + L1 spells.
- **Usable class features** — Second Wind, Rage, Lay on Hands, Action Surge,
  Wild Shape, Ki, Bardic Inspiration, Channel Divinity, Arcane Recovery… have
  Use buttons with per-rest charges; rests recharge them.
- **Backgrounds** — 8 backgrounds (Soldier, Criminal, Sage…) grant two skills
  and a story hook the GM weaves in.
- **Weather** — rolled each dawn per world, shown on the clock chip, colors
  the GM's scenes.
- **Generative ambient music** — Web-Audio pads per world + combat when no
  music file exists; real files still take precedence.
- **Companion depth** — wounds persist between fights, rests heal them, party
  chips with live HP ride in the chat banner.
- **Crafting** — 🔨 Combine two items; the GM adjudicates, auto-loot pockets
  the result.
- **Continue with save info** — campaign · hero · level · day on the title menu.
- **Forge-time cast portraits** — custom-world cast faces bake right after the
  backdrop.
- **First-run "How to play" card** + enemy HP scaling with player level +
  hardened foe detection (no more combatants named "Spell To Aid Your").

## Shipped in the "lorebook" pass (2026-07-02)

- **The Lorebook** (📖 Lore in the chat HUD) — four tabs:
  *Bestiary* (26 creatures across 3 threat tiers with description, **weakness**,
  tactics, and conjurable art — and the GM receives the weakness as canon when
  you fight a known beast), *Grimoire* (30 spells with school/classes/effects +
  "add to my spellbook"), *Classes* (all 12: blurb, hit die, saves, skills,
  starting kit, signature spells, features by level), *This World* (live lore,
  places, factions, cast, backgrounds). Entry art generates once and caches
  globally (`loreart` in `_global` world-state).
- **Encounter tables per world** — rest interruptions and road trouble now name
  bestiary foes fitting the setting.
- **Companion sheets** — companions get a class (inferred from their role),
  level = yours, class-based HP/AC; party section on the character sheet.
- **Guest hero (hot-seat)** — a second player's hero with real stats and a
  combat token; the GM is told it's a hero, not an NPC.
- **Export/import worlds** — download any forged world as `.world.json`,
  import from the worlds gallery.
- **Worldsmith refinement** — "✎ Refine…" revises the draft world with your
  instructions instead of rerolling from scratch.
- **Combat XP by toughness** — slain foes grant `max(25, 2×hpMax)` XP.

## Shipped in the "multiplayer" pass (2026-07-03)

- **Shared-party campaigns** — the host opens a table (🔗 Party in the chat
  HUD) and gets a 6-letter join code; friends pick **Join a Party** on the
  title screen, name their hero + class, and sit down in the SAME story:
  one chat session, one world state (the host's), their hero written into the
  party as a player-run guest hero.
  - `src/party_registry.py` — the registry (code → host/cid/sid/members/lock).
  - `_verify_session_owner` honors party membership (one gate covers
    history + chat_stream), studio world-state reads/writes resolve members
    onto the host's blob.
  - Client polls every 4 s: new messages appear for everyone; a **table lock**
    ("✋ ‹name› is talking to the GM…") keeps turns one-at-a-time; guests speak
    as their hero automatically; only the host runs the background extractors.

### Multiplayer ceilings (honest list)
- Polling (4 s), not websockets — replies appear on the next tick, not live-streamed to spectators.
- Guests share the host's sheet-world; their hero is companion-grade (no personal inventory/spell slots yet).
- The table lock is advisory and expires after 120 s — two truly simultaneous sends can still interleave.
- Needs a real two-account test over Tailscale (verified single-account: registry, gate, lock, both UIs).

## Shipped in the "content depth" pass (2026-07-03)

- **Worldsmith creatures** — every forged world now births 3 setting-specific
  threats (name/tier/desc/**weakness**/tactics/art). They lead the lorebook's
  bestiary ("Creatures of this world"), haunt rest-risk and travel encounters,
  and their weaknesses are combat canon for the GM. Export/import carries them.
- **Worldsmith reliability rework** — one giant JSON schema made the 3B drop
  sections and the 8B crawl (VRAM-squeezed by ComfyUI, 9-minute timeouts). Now
  TWO focused calls (world core → people & threats), each with one stern retry
  and `max_retries=1`. Verified: full world with creatures in **44 s**.
- **Companion banter** — ~25% of calm turns nudge the GM to give a companion a
  line; costs zero extra LLM calls.
- **Economy bands** — shops price by band (everyday 1–10, quality 20–80,
  rare 100+; buys at half, haggling moves ~20%).
- **Lorebook search** — live filter box over every tab; hides emptied groups,
  keeps focus.

## Shipped in the "mobile/polish" pass (2026-07-03)

- **Phone layout** (≤768px): the chat HUD becomes a swipeable horizontal strip
  (verified: 1401px of buttons in a 396px shell), banner chips wrap, side
  panels (sheet/combat/GM/pack) go full-width, overlays fit small viewports,
  the party code shrinks to fit.
- **Touch targets** (`pointer: coarse`): 42px buttons and dice, larger lorebook
  rows and remove/check controls.
- **Art-queue toast**: all 12 image-generation call sites route through one
  tracked wrapper — when a second picture is requested while one is baking,
  a quiet toast says the forge is busy and the story never waits (throttled
  to once per 20s).
- Verification note: this desktop's DPI scaling defeats real narrow-window
  testing; layout verified by injecting the mobile rules into a simulated
  420px shell. Confirm once on a real phone over Tailscale.

## Next up (rough priority)

1. **Two-account playtest** over Tailscale — first friend session will surface
   the real multiplayer bugs (and confirms the phone layout on real hardware).
2. **Guest hero depth** — per-guest inventory and spell slots.
3. **Real music files** — synth pads cover it; CC0 loops would be richer.

## Known ceilings (ponytail ledger)

- Enemy HP scales with player level via a flat multiplier, not a bestiary.
- Rest-risk odds are flat 25% / travel 20%, not locale-aware.
- Custom worlds reuse the 'arcane' ambient + generic currency ("gold").
- Companion AC is a flat 12; no companion classes yet.
- Worldsmith output is single-shot JSON — no iterative refinement chat yet.
