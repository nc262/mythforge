# Mythforge Interaction Language (MIL)

**The standard for every interaction in the game.** MDL
([DesignSystem.md](DesignSystem.md)) governs how things *look*; MIL governs how
things *behave when touched*. The World Style Guide
([WorldSkin.md](WorldSkin.md)) supplies the vocabulary both draw from.

If an interaction is not described here, it is not finished — either implement
the matching pattern, or extend this document first and then implement it.
**No one-off interaction behaviour.** Ever.

---

## THE LAW: beginning, middle, end

> The player must never feel that data changed.
> They must feel that **something happened**.

Every meaningful interaction has three acts. An interaction that skips an act
is a bug, not a shortcut.

| Act | Purpose | Typical carrier |
|---|---|---|
| **Beginning** — *anticipation* | "this is touchable, and I am touching it" | hover lift + glow + hover sound; press depress |
| **Middle** — *transformation* | the world visibly changes | the animation of the thing itself (a piece slots into a socket, a card flips, a bar fills) |
| **End** — *consequence + rest* | what it cost, what it gained, and a return to calm | stat delta rises, confirmation sound, control settles to idle |

**Worked reference — equipping a longsword:**

```
hover socket        → lift 1.045, gold rim warms, ui_hover        (beginning)
press               → depress 0.96, ui_click                      (beginning)
release             → item art flies card → socket (180ms)        (middle)
                    → socket flares gold, ring pulses             (middle)
                    → doll render tints/updates                   (middle)
                    → "+2 AC" rises off the stat line             (end)
                    → equip sound                                 (end)
                    → everything settles to idle within 500ms     (end)
```

Total budget: **≤ 600 ms**. Longer than that and the player is waiting, not
being rewarded. Nothing in MIL may block input — every act is skippable by
acting again.

---

## 1. Timing and easing

The only timing numbers allowed are `Ui.TIME`. New values require an edit here
and in `skin.gd` together.

| Token | Value | Used for |
|---|---|---|
| `fast` | 0.12 s | hover, press, tooltip fade, micro-feedback |
| `base` | 0.22 s | reveals, tab swaps, stat deltas, window ritual |
| `slow` | 0.45 s | scene transitions, ceremony beats, art crossfade |
| `breath` | 3.2 s | idle breathing loops (portraits, candles, waiting states) |

**Easing law:** ease **out** on arrival, ease **in-out** on round trips.
Exponential family only — `TRANS_QUAD`, `TRANS_CUBIC`, `TRANS_QUART`,
`TRANS_EXPO`, `TRANS_SINE` (idle loops).

**Banned:** `TRANS_BOUNCE`, `TRANS_ELASTIC`, and any overshoot on UI chrome.
Mythforge is candlelit and heavy — nothing springs.

---

## 2. Hover

Applies to every `Button`, card, socket, tab, map pin, and list row.

| Layer | Behaviour |
|---|---|
| Motion | scale → **1.045**, `fast`, ease-out quad (`Ui.polish` already does this) |
| Light | border/rim colour → `gold` at 0.55α; material plates raise their top highlight |
| Cursor | `CURSOR_POINTING_HAND` on anything clickable — **no exceptions** |
| Audio | `ui_hover` — quiet, ≤ 60 ms, at most one per 80 ms (rate-limited globally) |
| Tooltip | arms a 450 ms timer (see §10) |

**Rules**
- Hover state must be *visible without motion* (the rim), so reduce-motion users still perceive it.
- Disabled controls do **not** hover, do **not** sound, and carry a tooltip explaining *why* they're disabled.
- Nothing may change layout on hover. Lift is scale-only; no reflow.

## 3. Click / press

| Phase | Behaviour |
|---|---|
| Press down | scale → **0.96**, `fast`; `ui_click` fires **on press, not release** (perceived latency) |
| Held | hold the depressed state; no repeat sound |
| Release inside | return to hover scale 1.045, `fast`; the action's *middle* act begins |
| Release outside | return to 1.0, `fast`, **no** action, **no** sound |

**Rules**
- A click that does nothing must still respond — if the action is refused, run the **error** pattern (§5), never silence.
- Destructive or irreversible controls (delete a save, leave to the Hall mid-scene) require confirmation, and the confirm button uses `AccentButton` + `ui_open` ritual.
- Double-click is never the *only* way to do something.

## 4. Success feedback

Fires when the engine has actually committed the change.

1. **The thing moves** — item flies to its socket, star lights on the tree, coin leaves the purse. `base`, ease-out.
2. **Shimmer** — a brief `Ui.pulse` on the changed element (scale 1.0→1.06→1.0, `fast`), plus a gold glow at 0.35α fading over `base`.
3. **Floating delta** — `Ui.rise_text` for every numeric change the player cares about: `+2 AC`, `−40 gold`, `+150 XP`, `−7 HP`. Gold for gain, `danger` for loss, rising 34 px over `slow`.
4. **Audio** — the specific reward sound (§12), never a generic click.
5. **Rest** — everything settles; no lingering glow after 600 ms.

**Rule:** if a number on screen changed and no delta rose, the interaction is incomplete.

## 5. Error / refusal feedback

Never a silent no-op. Never a raw engineering string.

| Layer | Behaviour |
|---|---|
| Motion | horizontal shake — 3 oscillations, ±5 px, decaying, 260 ms total |
| Colour | border pulses `danger` at 0.7α → 0, over `base` |
| Audio | `ui_deny` — muted, low, short; deliberately unsatisfying |
| Words | one sentence, in the world's voice, saying *what* and *why*: "Not enough gold for the lantern — you carry 12, it asks 15." |

**Rules**
- Never show HTTP status codes, exception text, node paths, or the word "null" to a player.
- Errors that are the *system's* fault (backend down, art forge stalled) are phrased as the world faltering, plus a retry affordance — never blame the player.
- Refusals that are *rules* ("not your turn") are stated as rules, and point at the fix ("press Next › to advance").

## 6. Loading and waiting

**The screen may never be frozen, blank, or unexplained.** Three tiers:

### Tier 1 — Micro (< 400 ms)
No spinner. The control stays depressed until resolution. Nothing else.

### Tier 2 — Scene load (scene change, hydration, first art)
The `Loading` FSM state renders a composed frame, never a bare colour:
- the destination world's key art, dimmed and slowly drifting (Ken Burns, `breath`)
- the world's name in display type
- **one line of that world's own lore**, drawn from its descriptor — not "Loading…"
- a slim gold progress rule that reflects *real* work (hydrate → sheet → first paint), never a fake timer
- ambient bed already crossfaded in, so audio arrives before the visuals

Minimum on-screen time **700 ms** even if work finishes sooner — a flash is worse than a beat.

### Tier 3 — The GM is thinking (LLM first-token wait)

The most-seen wait in the game. It must feel like a person composing, not a
machine hanging.

**Composition** (bottom of the thread, where the reply will appear):
- a **quill** icon writing — a 3-dot ink stroke cycling, `breath`-paced
- the GM's bubble already present but empty, breathing at 0.9→1.0 α
- **candle flicker** on the scene art: ±0.02 α at ~2 Hz (slow — see the flicker RCA; fast flicker reads as a broken screen)
- 2–4 drifting motes rising through the bubble
- a status line in the **world's own voice**, rotating every 2.4 s

**World-specific waiting copy** (from `WorldSkin.FAMILIES[...].flavor`):

| Family | Lines |
|---|---|
| fantasy | "Consulting the Chronicle…" · "The quill moves…" · "Candles gutter as the tale turns…" |
| cyber | "Querying the net…" · "Decrypting the next frame…" · "The city answers…" |
| everyday | "Thinking it over…" · "Turning the page…" · "Finding the words…" |
| space | "Charting the next jump…" · "Long-range scan resolving…" |
| steam | "The difference engine turns…" · "Steam builds…" |
| pirate | "Reading the wind…" · "The log fills…" |
| horror | "Something considers you…" · "The dark deliberates…" |
| norse | "The threads are spun…" · "The saga gathers…" |

When the first token lands the waiting state **crossfades** into the streaming
text over `fast` — it never pops.

**Rule:** if a wait exceeds 20 s, the state adds a reassurance line ("the
GM is deep in thought — the local mind is slow tonight") and a cancel
affordance. It never silently gives up.

## 7. Reveal animations

For content appearing on screen (lists, cards, pages, tabs).

- Single element: `Ui.reveal` — α 0→1 + scale 0.985→1.0 over `base`, ease-out.
- Collections: `Ui.reveal_children` with **0.04 s stagger**, capped at 12 items (beyond that, reveal the container once — a 40-item stagger is a loading screen).
- Order: reading order, always. Never random, never centre-out.
- Tabs/pages: outgoing fades over `fast`, incoming reveals over `base`, no gap of empty screen.

**Rule:** a reveal enhances an already-valid layout. Content must never be *gated* on the animation firing — if the tween is skipped, the page still reads.

## 8. Reward animations

Reserved for things the player *earned*. Overuse destroys them.

| Reward | Presentation |
|---|---|
| Loot | item art scales 0.8→1.0 with a rarity-tinted glow, name rises, `loot` sound |
| Gold | coin glyph arcs to the purse, purse number counts up over `base`, `purchase` sound |
| XP | bar fills over `slow` with a travelling highlight; if it crosses a level, the fill *holds* one beat before the ceremony |
| Level up | full ceremony: screen dims 0.35, portrait breathes brighter, gold burst behind the hero, `levelup` fanfare, the menu opens on Destiny with the new star flaring |
| Quest complete | the quest line strikes through in gold, `quest` chord, entry slides to a "done" group |
| Chapter / THE END | the chronicler beat: page-turn, cover art assembles, `save` sound |

**Rule:** ceremony scales with rarity. A common dagger gets a shimmer; a level-up stops the world for 1.2 s.

## 9. Notifications

Mythforge has **no toast popups**. The world tells you things.

- **In-thread system lines** (`_say_system`) are the default channel: a drawn icon + one sentence, revealed like any other bubble.
- **Ambient state** (autosave, art landed) is shown *where the state lives* — the save mark near the header, the art fading into its frame — never a floating card.
- **Interruptions** (a reaction prompt in combat) take a modal with the full window ritual (§11) because they demand a decision.

**Rule:** if the player doesn't need to act, it does not steal focus.

## 10. Tooltips

Every actionable control carries one. This is not optional; it is the single
largest legibility gap in the current build.

| Property | Value |
|---|---|
| Delay | 450 ms hover, 0 ms if another tooltip is already open (chaining) |
| Fade | `fast` in, `fast` out |
| Anchor | above the control, flipping below near the screen edge; never covering the control |
| Content | **name** (title case) · **what it does** in one line · **shortcut** if any · **why disabled** when disabled |
| Rich tooltips | items, spells and skills use `MythTooltip` — framed panel, rarity rim, stat rows, ▲/▼ comparison against what's worn |

**Rules**
- Never restate the button's own label and stop there ("Shop — shop"). Say what happens.
- Numbers in tooltips must match the engine exactly — a tooltip is a promise.
- Keyboard/controller focus shows the tooltip too, at the same delay.

## 11. Window open / close rituals

Every dialog, menu, forge and book. `Ui.ritual_open` already carries the scrim;
MIL completes the ritual.

**Open**
1. Scrim fades in behind → `night` at 0.45α over `base`.
2. Window reveals: α 0→1, scale 0.985→1.0, over `base`, ease-out.
3. `ui_open` sound (rising) — one per open, never per child.
4. Focus lands on the primary control (keyboard/pad ready immediately).
5. Content inside staggers per §7.

**Close**
1. `ui_close` (falling, quieter than open).
2. Window α→0 + scale →0.99 over `fast`.
3. Scrim fades out over `base`.
4. Focus returns to the control that opened it.

**Rules**
- ESC always closes the topmost window and only that one.
- A window never opens over another without dimming the one beneath.
- Windows never resize after they're visible — measure before showing (this caused the off-screen OK button caught by the click-driver).

## 12. Audio vocabulary

All synthesized through `scripts/make_sfx.py` — pure math, no licences, no
downloads. **Every sound below is mandatory for VS-1.**

| Name | Character | Synthesis sketch |
|---|---|---|
| `ui_hover` | a breath of felt | 1.8 kHz sine, 45 ms, exp decay, −26 dB |
| `ui_click` | wood on leather | 120 Hz sine thump + 8 ms noise, 90 ms |
| `ui_open` | a drawer sliding | rising 220→330 Hz sine, 260 ms, soft attack |
| `ui_close` | it settles | falling 330→220 Hz, 200 ms, quieter than open |
| `ui_back` | one step back | short falling fifth, 140 ms |
| `ui_deny` | a muted refusal | 90 Hz square-ish, heavily damped, 160 ms |
| `equip` | metal into leather | noise burst + 1.2 kHz metallic ring, 240 ms |
| `purchase` | coins | 3 short metallic pings, randomized, 300 ms |
| `loot` | a small wonder | rising bell arpeggio (major 3rd), 420 ms |
| `levelup` | earned | major triad swell + shimmer tail, 1.4 s |
| `quest` | resolution | warm perfect fifth, 700 ms |
| `page` | paper turns | filtered noise sweep, 280 ms |
| `travel` | departure | low whoosh, 600 ms |
| `save` | the quill sets down | brief scratch + soft chime, 350 ms |
| `crit` | it *lands* | existing `hit` + bright overtone, 320 ms |
| `turn` | your move | soft double tap, 180 ms |

Plus the existing `dice`, `hit`, `sting`, `chime` and five ambient beds.

**Mix law**
- UI feedback sits **−18 to −26 dB** — felt, never announced.
- Rewards sit **−12 dB**; ceremony (`levelup`) at **−8 dB** is the loudest thing in the game.
- One hover sound per 80 ms globally. Two identical sounds never stack — retrigger cuts the first.
- Every sound respects the Settings SFX toggle; ambient respects its own toggle and slider.
- **Silence is never the answer to a click.** If a control is intentionally quiet, it still gets `ui_click`.

*World-skinned timbre (a cyber `ui_click` that ticks rather than thumps) is
explicitly **out of scope** for VS-1 — one neutral set ships first.*

## 13. Motion vocabulary

The complete public API. **Screens may not hand-roll tweens** — extend `Ui`
instead, so reduce-motion stays a single switch.

| Function | Does | Existing |
|---|---|---|
| `Ui.polish(root)` | wires hover lift + press dip to every Button under a node | ✅ |
| `Ui.reveal(ctrl, delay)` | fade + settle entrance | ✅ |
| `Ui.reveal_children(c, stagger)` | staggered collection entrance | ✅ |
| `Ui.breathe(ctrl)` | idle life loop at `breath` | ✅ |
| `Ui.pulse(ctrl)` | one-shot attention flare | ✅ |
| `Ui.ritual_open(dlg)` | scrim + window ceremony | ✅ |
| `Ui.rise_text(parent, text, colour, at)` | floating stat delta | ✅ |
| `Ui.shake(ctrl)` | error refusal | **VS-1** |
| `Ui.fly_to(from, to, tex)` | item/coin travelling between two rects | **VS-1** |
| `Ui.count_to(label, from, to)` | numbers roll rather than snap | **VS-1** |
| `Ui.transition(to_scene)` | world-skinned scene wipe | **VS-1** |
| `Sfx.ui(name)` | rate-limited UI sound | **VS-1** |

## 14. Accessibility variants

Every pattern above must degrade, never disappear. `Ui.reduce_motion` is
already honoured in 17 files; MIL extends the contract.

| Pattern | Reduced motion | Notes |
|---|---|---|
| Hover | rim/colour change only, no scale | state stays perceivable |
| Click | instant state change, sound unchanged | audio carries the beat |
| Success | delta text **appears and holds 1.2 s** instead of rising | information preserved |
| Error | colour pulse + sound, **no shake** | never induce motion discomfort |
| Loading | static composed frame, no drift, no motes | progress rule still moves (it is information, not decoration) |
| Reveal | instant visibility | never gate content on a tween |
| Reward | single flash + sound, no burst | ceremony shortens, never vanishes |
| Window ritual | instant, scrim still dims | dimming is hierarchy, not motion |
| Waiting state | text rotation only, no quill animation | the words do the work |

**Additional requirements**
- Every state is carried by **at least two channels** (colour + motion, or colour + sound, or motion + text) — never colour alone.
- Body text contrast ≥ **4.5:1**, large text ≥ **3:1**, measured per palette, not assumed.
- Sound is never the *only* signal of anything.
- Focus is always visible — the 2 px amethyst ring, on every focusable control, keyboard and pad alike.

*Text scaling and colourblind palettes are queued (VerticalSlice §G) and out of
VS-1 scope; the two-channel rule above is what VS-1 must satisfy.*

---

## 15. Compliance checklist

Applied to **every screen** before it may be called done:

- [ ] Every control hovers (motion + rim + sound + cursor)
- [ ] Every control clicks (depress + sound on press)
- [ ] Every control has a tooltip; disabled ones say why
- [ ] Every state change shows a delta or a moving thing
- [ ] Every refusal shakes, pulses, sounds, and explains in the world's voice
- [ ] Every wait is composed — nothing frozen, nothing blank
- [ ] Every window opens and closes with the full ritual
- [ ] Every animation has a reduce-motion variant that preserves the information
- [ ] No raw glyphs/emoji — drawn icons only (MDL law)
- [ ] No engineering strings visible to a player
- [ ] Both harnesses green (`ui_playthrough`, `click_driver`)

## 16. What this document does not permit

Scope armour for VS-1. These are **not** interaction-language work:

- New game systems, new screens, new mechanics
- Redesigning layouts that already read correctly
- World-skinned audio timbres, text scaling, colourblind palettes (queued)
- Dialogue UI, quest journal, combat rebuild (queued — separate sprints)
- Any change that alters what the engine *computes*

MIL changes how things **feel**, never what they **do**.
