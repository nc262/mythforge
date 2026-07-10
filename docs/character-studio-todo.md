# Mythforge — TODO / Gap Checklist

The living list of what's still missing to make this a *complete* D&D-style game.
Ordered by impact within each group. Checked = shipped. Keep this current as
gaps are filled or found. (Shipped history lives in `character-studio-roadmap.md`.)

## 🎲 Core rules mechanics
- [x] Heritage / species (ability bonuses, speed, darkvision, traits)
- [x] Spell save DC + spell attack bonus (casting ability per class)
- [x] Concentration (one at a time; CON save on damage)
- [x] Passive Perception
- [x] Conditions → advantage/disadvantage on the player's rolls (incl. skill checks)
- [x] **DM Inspiration** — HUD chip, awarded by the GM, armed & spent for advantage
- [x] **Full standard conditions** — stunned, paralyzed, grappled, incapacitated,
      deafened, petrified, unconscious, etc. (adv/dis + effects fed to the GM)
- [x] **Feats** as an ASI alternative at level-up (12 feats, 2 ASI points each;
      Tough/Alert/Observant/War Caster are mechanical, rest GM-honored)
      *(verified live: kill at 2680 XP → L4 overlay → 12 feats offered → Tough
      picked → hpMax +2×level applied, feats=['Tough'] persisted)*
- [x] **Exhaustion track** (6 levels, real 5e penalties): +/- on the sheet,
      one level per long rest, level 6 = death; GM enforces active penalties
- [x] **Deeper table rules — GM-honored** (in every GM charter; the model runs
      them in fiction, the client keeps the core numbers): weapon properties,
      cover bands, cantrip scaling at 5/11, attunement (max 3), opportunity
      attacks, weakness/resistance bite, light & darkness, surprise rounds,
      foes applying conditions (+ advantage vs prone/restrained), traps,
      reaction rolls by disposition, downtime activities
- [x] Damage resistances as client-side MATH — `_DEFENSES` table (24 creatures:
      skeleton resist piercing/slashing + vuln bludgeoning, trolls/golems vuln
      fire, wraiths/specters resist all physical, dragons resist their element…)
      merged into the BESTIARY; `_weaponDmgType` + `_playerAttack` double on
      vuln / halve on resist, with an inline damage tag in the hit bubble
      *(verified: Skeleton vs shortsword → "3 damage (resists slashing)")*
- [x] **Subclasses** (light-but-real): at level 3 the level-up overlay requires
      choosing one of two paths per class (24 subclasses — Champion/Battle
      Master, Thief/Assassin, Life/War, Evoker/Abjurer…); the choice is
      permanent, shows on the sheet, and the GM honors the path's signature
      moves. Per-path resource pools now tracked client-side too: `SUBCLASS_GRANTS`
      + 10 subclass FEATURE_ACTIONS (Combat Maneuver/superiority dice, Channel
      Divinity, Ki, Rage, Bardic Inspiration…) with per-rest charges and Use
      buttons on the sheet; Champion crits on 19–20, Hunter's Colossus Slayer
      +1d8 vs wounded, Draconic Sorcerer HP bump, Fiend temp-HP on kill are
      wired into the damage/finish path *(verified live: Combat Maneuver pool
      4/4 → Use → 3/4, superiority die spent in the bubble)*
- [x] **Multiclassing** (light-but-real): each level-up offers *advance your class*
      or *branch into a new one*. Per-class levels tracked in `s.classes`
      (`[{cls, levels, subclass}]`, synthesized for old single-class sheets so
      nothing breaks). The chosen class drives that level's hit die, features,
      and its own subclass at its level 3; spell slots grow to the **combined**
      effective caster level (full casters full, Ranger/Paladin at half); DC/attack
      come from the caster class with the most levels. 5e-style prereq gate (13 in
      the key stat). *(verified live: Rogue 4 → Fighter 1 with d10 HP → Wizard 1
      granting L1 slots; classes=[Rogue 4, Fighter 1, Wizard 1])*
      ponytail: multi-level XP jumps advance the primary class; Warlock counts as
      a full caster (pact magic not split out) — both fine at this scope.
- [ ] Flanking *(optional rule — deliberately skipped)*

## ⚔️ Combat depth
- [x] Initiative, turn order, attack rolls vs AC, crits, death saves
- [x] Player attack / flee actions; enemy HP scaling
- [x] Companions + guest heroes in combat
- [x] Surprise / enemy conditions / attacker-advantage — GM-honored (see above)

## 🗺️ Exploration & world
- [x] Travel map, "you are here", random encounters, rest risk
- [x] World clock + weather
- [x] Light & darkness, traps, downtime — GM-honored (see above)

## 👥 Social & party
- [x] NPC dispositions, factions, reputation/renown, bonds
- [x] Companion banter, shared-party multiplayer
- [x] Party **voice chat** — WebRTC mesh over the tailnet (🎙 chip by the party
      chip; server only relays signaling) *(relay verified; two-machine audio
      rides on the standing Tailscale playtest)*
- [x] Reaction rolls by disposition — GM-honored (see above)

## 🧑‍🎨 Character & content
- [x] 12 classes, 9 heritages, 8 backgrounds, class kits, level-up spell learning
- [x] Lorebook: bestiary / grimoire / classes / world lore, with art
- [x] **📜 Rules tab** in the Lorebook: checks & DCs, combat actions & cover,
      every condition's effect, resting & death saves, the full feats list
- [x] **Bestiary depth**: 84 creatures (was 26) across minor/standard/dire and
      all three prebuilt worlds — plus 6–8 unique beasts per forged world
- [x] **Spell circles 3–5**: 58 spells total; casters climb the real 5e curve
      (circle 3 at level 5 … circle 5 at level 9; the slot table already matched)
- [x] **Companion / Game Master forge**: "New companion" opens the studio forge;
      a toggle forges a custom GM (full 5e charter + their personal style,
      lands with the whole adventure HUD)

## 🎮 Game-feel & QoL
- [x] Title screen, key art, campaign finales, Chronicle archive
- [x] Mobile layout, touch targets, art-queue toast
- [x] Undo on manual sheet edits (↺ restores the sheet as it was when the
      panel opened) + **⤓ sheet export** (readable text file)
- [ ] First-run interactive tutorial (beyond the how-to card)
- [ ] Real CC0 ambient music loops (synth pads cover it; needs asset downloads —
      ask before fetching)

## 🔐 Multi-account (friends-ready)
- [x] **Templates are per-player now**: characters/adventures carry an owner;
      lists are owner-filtered, cross-owner save/overwrite and delete are 403,
      owners can delete their own (no admin needed). Existing templates
      migrated to the admin. Deterministic campaign ids auto-suffix per player
      on collision, so two people can each run "Embervale: Free Roam".
      *(verified live with a second account: isolation, round-trip, 403s)*

## 🎧 Playtest feedback (2026-07-06) — the live punch list
Fixed & verified headless (fresh account, Playwright):
- [x] Refresh landed in the legacy chat UI → game mode now always boots to the
      title screen; stale `#session` hashes are stripped; auto-restore is off
- [x] "Nobody" button broke the landing → hidden in game mode (with the /setup
      welcome text)
- [x] Home Settings did nothing (dead `rail-settings` id) → opens the settings
      modal; "More tools" removed from the title screen
- [x] Companions → **"Chat with a Companion"**
- [x] Forge tab forged characters → **World Forge** (opens the worldsmith);
      Roster's card is now **"Create new character"**
- [x] ✕ in the corner → **"⌂ Title screen"**, and closing always lands on the
      title screen
- [x] Continue only loaded the last save → save-file list of ALL campaigns
      (world · hero · level · day · 🏁), latest tagged
- [x] Play-as listed every roster character + a custom button → now only YOU
      and the NPC companions currently in your party

Fixed (code shipped; verify in play):
- [x] Could start Neon Spire with no character → creation gate can no longer be
      skipped (✕ cancels the start; name + class required) and 4 **prebuilt
      heroes** are one click
- [x] Character forge: race/class dropdowns now seed an **editable portrait
      prompt** ("half-elf ranger" + "male, balding…")
- [x] Purse wasn't visible in the Pack → purse chip + trade button at the top
- [x] Selling worked anywhere → selling now needs a vendor (shop location)
- [x] Vendor buy/sell counter: deterministic wares + prices (UI is canon so the
      keeper can't forget the DM's price), sell-from-pack, haggle stays roleplay
- [x] "Shield module" typed as misc → misc items re-classify from their name on
      inspect/equip; rejected equips explain themselves (toast) instead of erroring
- [x] Map items did nothing → 🗺 **Study** action asks the GM to chart new
      locations onto the world map

Still open from the feedback list:
- [x] **Renamed to Mythforge** — page title, title-screen brand, studio topbar,
      login page, manifest/PWA, favicon (boat → ✦ spark, incl. the theme-driven
      redraw in theme.js), README, installer scripts. Internal ids (pm2 app,
      repo dir, localStorage keys) intentionally unchanged.
- [x] **De-platform (pass 1)**: game mode hides Email, Models, and the old
      workspace tools from the sidebar (chats/search/Gallery/game/Theme stay);
      refresh + Nobody + dead buttons were killed in pass 1 of the punch list
- [ ] **De-platform (pass 2)**: trim the Settings modal to game-relevant tabs;
      consider bundling ComfyUI into the installer flow (install.ps1 already
      analyzes hardware and installs the stack)
- [x] **World-adapted classes** (mechanism): pick a standard class, the world
      renames it — Neon Spire Wizard = "Body Modder" (slots = mod charges),
      Everyday Rogue = "Hustler" (slots = grit). Shows in the class dropdown
      ("Wizard ✦ — Body Modder here"), seeds the portrait prompt, lands on the
      sheet, and the GM is ordered to use the world's words. Custom worlds
      honor a `reskins` object on the world — *generating* it in the world
      forge belongs to the pregen pass below.
- [x] **Lorebook depth**: 84 shared beasts + 6–8 unique per forged world with
      pre-generated art; the world forge generates the `reskins` table (and its
      flavor line re-skins how ALL casting is described in that world)
- [x] **Guided world forge**: 5 pillar fields with one-tap suggestions (magic
      system / technology / era / beast variants / tone) + 🎲 Surprise me; every
      pillar is honored by every generation call. The forge now makes 4–6 small
      LLM calls (core → locations fallback → cast+stories → stories fallback →
      6-beast bestiary → class reskins) so no section comes back empty — 4/4
      live runs produced complete worlds in 3–5.5 min
- [x] **Pictures pre-generated**: creating a world queues its whole picture
      book (world portrait → cast faces → every bestiary creature into the
      lorebook's art cache) with a visible progress chip; players never press
      "Conjure" for a forged world *(queue mechanics verified; a full
      create-to-illustrated run is a play-session check)*
- [x] **A picture for every world**: the worlds gallery bakes missing card art
      in the background — prebuilt worlds included *(verified live: a fresh
      browser painted its first card in under 2 minutes)*
- [x] **Location scenes on travel** (first pass): arriving anywhere repaints
      the chat backdrop as THAT place (baked once per place, cached) and the
      GM must describe the layout and NAME who's present (keepers, vendors,
      patrons — plus wares if it's a shop)
- [ ] **Location floor-plan maps** (interactive tactical layout per building)
      — the backdrop+roster pass above covers the fiction; a real per-location
      map grid is a bigger feature for later
- [x] **Top banner**: regrouped — 6 primary chips (Sheet/Pack/Quests/Combat/
      Map/Lore, gold-glow styling) + a "⋯ More" menu holding the other 11
- [x] **Voice chat** for party members — self-hosted WebRTC mesh, 🎙 chip
      beside the party chip (see Social & party above)
- [x] **Companion forge** from "Chat with a Companion" — the studio forge with
      a Companion / Game Master toggle (see Character & content above)

## 🎮 QA playthrough findings (2026-07-07 — fresh account, full session)
Fixed & re-verified in play:
- [x] CRITICAL: friends couldn't start ANY adventure (session create sent raw
      endpoint_url without endpoint_id → SSRF guard 403). Fixed; opening scene
      verified on the non-admin account.
- [x] Forged worlds had no working vendors (worldsmith omits `shop` text; all
      vendor gates keyed on it). Shops/taverns now count as vendors; server
      defaults the trade text. Verified: tavern counter, buy bread, sell sword,
      purse math exact (25 − 1 + 3 = 27).
- [x] Combat XP required pressing End after VICTORY — now auto-finishes when
      the last foe falls. Verified: +25 XP → Level 3 overlay → subclass
      enforced → Thief on the sheet (21/21 HP).
- [x] The GM's own rules talk spawned a foe named "Opportunity" — foe-name
      blacklist extended with rules vocabulary.
- [x] Cookbook pollers spammed 403s for players; PWA icons 404'd; Continue
      caption showed stale level/day; snapshot save had no feedback.
Still open from the playthrough (see the session report for the full list):
- [ ] Inventory sync race: a sale made just before closing the tab was
      resurrected on next load (last-writer-wins between local cache and
      server state) — needs a versioned merge or save-on-change flush
- [ ] Snapshot save produced no Chronicle entry on the test account —
      investigate the snapshot endpoint under non-admin
- [ ] Forge-time cast portraits don't show on the world-detail cast cards
      (initial letters shown despite baked avatars)
- [ ] Composer placeholder says "Say something to ‹campaign title›…" — should
      be "What do you do?" in adventures
- [ ] Selling an equipped item needs a confirm

## 🎮 Playtest round 2 (2026-07-07 — user's detailed session)
Fixed & verified (real mouse clicks, fresh account):
- [x] **More-menu items were visible but dead** below the banner band — the
      transparent chat scroller hit-tested above the banner's stacking context
      (equal z-index, DOM order). Banner raised; 10/10 menu items now open.
- [x] **Escape quit the whole game** through open overlays → now peels one
      layer at a time (overlay → panel → menu) and never exits a live chat.
- [x] Hero gate: portrait no longer floats over the form when scrolling;
      picking a prebuilt swaps the portrait too; **✨ Start fresh** gives a
      blank slate; copy explains a NEW hero is created (nothing overwritten).
- [x] **Backstory field** on the gate — canon for the GM, saved on the sheet.
- [x] Ability clarity: note that heritage bonuses are added on top of base
      scores at start, and backgrounds grant skills, not scores.
- [x] **Kits no longer over-encumber**: lighter gear weights, 5 rations, worn
      gear counts half — and starting weapons/armor arrive EQUIPPED
      (verified: 3 equipped, load 8.5 / cap 30).
- [x] Loot detector no longer pockets gestures ("an Inquisitive Wave") —
      social/abstract noun blacklist.
- [x] Bare dice rolls carry no fiction: the GM is told to ask what an
      undeclared roll was for, and to CORRECT wrong dice/ability calls.
- [x] Charter: the GM may never refuse a fight the player picks — one
      "*Are you sure?*" for outrageous targets, then "*Roll for initiative!*"
- [x] Save list readability (bigger rows, legible captions).
- [x] Your hero's **portrait rides your own chat bubbles** (stored on the sheet).
- [x] Pack: hero portrait beside the gear slots (first paper-doll step) +
      **🎨 Illustrate pack** paints every item lacking art.
- [x] Lorebook: **🎨 Illustrate all** per tab — no more per-entry clicking.
- [x] Inventory sync race: state writes flush with keepalive + on tab hide.
- [x] Snapshot endpoint verified working for players (12s; toast feedback added).
- [x] World-detail cast cards show their baked portraits.
- [x] Adventure composer placeholder is "What do you do?".
- [x] Selling equipped gear asks first.

Design passes — ALL SHIPPED (2026-07-07, verified with screenshots):
- [x] **Diablo-style menus**: every overlay/panel paints over the current
      world's key art behind a heavy scrim with an inner gold frame; the Pack
      is a full paper-doll (11 slots around the hero portrait)
- [x] **World map as art**: generated hand-drawn region map per world, fog of
      war (unvisited = dimmed cloud-marks, travel lifts it), scene-art markers
      for visited places, glowing you-marker; **🗺 Local map** per place draws
      a floor plan (interiors) or street map (settlements) + "Who's here?"
- [x] **NPC speech portraits**: the speaker's face floats at the head of any
      paragraph where a codex NPC speaks — live and on reload
- [x] **Dice skins**: six sets in ⋯ More → Dice skins, per-player, persisted
      *(generated custom dice = future nicety)*
- [x] Character sheet as an aged scroll (leather-dark fiber, rod header)
- [x] Portrait prompt adherence: bridge was turbo @ 6 steps / CFG 2.0 —
      raised to 8 / 2.8 (top of turbo's range) and restarted
- [x] Region-map garbled title cartouche — map prompts hardened to
      "completely unlabeled, no lettering, no writing, no title cartouche"
      (+ the CFG 2.8 bump helps the model honor it)
- [x] First-run spotlight tour (`_startTour`, `_TOUR_STEPS`) — ring + tip card
      walks a new player through the HUD once (flag `studio-tour-done`,
      Skip/Next); fires beside the how-to-play on the first chat open
      *(verified live: tour ring visible on a fresh save)*
- [x] Settings trimmed in game mode — search/integrations/email/reminders tabs
      hidden; only services/ai/appearance/shortcuts/account show
      *(verified: tab list == "services,ai,appearance,shortcuts,account")*

## 🧪 Verification debt
- [x] Subclass level-up walkthrough — verified live in the QA playthrough
      (End fight → XP → Level 3 → path choice enforced → sheet updated)
- [x] Feats pick in play — verified live (kill at 2680 XP → L4 overlay → 12
      feats → Tough picked → hpMax +2×level applied, feats=['Tough'] persisted)
- [ ] Two-account Tailscale multiplayer playtest (real hardware) — now also
      covers voice audio and per-player template isolation in anger
- [ ] Phone layout confirmed on a real device
- [ ] Full world-forge run in the browser (guided form → create → watch the
      pregen queue illustrate everything) — all stages verified separately
- [x] Multi-account privacy: templates are per-owner now (see 🔐 above).
      The throwaway login `playtest-claude` remains for testing — delete from
      user management whenever.
