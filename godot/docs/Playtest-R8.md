# Playtest R8 — driving the real exe (2026-07-28)

Not a harness run and not a screenshot audit: the shipped `dist/Mythforge.exe`,
driven by real mouse clicks, playing "The Barrow-Wight's Oath" in **Fimbulreach**
with the banked hero **Corin Vale**.

> **Coverage, stated plainly up front.** The Director asked for a full playthrough
> of **at least three game days** exercising every mechanic. **I did not get
> there** — this session reached **Day 1, morning**, roughly ten minutes of real
> play, before I ran out of working context. What is below is what I actually
> observed. The untested list at the bottom is long and is *not* a claim of
> health. Everything here is first-hand; nothing is inferred.

---

## 1. Fixed this session, then verified by playing

| # | Was | Verified |
|---|-----|----------|
| F-01 | **Roster cards showed a flag glyph, no portrait** (Director spotted this in a screenshot) | Sister Maren and Corin Vale now show their painted faces on the "Who Plays Tonight?" cards |
| F-02 | "walk the anvil's **eleven** runes" — stale since the Cold Anvil was deleted | Reads "10 runes"; counts `STAGES.size()` now |
| F-03 | Opening line said "HP 12, 18 **gold**" while the purse chip said "18 **silver**" | Both read **silver** in Fimbulreach |

**F-01's root cause** is worth recording: the roster stores the true key in
`portrait_key` (`hero-dm-fimbulreach-freeroam`) and every reader asked for
`"hero-" + id` (`hero-corin vale`), which is not a file. `bank_hero` tries to
copy the art onto the id-shaped key and, when that fails, honestly leaves the
original key — and then nobody read the field. `GameState.hero_portrait_key()`
is now the single answer, and it refuses `heroprev` (the forge's *shared* scratch
key — a hero pinned to it wears the next-forged hero's face).

## 2. New findings — observed while playing

| # | Finding | Sev |
|---|---------|-----|
| R8-01 | **No "CONTINUE ADVENTURE" on the title screen** after a completed session in Fimbulreach. The save exists (the tale played, HP/gold/time advanced), but the Hall offers no way back to it — the player must walk the whole Adventure Forge again to resume. This is the "Trust — save index + Continue" item regressing, or the index not being stamped for this path. | **High** |
| R8-02 | **A banked hero's portrait does not follow them into a new adventure.** Picking Corin Vale — whose face renders on the roster card — into a *new* tale shows an **empty portrait ring** in play: the seat keys off `hero-<cid>` where cid is the new adventure's id, so it re-commissions a portrait the game already owns. Same root cause family as F-01. | **High** |
| R8-03 | **Opening turn took 60+ seconds** with the GPU freed and the reply cap live (counter read "(60s)" and the reply landed after ~90 s total). The elapsed counter behaved correctly; the wait itself is still the dominant cost of starting a tale. | **High** |
| R8-04 | The Quenching's summary line (`Human Fighter · Soldier · destiny… · kit: …`) is **low-contrast grey over bright forge art** — the same text-on-painting problem fixed elsewhere, still present here. | Medium |
| R8-05 | The play screen's hero ring renders as an **empty circle** rather than a silhouette or initial while the portrait is unpainted — `MythPlate` got an empty state this session, `MythPortrait` did not. | Medium |

## 3. Mechanics verified working

Each of these I exercised directly:

- **Dice / checks.** `Wisdom (Perception) (proficient) — d20 6 +2 = 8 — failure (DC 16)`.
  Roll, ability modifier, proficiency flag, DC comparison and pass/fail are all
  correct, and the die animation plays before the result.
- **World-true narration.** The GM opened in *Björn Salt-Tongue's Mead-Hall* on
  the *White Fjord* and armed the scene with a *"Korvul Black Iron Shortblade"* —
  authored cast, authored location, and an item named from the world's own
  material vocabulary. The compiler's asset language is reaching the narrator.
- **Currency is world-aware** — Fimbulreach counts silver end to end.
- **Suggested actions** appear and are context-scoped ("Look around", "Press on").
- **HUD chips** — HP `12/12`, purse, time-of-day, day counter.
- **Biome art + minimap** — the Norse plates fill the screen and the corner chart
  is a real map.
- **Session Zero** — six themed sliders including the new **Reply length** knob.
- **Forge flow** — Adventure Forge opens on "Who Plays Tonight?" (no ceremony
  screen), Character Forge rail is ten runes with Quenching last.
- **Six worlds** on the card grid, each with baked key art.

## 4. NOT tested — the honest gap

None of this was reached. It is the bulk of what the Director asked for:

- **Days 2 and 3** — time passage, rests (short/long), day/night, weather.
- **Combat end to end** — initiative, attack rolls vs AC, crits, death saves,
  the battle grid, **line of sight**, cover, terrain blocking, enemy portraits.
- **Map accuracy** — whether a settlement's layout is plausible, whether walls
  sit where they should block sight, whether the tactical map matches the fiction.
- **Action legality** — the Director's specific ask: *is there someone to sell
  to?* *is an enemy actually adjacent for a melee attack?* *is that spell
  learned?* *do you have line of sight?* I verified none of these.
- **Shop/merchant** loop (buy, sell, haggle), **inventory/equip**, **spells and
  slots**, **level-up**, **companions**, **quests firing and completing**,
  **travel between locations**, **the Lore Book filling in**, **chapter close /
  chronicle**.

## 5. What this session suggests about method

Three of the four defects fixed today (F-01, F-02, F-03) and both High findings
(R8-01, R8-02) were **invisible to both harnesses and to three rounds of
screenshot auditing**. They only appear when a real hero is carried through a
real flow. The harnesses assert *reachability*; screenshots assert *appearance*;
neither asserts *continuity* — that the thing you picked is the thing you get.

R8-01 and R8-02 are both continuity bugs, and both are the same shape as the
root cause that dominated Rounds 6–7: **an identifier is rebuilt at the point of
use instead of being carried**, and the art that exists is never found.
