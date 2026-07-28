# Playtest R8 — driving the real exe (2026-07-28)

Not a harness run and not a screenshot audit: the shipped `dist/Mythforge.exe`,
driven by real mouse clicks, playing "The Barrow-Wight's Oath" in **Fimbulreach**
with the banked hero **Corin Vale**.

> **Coverage.** Session 1 reached Day 1 morning before running out of context.
> Session 2 resumed the same save and played through to **Dawn, Day 4** — past
> the Director's three-day ask — across roughly fourteen turns of real input.
> Everything below is first-hand. The untested list in §5 is still long, and
> §5 explains *why* it is long: the reason is itself the session's biggest
> finding.

---

## 1. Fixed, then verified by playing

| # | Was | Verified |
|---|-----|----------|
| F-01 | **Roster cards showed a flag glyph, no portrait** (Director spotted this in a screenshot) | Sister Maren and Corin Vale show their painted faces on the "Who Plays Tonight?" cards |
| F-02 | "walk the anvil's **eleven** runes" — stale since the Cold Anvil was deleted | Reads "10 runes"; counts `STAGES.size()` now |
| F-03 | Opening line said "HP 12, 18 **gold**" while the purse chip said "18 **silver**" | Both read **silver** in Fimbulreach |

**F-01's root cause:** the roster stores the true key in `portrait_key`
(`hero-dm-fimbulreach-freeroam`) and every reader asked for `"hero-" + id`
(`hero-corin vale`), which is not a file. `GameState.hero_portrait_key()` is now
the single answer, and it refuses `heroprev` (the forge's *shared* scratch key —
a hero pinned to it wears the next-forged hero's face).

## 2. Mechanics verified correct — exercised directly

**The rules engine is the healthiest part of the game.** Every number I could
check was right, and the sheet agrees with what the dice actually used.

- **The Six → modifiers.** 16/14/15/11/11/10 → +3/+2/+2/+0/+0/+0. Correct.
- **Armour Class 12** = 10 + DEX 2, unarmoured. Correct.
- **Attack +5** = STR +3 + proficiency +2 — and the live attack prompt read
  `Roll to hit d20 +5 vs AC 14`. The sheet and the dice agree.
- **Passive Perception 12** = 10 + WIS 0 + proficiency 2.
- **Saving throws** — STR +5 ●, CON +4 ●, rest unproficient. Correct for Fighter.
- **Skills** — all eighteen, with Athletics +5 / Intimidation +2 / Perception +2
  proficient (Fighter + Soldier), and unproficient DEX skills at +2. Insight
  shows **+0**, and the live Insight roll used **+0**. Consistent end to end.
- **Ability checks** — `Wisdom (Perception) (proficient) → d20 6 +2 = 8 —
  failure (DC 16)` and `Wisdom (Insight) → d20 18 +0 = 18 — success! (DC 15)`.
  Roll, modifier, proficiency, DC and outcome all correct.
- **Critical miss** — `attack roll → d20 1 +5 = 6 — critical miss!` Natural 1
  detected and named.
- **Short rest** — spends a Hit Die, `d10+2 CON`, heals, decrements the pool.
- **Long rest** — full HP, advances to dawn, and **restores Hit Dice 0/1 → 1/1**.
  Correct 5e behaviour, checked on the sheet afterwards.
- **Time** — Morning → Midday → Afternoon → Dusk → Dawn, day counter to **Day 4**.
- **Weather** — cycles: clear → fog → rain → storm.
- **Quest tracking** — a `◈ The Barrow-Wight's Oath` chip appears in the status
  bar once the quest exists.
- **Suggested actions do update** — they gained "Ask about the task" the moment
  the quest started. *(This corrects session 1's note; they are slow, not static.)*
- **Send is disabled while a turn is in flight.**
- **Icon buttons have hover tooltips** ("Short rest — spend a Hit Die to heal",
  "Long rest — camp for the night").
- **Baked art is landing** — the Inspect card shows a real painted sword, the
  Gear paper-doll has per-slot silhouettes, the Destiny constellation renders,
  the Atlas chart renders, and the sheet portrait is correct.
- **World-true narration** — authored cast (Björn Salt-Tongue, Ingrid the Völva),
  authored places (White Fjord, Fimbulreach), and an item named from the world's
  own material vocabulary ("Korvul Black Iron Shortblade").

## 3. The two that matter most

### R8-06 — four of nine sheet tabs cannot be clicked

**Chronicle and The Table are unreachable at every window size I tried.**
Maximized, **Destiny and Atlas go dead too** — four of nine.

Measured, not inferred:

- Maximized, the live region of the tab rail ends at **x ≈ 813**; the rail is
  drawn out to x ≈ 1178.
- **Hover proves no mouse event arrives.** Gear brightens under the cursor;
  Destiny does not. The buttons are not receiving input, so this is hit-testing,
  not a broken handler — every one of the nine is wired to `_show_page` at
  [character_screen.gd:100](../scenes/ui/character_screen.gd#L100).
- Restore the window and Destiny works, Atlas works, **Chronicle and The Table
  still do not.** The dead span shrinks with the window but never closes.

**Root cause: still unknown — and my first answer was wrong.**

I originally recorded this as "content laid out wider than the window, so the
rightmost tabs render outside the input rect", by analogy with the comment at
[:89–93](../scenes/ui/character_screen.gd#L89). I then wrote an in-engine probe
to confirm it, and **the probe disproved it.** What was ruled out:

- **Geometry is clean.** Every tab sits inside the window. The rail spans
  x 390…1250 in a 1272-wide dialog; overflow is **0.0 px**, at both the default
  size and maximised (2560×2054 → viewport 1280×1027, dialog 1272×1019).
- **Nothing covers them.** Walking the tree at each tab's centre returns the
  identical ancestor chain for Gear, Destiny and Chronicle — MarginContainer →
  HBox → VBox → rail → Button — with no overlay and no extra `MOUSE_FILTER_STOP`
  control in the way. `MythEnvironment` is `MOUSE_FILTER_IGNORE`.
- **It does not reproduce in a probe scene.** The failure needs the real running
  game; a freshly-instantiated sheet behaves.

What the measurements *do* pin down: the dead zone begins **exactly at a tab's
left edge** in both window sizes — logical x = 870 (Destiny) maximised, x = 1062
(Chronicle) restored — and the live span of the rail *shrinks* as the window
*grows* (480 px live maximised vs 672 px restored, in the same 1280-wide
viewport). A geometric overflow cannot produce that inversion.

**Not fixed.** I will not ship a speculative fix for this; the probe already
caught one confident wrong answer and a second would be worse than none. The
next step is an in-game probe against the live scene (warp the cursor along the
rail and log `gui_get_hovered_control()` from inside a real session), not more
static reading.

**Cost meanwhile:** chapter close, the chronicle and the tone knobs are dead
content via the rail. They remain reachable from the **More** menu, which opens
the sheet directly on a page (`_open_character_screen("Chronicle")`,
[game.gd:1593](../scripts/game.gd#L1593)) — a workaround, not a fix.

**Harness note.** `click_driver` prints *"every station clickable, nothing
covered or lost"* on this exact build. It walks stations, not tab rails.

### R8-07 — the player cannot start a fight

Combat only begins when the **GM's own prose** matches a verb pattern —
`_COMBAT_VERBS` at [tag_parser.gd:92](../autoload/tag_parser.gd#L92) — or an
explicit "roll initiative" phrase. Nothing the player types can start it.

Three deliberate attacks over fourteen turns:

1. *"I draw Korvul Black Iron Shortblade and attack the hooded figure."*
   → an attack roll, a natural 1, a miss narrated. **No initiative. No enemy
   turn. No retaliation. No hostility state.** The target "remains still".
2. *"I heave the stone seal off the barrow and shout a challenge to the draugr."*
   → atmosphere, then "the silence holds, awaiting your next move".
3. *"I tear down the veils and charge the thing lurking in the corridor."*
   → "Your charge, however, fails to have any noticeable effect… it remains
   cowered against the wall."

It is worse than a missing trigger. `_foe_bad_re`
([:96](../autoload/tag_parser.gd#L96)) blacklists **`figure`**, along with
`shape`, `sound` and `form` — the GM's most natural way to name an unknown
antagonist. So even when the GM *does* write an attack, the most common phrasing
for a not-yet-revealed enemy can never be promoted to a combatant.

**This is why §5 is long.** The battle grid, line of sight, cover, terrain
blocking, adjacency, initiative order, AC in combat, crits on hits, death saves
and enemy portraits could not be tested, because in fourteen turns of trying I
could not reach combat at all. The tactical layer exists in the codebase
(`scenes/combat/battle_grid.gd`) and is unreachable through play.

## 4. Everything else found this session

| # | Finding | Sev |
|---|---------|-----|
| R8-08 | **Short rest is allowed at full HP and silently burns the Hit Die.** At 12/12 it fired, reported "recover 4 HP, now 12/12", and left Hit Dice 0/1. Pure resource loss, no warning. At 0 dice the button stays enabled, prints nothing, and still spends a GM turn. | **High** |
| R8-09 | **Clicking Send while a turn is in flight silently discards the click.** The typed text stays in the box, nothing signals refusal, and the player believes they acted. I lost a full action to this. | **High** |
| R8-10 | **Location continuity breaks across a long rest.** I made camp at the barrow-mound; the GM woke me in "one of Björn Salt-Tongue's mead-hall guest rooms" — a different place, with no travel between. | **High** |
| R8-11 | **Raw parser tags leak into player-visible prose** — `[[Perception` (truncated mid-tag) and `[Active Perception]` both rendered verbatim in the transcript. | Med |
| R8-12 | **The minimap overlays the transcript.** The corner chart sits on top of the message column and hid the opening ~150px of the thinking indicator and of three narration lines. | Med |
| R8-13 | **The scene backdrop never changes.** One fjord plate served the mead-hall interior, the headland walk, the barrow exterior and the barrow interior, across four in-game days and three weather states. | Med |
| R8-14 | **The Atlas is decoration, not a map.** No place names, no legend, no compass, no scale, no roads, no points of interest — one unlabelled dot. It cannot support a travel decision, and it does not depict the fiction: a *fjord* system reads as scattered lakes. | Med |
| R8-15 | **Sell is offered with no buyer.** The item menu offers "Sell — 3 silver" inside a sealed barrow with no merchant present. *(The Director's "is there someone to sell to" case, answered: no, and the game offers it anyway.)* | Med |
| R8-16 | **A level-1 Fighter has no class features.** Powers lists only "Versatile" — the *Human heritage* trait — mislabelled under "CLASS FEATURES" and duplicated verbatim on Story. Second Wind and Fighting Style exist only as locked Destiny nodes, so the character has zero usable abilities. | Med |
| R8-17 | **Starting equipment is one weapon.** No armour, no shield, no pack, no rations; AC 12 unarmoured. `Pack 1/24` is counting the equipped blade. | Med |
| R8-18 | **"Armour Class 12 · 1 worn"** counts a wielded weapon as *worn*, while the Armour slot reads "—". | Low |
| R8-19 | **Item icon contradicts the item** — "Korvul Black Iron **Shortblade**" renders as a cruciform arming sword. | Low |
| R8-20 | **Destiny labels overlap their nodes, and four separate nodes are all named "Gift of Growth"** — the tree tells the player nothing about what it grants. | Med |
| R8-21 | **Full HP renders as an alarm-red bar** — 12/12 reads as critical damage. | Low |
| R8-22 | **Skills, Powers and Story leave ~700px empty** below a cramped top block. | Low |
| R8-23 | **The item context menu spawns clipped at the window edge** and does not flip. | Low |
| R8-24 | **The play-screen hero ring stays empty** while the *same portrait renders correctly on the sheet*. The sheet's lookup is right and the ring's is not — which localises the fix. *(Refines R8-05.)* | Med |
| R8-25 | **Sleeping in a hostile place has no consequence.** Two long rests inside an opened barrow, with a hostile figure watching, produced no interruption and no ambush; the figure has been "huddled against the wall" for four days. | Med |
| R8-26 | **The GM invents consequences that never happened** — "regaining some of the vitality lost in battle" after a rest, with no battle fought and no HP lost. | Med |
| R8-27 | **Turn latency 45–100 s**, measured across the session (45, 50, 90, 95, 100). This remains the dominant cost of play. | **High** |
| R8-28 | **No XP is ever awarded.** Still `0 / 100` after fourteen turns including an attack, a quest start and four days. Level-up is therefore unreachable by play. | Med |
| R8-29 | The first long rest printed a "Dusk, day 1" time divider; later ones printed none. | Low |
| R8-30 | Each long rest consumes a full dawn-to-dawn day, so two rests took Day 2 → Day 4 and Day 3's daylight never existed. There is no way to rest without losing a day. | Low |

## 4b. Director's own observations (2026-07-28)

Watching the session back, the Director added four. All are real and none were
in my list as stated:

| # | Finding | Sev |
|---|---------|-----|
| R8-31 | **The minimap is not a map.** It reads as a random frozen pond: no key points, no labels, and — the part I missed — **no marker for where the player is**. Add to that the darker grey panel over the mid-section that sits on top of the transcript (R8-12). Together these make it decoration that actively costs legibility. | **High** |
| R8-32 | **There is still a second, working game UI at `localhost:7000`** — and in several respects it is *better* than the Godot client. From the Director's screenshots it has: **Continue** on the title (R8-01, already solved there), **Cast — who you've met**, **Chronicle**, **Party — play with friends**, **Trade at The Ember & Oak** (a real merchant entry point — R8-15), a drag-to-arrange pack with **Load 7.5/23** and slot count, an inline dice tray (d20…d4, `+ mod`, `Check`), **Combat**, **Map**, **Lore**, **Tune the GM**, **Scene backdrop**, **Campaign memory**, **Private notes**, **Save a snapshot**. **We are maintaining two front-ends and the older one is ahead on features.** This needs an explicit decision — port, retire, or declare the web UI the product — not drift. | **P0 decision** |
| R8-33 | **The Cast never updates with who you've met.** Björn Salt-Tongue, Ingrid the Völva and the hooded figure all appeared in play over four days; none were recorded. The web UI has a "Cast — who you've met" panel; the Godot client does not populate one. | **High** |
| R8-34 | **The portrait and the gear paper-doll are different people.** The round portrait and the full-body doll render are commissioned from separate prompts with no shared seed or identity anchor, so the hero's face changes between the two views of the same character. | **High** |

R8-34 compounds R8-24 and R8-02: three separate portrait defects, all from the
same habit of **deriving the hero's likeness at the point of use** instead of
carrying one identity. R8-24/R8-02 are fixed below; R8-34 is not — matching two
diffusion renders needs a shared seed and a locked identity prompt, which is a
real piece of work, not a lookup change.

## 4c. Fixed in this pass

| # | Fix |
|---|-----|
| R8-08 | **Short rest no longer burns a Hit Die at full HP.** `GameState.short_rest()` now has a third branch: unhurt, the hour still passes and features still recharge, but the dice stay in hand. A level-1 hero owns exactly one. Covered by a new assertion in `tests/playthrough.gd`. |
| R8-09 | **Send while a turn is in flight no longer fails silently.** It keeps your text, shakes the field, plays the deny cue and says so: *"The table is still speaking — your words are held, not lost."* |
| R8-24 / R8-02 | **One answer for the hero's face.** Six readers rebuilt `"hero-" + cid` at the point of use; a hero banked in one adventure and played in another owns art under the key they were *painted* with, so the rebuilt key named a file that does not exist — empty ring, and a fresh GPU render of a portrait already owned. New `Art.hero_key()` asks the hero. `ensure_hero_portrait` now returns early when the carried art exists, so an adventure no longer re-commissions a face we have. |

## 5. Still not tested — and why

- **The whole tactical layer** — battle grid, **line of sight**, cover, terrain
  blocking, **adjacency for melee**, initiative order, AC in combat, crits on
  hits, death saves, enemy portraits. *Blocked by R8-07: combat is unreachable.*
- **Spells and spell slots** — *is that spell learned?* The Fighter casts none
  and there is no spells surface to inspect. Needs a caster hero.
- **Merchants and the shop loop** — never met one in four days; only the orphan
  Sell affordance (R8-15).
- **Level-up** — blocked by R8-28, no XP is granted.
- **Chapter close, the chronicle, the tone knobs** — blocked by R8-06, those tabs
  cannot be clicked.
- **Companions**, **the Lore Book filling in**, **equipping/unequipping** (only
  one item ever existed).

## 6. What these two sessions say about method

Session 1's defects were **continuity** bugs — the thing you picked is not the
thing you get. Session 2's are **legality and reachability** bugs — the game
offers actions it cannot honour (Sell with no buyer, a rest that wastes your
last die, a Send that does nothing) and hides ones it can (four tabs, all of
combat).

Neither class is visible to the existing checks. The harnesses assert
*reachability* of screens; the screenshot audits assert *appearance*. Nothing
asserts that an offered action is **legal**, or that a drawn control is
**clickable**. R8-06 is the sharpest example: the tab rail is drawn correctly,
screenshots beautifully, passes any visual audit — and four of its nine buttons
have never worked. It took hovering the cursor to see it.
