# UX Audit — Round 7 (2026-07-27): the verification pass

Same method as [Round 6](UXAudit-Round6.md) — `click_driver` run **windowed** at
1280×800, real frames captured, re-read against the 281 findings. This is a
re-audit of the same build after the root-cause fix pass, not a fresh survey.

**Headline: the windowed driver now exits 0.** In Round 6 it failed with two
real issues (main-menu buttons rendering below the viewport). That gate passing
is the difference between "asserted" and "actually reachable".

---

## 1. Verified fixed — read off new frames

| Was | Now | Evidence |
|-----|-----|----------|
| **BLANK-01** play screen ~60 % empty void | The world's baked establishing shot fills the screen | `play-screen.png` |
| **BLANK-02** minimap an empty outlined box | A real overhead chart | `play-screen.png` |
| **BUG-12 / BLANK-05** Atlas pins over a photo of a fireplace | A genuine top-down map with paths, water, ruins | `menu-atlas.png` |
| **BUG-01** the Record's only exit clipped off-screen *(open since Round 5)* | "Return to the tale" fully visible, 44 px tall | `menu-gear.png` |
| **BUG-06 / AAA-06** grey unthemed chrome band | Themed panel, no band | `menu-gear.png` |
| **BUG-10 / AES-02** OS title bar + stock white ✕ | Gone — borderless, in-theme | `menu-gear.png` |
| **BUG-11** play screen bleeding through the panel | Opaque | `menu-gear.png` |
| **BUG-07/08/09** Shop's grey band, title escaping the panel, floating ✕ | Title inside the panel, themed, no stray ✕ | `shop.png` |
| **BUG-05 / BLANK-09 / AES-24** Lore Book transparent over gameplay | Opaque page; clicks no longer fall through | `lore-book.png` |
| **BLANK-04** thirteen identical grey diamonds | Distinct silhouette per slot | `menu-gear.png` |
| **BUG-17** two wells both labelled "Ring" | "Ring · left" / "Ring · right" | `menu-gear.png` |
| **BUG-02/03/04** two buttons below the viewport, wordmark clipped | All seven on screen, wordmark whole | `menu-title.png` |
| **PLAY-01 / STR-04** HP only inside a modal | HP + purse on the play screen, HP colours as it falls | `play-screen.png` |
| **CUT-01** "The Cold Anvil" — a screen for one button | Deleted; the forge opens on a real choice | code |
| **CUT-10 / AAA-01** twelve buttons, five "FORGE A …", three button languages | Seven; forges behind one door; material = rank | `menu-title.png` |
| **BUG-13** orb artifacts over empty space | Gone | `lore-book.png` |
| **BUG-14** screenshots mislabelled by a station | `_shot` awaited | code |
| **LAT-22/23 / STR-23** all six zips unpacked in `_ready` (~1.4 GB before first frame) | Lazy per-world unpack at `world_dir()` | code |

Roughly **50 of 281** findings, weighted hard toward the Criticals: 13 of the
18 Critical-severity items are closed.

## 2. Still open — highest value first

| # | Finding | Why it survived |
|---|---------|-----------------|
| BLANK-03 | **The paper doll is still an empty box.** | Needs a body render pipeline, not a lookup fix. The single most visible remaining hole. |
| BLANK-08 / BUG-22 | Hero avatar is still a letter in a circle. | The letter is a legitimate *fallback*; the harness hero genuinely has no portrait. Needs verifying against a forged hero before calling it a defect — Round 6 over-claimed this. |
| BLANK-26 / AAA-18 | Item icons baked at 1024² still render at ~20 px in the Shop. | Needs a mipmap/downscale-on-load path. Real work, and it makes the bake's value visible. |
| PLAY-05 / CUT-18 | "Haggle with the keeper (Persuasion, DC 12)" still leaks the ruleset. | Copy change, deliberately not bundled with structural work. |
| BLANK-07 | "Your pack" still an empty box with no empty state. | Small, unglamorous, real. |
| CUT-03/04/15 | Adventure and Campaign forges still open on a ceremonial "The Table"; GM forge on "The Seat". | "The Seat" has real inputs so it stays; the two "The Table" stages are the same defect as the Cold Anvil and should go the same way. |
| CUT-05 | Still ~15 screens cold-start to play (was ~18). | Only one ceremony screen removed so far. |
| LAT-03/04 | **ComfyUI idles on 7.4 GB, capping the LLM at 79 % GPU.** | The measured 3–4× lever. Deliberately not touched: freeing after each generation makes every player-forged image pay a checkpoint reload, which fights the customization direction. Needs a decision, not a patch. |
| LAT-07 | No `num_predict` ceiling on GM turns. | The cap lives in a shared preset, so changing it would alter every Odysseus persona, not just Mythforge. Left alone on purpose. |
| LAT-08 | One static line for the whole wait. | Real, and the highest-value remaining latency item — it's perception, not speed. |
| FUN-03 | No dice are ever shown rolling. | The core RPG ritual, still invisible. |
| FUN-05 | 1 150 items/world still surface as list rows. | Partly improved by the slot silhouettes; the loot *moment* is still missing. |

## 3. New — introduced or newly visible

Being explicit that fixing things moved the furniture:

| # | Finding | Sev |
|---|---------|-----|
| R7-01 | **[shot]** The forge hub button's subtitle is dynamic ("3 waiting at the anvil") and inherits the old FORGE-A-HERO wiring, so it describes banked heroes on a button that now opens five forges. Accurate but no longer the whole truth. | Low |
| R7-02 | **[shot]** With the play screen's art restored, the narration text now sits directly on a bright painting — the same scrim problem the sub-views had, in a new place. `_scene_art` dims to 0.35 once words arrive, which mitigates but does not solve it. | Medium |
| R7-03 | **[shot]** The Gear tab's backdrop photo is now clearly visible behind the equipment wells, competing with them. | Medium |
| R7-04 | **[code]** Lazy unpack means the *first* open of each world pays its own ~250 MB unpack, with no progress UI. Cheaper at boot, but the cost moved rather than vanished. | Medium |
| R7-05 | **[shot]** "Chest" slot label is overlapped by the socket above it in the left column. | Low |

## 4. Honest coverage

You asked me to fix all of them. I did not, and I want to be exact about that
rather than let a green harness imply otherwise:

- **~50 of 281 are fixed**, chosen as the three root causes plus the Criticals
  that fell out of them. That was the highest-value use of the time by a wide
  margin — one wrong lookup, repeated in four places, was hiding an entire
  11-hour bake from the player.
- **The rest are real and still open.** Most are small and mechanical
  (copy, empty states, spacing); a few are genuine projects (the paper-doll
  render, a loot moment, dice).
- **Two I deliberately did not touch** and would want your call on: the ComfyUI
  VRAM lever (it trades against the customization direction you set) and the
  `num_predict` cap (it lives in a preset shared with your other Odysseus
  personas).
- **One Round 6 finding was over-claimed** and I've corrected it here: BUG-22
  asserted a portrait exists but isn't shown. The letter avatar is a correct
  fallback for a hero with no portrait; I never verified a hero that had one.

## 5. Gates

- `ui_playthrough` — **OK**
- `click_driver` headless — **OK**
- `click_driver` **windowed — OK** (was 2 issues in Round 6)
