# Mythforge Interaction Language (MIL)

**The standard for every interaction in the game.** MDL
([DesignSystem.md](DesignSystem.md)) governs how things *look*; MIL governs how
things *behave when touched*, and — first — **how they should make the player
feel**. The World Style Guide ([WorldSkin.md](WorldSkin.md)) supplies the
vocabulary both draw from.

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
| **Beginning** — *anticipation* | "this is touchable, and I am touching it" | hover lift + rim warm + hover sound; press depress |
| **Middle** — *transformation* | the world visibly changes | the animation of the thing itself (a piece slots into a socket, a coin arcs to the purse, a bar fills) |
| **End** — *consequence + rest* | what it cost, what it gained, a return to calm | stat delta, confirmation sound, control settles to idle |

**Worked reference — equipping a longsword:**

```
hover socket   → scale SCALE.lift, gold rim at ALPHA.rim, Sfx.ui("ui_hover")   (beginning)
press          → scale SCALE.press, Sfx.ui("ui_click")                          (beginning)
release        → Ui.fly_to(card → socket) over TIME.base                        (middle)
               → socket flares, Ui.pulse                                        (middle)
               → doll render updates                                            (middle)
               → Ui.rise_text("+2 AC")                                          (end)
               → Sfx.ui("equip")                                                (end)
               → all idle within TIME.slow                                      (end)
```

Total budget: **`INTERACT.budget`**. Longer and the player is waiting, not being
rewarded. Nothing in MIL may block input — every act is interruptible by acting
again.

---

## 1. Emotional intent — design this first

**Design the player's emotional experience first, then design the motion, audio
and visuals that serve it.** A pattern whose emotion is undefined has no way to
be judged right or wrong, and drifts into decoration.

Every pattern in this document declares its intent. The full table:

| Pattern | Purpose | Desired emotion | Why it exists |
|---|---|---|---|
| **Hover** | mark the boundary between world and interface | *curiosity, invitation* | The player must know what is alive before committing. Uncertainty about what is clickable is the cheapest form of anxiety, and the easiest to remove. |
| **Click** | confirm the machine received the intent | *agency, certainty* | Input without acknowledgement makes a player press twice. Two presses is a broken contract. |
| **Success** | make the consequence legible and deserved | *satisfaction, competence* | Numbers changing off-screen teach the player their choices are bookkeeping. A visible consequence teaches that their choices matter. |
| **Error / refusal** | say no without punishing | *clarity, never shame* | A refusal the player doesn't understand reads as a bug. A refusal that explains itself reads as a rule — and rules are part of the fiction. |
| **Loading** | keep the world present while the machine works | *trust, anticipation* | A frozen screen breaks the fiction and invites the thought "is it broken?" A composed wait keeps the player inside the story. |
| **GM thinking** | make the pause feel like authorship | *anticipation, company* | The local model is genuinely slow. Unmasked, that reads as failure; dressed as a Game Master composing, the same seconds read as care. |
| **Reveal** | let content arrive rather than appear | *discovery, order* | Instant population overwhelms and hides hierarchy. Staggered arrival tells the eye where to begin reading. |
| **Reward** | mark what was earned | *pride, appetite* | If loot and levels land as silently as a menu click, progression stops feeling like progress. |
| **Notification** | inform without interrupting | *calm awareness* | Interruption is a tax on immersion. State should be visible where the state lives. |
| **Tooltip** | answer the question before it's asked | *confidence, mastery* | A player who must experiment to learn what a button does is being tested, not taught. |
| **Window ritual** | mark passage between contexts | *deliberateness, weight* | A window that blinks into existence is a dialog box. A window that opens is a place you went. |
| **Scene transition** | preserve continuity of world | *immersion, flow* | A hard cut resets the fiction. A transition carries the player somewhere; nothing feels more "prototype" than a cut. |
| **Ceremony** | stop time for what mattered | *awe, pride, memory* | Ordinary feedback is calibrated to be forgettable. Some moments must be *remembered*, and memory requires disproportion. |

**Rule:** when a pattern's motion, audio and visuals disagree about the
emotion, the emotion wins and the craft is redone.

---

## 2. Tokens — the only numbers allowed

**No literal timing, scale, alpha, offset, or decibel value may appear in an
interaction.** Everything below lives in `autoload/skin.gd` so the whole game
can be re-tuned from one place during playtesting — that is the point: these
values *will* change once we play it, and no code should have to change with
them.

```gdscript
Ui.TIME     = {instant, fast, base, slow, beat, ceremony, breath}
Ui.SCALE    = {press, exit, enter, lift, pulse, bloom}
Ui.ALPHA    = {ghost, glow, scrim, rim, dim}
Ui.MOTION   = {shake_px, shake_cycles, rise_px, stagger, stagger_max, drift_px}
Ui.DELAY    = {hover_gate, tooltip, load_min, status_cycle, ceremony_hold}
Ui.MIX      = {ui, reward, ceremony}
Ui.INTERACT = {budget}
```

| Group | Token | Meaning |
|---|---|---|
| **TIME** | `instant` | sub-perceptual state flips |
| | `fast` | hover, press, tooltip fade, micro-feedback |
| | `base` | reveals, tab swaps, deltas, window ritual |
| | `slow` | scene transitions, art crossfade, settle |
| | `beat` | a held pause inside a ceremony |
| | `ceremony` | the full length of a ceremony peak |
| | `breath` | idle life loops (portraits, candles, waiting) |
| **SCALE** | `press` | depressed control |
| | `exit` | element leaving |
| | `enter` | element arriving from |
| | `lift` | hovered control |
| | `pulse` | one-shot attention flare peak |
| | `bloom` | ceremony burst peak |
| **ALPHA** | `ghost` | empty-slot art, disabled imagery |
| | `glow` | success/attention glow |
| | `scrim` | modal dim behind a window |
| | `rim` | hovered border warmth |
| | `dim` | ceremony world-dim |
| **MOTION** | `shake_px` / `shake_cycles` | refusal shake |
| | `rise_px` | floating stat delta travel |
| | `stagger` / `stagger_max` | collection reveal cadence and cap |
| | `drift_px` | Ken Burns / parallax travel |
| **DELAY** | `hover_gate` | minimum spacing between hover sounds |
| | `tooltip` | hover dwell before a tooltip |
| | `load_min` | minimum time a loading frame stays up |
| | `status_cycle` | waiting-line rotation |
| | `ceremony_hold` | the pause at a ceremony's peak |
| **MIX** | `ui` / `reward` / `ceremony` | the three loudness tiers, in dB |
| **INTERACT** | `budget` | maximum length of an *ordinary* interaction |

**Easing law:** ease **out** on arrival, ease **in-out** on round trips.
Exponential family only — `TRANS_QUAD`, `TRANS_CUBIC`, `TRANS_QUART`,
`TRANS_EXPO`, `TRANS_SINE` (idle loops). **Banned:** `TRANS_BOUNCE`,
`TRANS_ELASTIC`, any overshoot on UI chrome. Mythforge is candlelit and heavy —
nothing springs.

**Tuning protocol:** during playtest, change the token, never the caller. If a
single screen needs a different value, that is a signal the token set is wrong,
not a licence to hardcode.

---

## 3. Hover

> **Intent:** curiosity, invitation. *The player must know what is alive before committing.*

Applies to every `Button`, card, socket, tab, map pin, and list row.

| Layer | Behaviour |
|---|---|
| Motion | scale → `SCALE.lift` over `TIME.fast`, ease-out quad (`Ui.polish`) |
| Light | border/rim → `gold` at `ALPHA.rim`; material plates raise their top highlight |
| Cursor | `CURSOR_POINTING_HAND` on anything clickable — **no exceptions** |
| Audio | `ui_hover` at `MIX.ui`, gated to one per `DELAY.hover_gate` |
| Tooltip | arms the `DELAY.tooltip` timer (§10) |

- Hover must be visible **without motion** (the rim), so reduce-motion still perceives it.
- Disabled controls do not hover, do not sound, and carry a tooltip saying *why*.
- Nothing may change layout on hover — scale only, never reflow.

## 4. Click / press

> **Intent:** agency, certainty. *Input without acknowledgement makes a player press twice.*

| Phase | Behaviour |
|---|---|
| Press down | scale → `SCALE.press` over `TIME.fast`; `ui_click` fires **on press, not release** |
| Held | hold the depressed state; no repeat sound |
| Release inside | → `SCALE.lift` over `TIME.fast`; the action's *middle* act begins |
| Release outside | → 1.0, no action, no sound |

- A click that does nothing must still respond — refusal (§6), never silence.
- Irreversible controls confirm first; the confirm uses `AccentButton` + the full window ritual.
- Double-click is never the only path to an action.

## 5. Success

> **Intent:** satisfaction, competence. *A visible consequence teaches that choices matter.*

1. **The thing moves** — `Ui.fly_to` for objects, fill for bars, over `TIME.base`, ease-out.
2. **Shimmer** — `Ui.pulse` to `SCALE.pulse`, plus a gold glow at `ALPHA.glow` fading over `TIME.base`.
3. **Delta** — `Ui.rise_text` for every number the player cares about (`+2 AC`, `−40 gold`, `+150 XP`), travelling `MOTION.rise_px`, gold for gain / `danger` for loss.
4. **Audio** — the specific reward sound (§12), never a generic click.
5. **Rest** — settled within `INTERACT.budget`; no glow outlives it.

**Rule:** if a number on screen changed and no delta rose, the interaction is incomplete.

## 6. Error / refusal

> **Intent:** clarity, never shame. *A refusal that explains itself reads as a rule, not a bug.*

| Layer | Behaviour |
|---|---|
| Motion | `Ui.shake` — `MOTION.shake_cycles` oscillations at ±`MOTION.shake_px`, decaying, over `TIME.base` |
| Colour | border pulses `danger` → 0 over `TIME.base` |
| Audio | `ui_deny` at `MIX.ui` — muted, low, deliberately unsatisfying |
| Words | one sentence, in the world's voice, saying *what* and *why*: "Not enough gold for the lantern — you carry 12, it asks 15." |

- Never show HTTP codes, exception text, node paths, or "null" to a player.
- System faults (no narrator model, the art forge stalled) are phrased as the world faltering, with a retry — never blame the player.
- Rule refusals state the rule and point at the fix ("not your turn — press Next › to advance").

## 7. Loading and waiting

> **Intent:** trust, anticipation. *A frozen screen invites "is it broken?"*

### Tier 1 — Micro (< `TIME.slow`)
No spinner. The control holds its pressed state until resolution.

### Tier 2 — Scene load
The `Loading` FSM state renders a composed frame, never a bare colour:
- destination world's key art, dimmed, drifting `MOTION.drift_px` over `TIME.breath`
- the world's name in display type
- **one line of that world's own lore** — never the word "Loading"
- a slim gold rule reflecting *real* work (hydrate → sheet → first paint), never a fake timer
- ambient bed crossfaded in first, so sound arrives before picture

Held a minimum of `DELAY.load_min` even if work finishes sooner — a flash is worse than a beat.

### Tier 3 — The GM is thinking

> **Intent:** anticipation, company. *The same seconds read as care instead of failure.*

At the foot of the thread, where the reply will appear:
- a **quill** writing — ink-stroke cycle paced to `TIME.breath`
- the GM's bubble present but empty, breathing between `ALPHA.dim` and 1.0
- **slow** candle flicker on the scene art (fast flicker reads as a broken screen — see the flicker RCA)
- a few motes drifting up through the bubble
- a status line in the world's own voice, rotating every `DELAY.status_cycle`

**World-specific waiting copy**, keyed to the active `WorldSkin` family:

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

First token → crossfade into streaming text over `TIME.fast`; it never pops.
Past a long wait, add reassurance and a cancel affordance; never fail silently.

## 8. Reveal

> **Intent:** discovery, order. *Staggered arrival tells the eye where to begin.*

- Single element: `Ui.reveal` — α 0→1, scale `SCALE.enter`→1.0 over `TIME.base`, ease-out.
- Collections: `Ui.reveal_children` at `MOTION.stagger`, capped at `MOTION.stagger_max` (beyond that reveal the container once — a 40-item stagger is a loading screen).
- Order: reading order. Never random, never centre-out.
- Tabs/pages: outgoing fades over `TIME.fast`, incoming reveals over `TIME.base`, never a gap of empty screen.

**Rule:** content must never be *gated* on the tween — if it's skipped, the page still reads.

## 9. Reward

> **Intent:** pride, appetite. *Silent progression stops feeling like progress.*

| Reward | Presentation |
|---|---|
| Loot | art scales `SCALE.enter`→1.0 with a rarity-tinted glow, name rises, `loot` |
| Gold | coin arcs to the purse (`Ui.fly_to`), purse counts up (`Ui.count_to`), `purchase` |
| XP | bar fills over `TIME.slow` with a travelling highlight; crossing a level *holds* one `TIME.beat` before the ceremony |
| Quest complete | line strikes through in gold, `quest`, entry slides to a done group |

Ordinary rewards live here. Anything that should be *remembered* is a Ceremony (§13).

## 10. Tooltips

> **Intent:** confidence, mastery. *A player who must experiment to learn is being tested, not taught.*

| Property | Value |
|---|---|
| Delay | `DELAY.tooltip`; 0 if another tooltip is already open (chaining) |
| Fade | `TIME.fast` in and out |
| Anchor | above the control, flipping near screen edges; never covering it |
| Content | **name** · **what it does**, one line · **shortcut** · **why disabled** |
| Rich | items/spells/skills use `MythTooltip` — framed, rarity rim, stat rows, ▲/▼ vs worn |

- Never restate the label and stop ("Shop — shop"). Say what happens.
- Numbers must match the engine exactly — a tooltip is a promise.
- Keyboard and pad focus show tooltips too, at the same delay.

## 11. Notifications

> **Intent:** calm awareness. *Interruption is a tax on immersion.*

- **In-thread system lines** are the default channel: drawn icon + one sentence, revealed like any bubble.
- **Ambient state** (autosave, art landed) is shown *where the state lives* — never a floating card.
- **Interruptions** (a combat reaction prompt) take a modal with the full ritual, because they demand a decision.

**Rule:** if the player needn't act, it does not steal focus. Mythforge has no toast popups.

## 12. Window open / close rituals

> **Intent:** deliberateness, weight. *A window that opens is a place you went.*

**Open**
1. Scrim fades in → `night` at `ALPHA.scrim` over `TIME.base`.
2. Window: α 0→1, scale `SCALE.enter`→1.0 over `TIME.base`, ease-out.
3. `ui_open` — one per window, never per child.
4. Focus lands on the primary control.
5. Content staggers per §8.

**Close** — `ui_close` (quieter than open) · α→0, scale→`SCALE.exit` over `TIME.fast` · scrim out over `TIME.base` · focus returns to the opener.

- ESC closes the topmost window, and only that one.
- A window never opens over another without dimming the one beneath.
- Windows never resize after becoming visible — measure before showing (this caused the off-screen OK button the click-driver caught).

## 13. Ceremonies

> **Intent:** awe, pride, memory. *Ordinary feedback is calibrated to be forgotten. Some moments must be remembered — and memory requires disproportion.*

Ceremonies are the deliberate exception to `INTERACT.budget`. They stop time.
Because they are expensive, they are **rationed**: a ceremony that fires often
is no longer a ceremony, it is an interruption.

### The five-beat grammar

Every ceremony uses the same shape, scaled by weight:

| Beat | What happens |
|---|---|
| **1. Hush** | the world quiets — scene dims to `ALPHA.dim`, ambient ducks, motion stills over `TIME.base` |
| **2. Gather** | the elements converge — art assembles, light draws inward, portrait brightens |
| **3. Strike** | the peak — bloom to `SCALE.bloom`, the fanfare at `MIX.ceremony`, held `DELAY.ceremony_hold` |
| **4. Bestow** | what you gained, stated plainly and legibly — the name, the number, the new power |
| **5. Return** | the world comes back over `TIME.slow`, focus lands somewhere useful (usually *at* the new thing) |

### The ceremonies

| Moment | Weight | Beats | The feeling it must produce |
|---|---|---|---|
| **Character created** | Major | full 5 | *"This is mine."* The portrait, name, class and world assemble into one composed frame — the first time the hero exists as a person rather than a form. |
| **Campaign created** | Major | full 5 | *"A world now exists that didn't."* Key art resolves, the premise is read like a title card. |
| **Adventure start** | Major | full 5 | *"It begins."* The hush before the first scene: world art, party assembled, then the GM's first words arrive into stillness. |
| **Level up** | Major | full 5 | *"I grew."* Dim, portrait brightens, gold burst, the gains listed, then the menu opens on Destiny with the new star flaring. |
| **Legendary / epic loot** | Major | full 5 | *"I will remember finding this."* Rarity-coloured light, the item held large before it goes to the pack. |
| **Boss victory** | Major | full 5 | *"We survived that."* Battle music resolves rather than stops, the fallen foe's art dims, spoils presented as a group. |
| **Companion recruited** | Medium | 1,2,3,5 | *"I'm not alone."* Their portrait paints in and takes its place beside the hero. |
| **Chapter closed / THE END** | Major | full 5 | *"That was a story."* Page-turn, the cover assembles, the chronicle accepts it. |
| **First arrival in a new place** | Light | 2,3,5 | *"Somewhere new."* Scene art crossfades under the place's name; no dim, no focus theft. |
| **Uncommon / rare loot** | Light | 3,4 | *"Nice."* Glow and lift proportional to rarity — not a full stop. |

### Ceremony law

- **Always skippable.** Any input completes the ceremony immediately and lands on its end state. Never trap the player.
- **Never blocking truth.** State is committed *before* the ceremony plays; the ceremony narrates a change that already happened, so an interrupted ceremony can never desync.
- **Rationed by weight.** Major ceremonies must be rare enough to stay special — if playtest shows one firing every few minutes, it demotes to Medium.
- **Diegetic where possible.** Prefer the world reacting (candles flare, the chronicle writes) over UI effects layered on top.
- **Reduce-motion:** the beats remain, expressed as crossfade + hold instead of movement — a ceremony must never simply vanish for accessibility. Duration may shorten; the *moment* may not be removed.
- **Audio is the spine.** If everything visual were removed, the ceremony's audio alone should still read as "something significant just happened."

## 14. Motion vocabulary

The complete public API. **Screens may not hand-roll tweens** — extend `Ui`
instead, so reduce-motion and token tuning stay single switches.

| Function | Does | State |
|---|---|---|
| `Ui.polish(root)` | hover lift + press dip on every Button under a node | ✅ |
| `Ui.reveal(ctrl, delay)` | fade + settle entrance | ✅ |
| `Ui.reveal_children(c, stagger)` | staggered collection entrance | ✅ |
| `Ui.breathe(ctrl)` | idle life loop | ✅ |
| `Ui.pulse(ctrl)` | one-shot attention flare | ✅ |
| `Ui.ritual_open(dlg)` | scrim + window ceremony | ✅ |
| `Ui.rise_text(parent, text, colour, at)` | floating stat delta | ✅ |
| `Ui.shake(ctrl)` | refusal | **VS-1** |
| `Ui.fly_to(from, to, tex)` | object travelling between two rects | **VS-1** |
| `Ui.count_to(label, from, to, fmt)` | numbers roll rather than snap | **VS-1** |
| `Ui.transition(scene_path)` | world-skinned scene wipe | **VS-1** |
| `Ui.ceremony(host, spec)` | the five-beat grammar | **VS-1** |
| `Sfx.ui(name)` | rate-limited, tier-mixed UI sound | **VS-1** |

## 15. Audio vocabulary

All synthesized through `scripts/make_sfx.py` — pure math, no licences, no
downloads. Every sound below is mandatory for VS-1.

| Name | Character | Synthesis sketch |
|---|---|---|
| `ui_hover` | a breath of felt | high sine, very short, exp decay |
| `ui_click` | wood on leather | low sine thump + brief noise |
| `ui_open` | a drawer sliding | rising sine, soft attack |
| `ui_close` | it settles | falling sine, quieter than open |
| `ui_back` | one step back | short falling fifth |
| `ui_deny` | a muted refusal | low damped square-ish, no sparkle |
| `equip` | metal into leather | noise burst + metallic ring |
| `purchase` | coins | three randomized metallic pings |
| `loot` | a small wonder | rising bell arpeggio |
| `levelup` | earned | major triad swell + shimmer tail |
| `quest` | resolution | warm perfect fifth |
| `page` | paper turns | filtered noise sweep |
| `travel` | departure | low whoosh |
| `save` | the quill sets down | brief scratch + soft chime |
| `crit` | it *lands* | impact + bright overtone |
| `turn` | your move | soft double tap |

Plus existing `dice`, `hit`, `sting`, `chime` and five ambient beds.

**Mix law**
- UI feedback at `MIX.ui` — felt, never announced.
- Rewards at `MIX.reward`. Ceremony at `MIX.ceremony` — the loudest thing in the game.
- One hover sound per `DELAY.hover_gate`; identical sounds never stack (retrigger cuts the first).
- Every sound respects the Settings toggles.
- **Silence is never the answer to a click.**

*World-skinned timbre is explicitly out of scope for VS-1 — one neutral set ships first.*

## 16. Accessibility variants

Every pattern degrades; none disappears. `Ui.reduce_motion` is already honoured
in 17 files — MIL extends the contract.

| Pattern | Reduced motion |
|---|---|
| Hover | rim/colour only, no scale |
| Click | instant state flip, sound unchanged |
| Success | delta **appears and holds** instead of rising |
| Error | colour pulse + sound, **no shake** |
| Loading | static frame, no drift or motes — but the progress rule still moves (information, not decoration) |
| Reveal | instant visibility |
| Reward | single flash + sound, no burst |
| Window ritual | instant, scrim still dims (dimming is hierarchy) |
| GM thinking | text rotation only, no quill animation |
| **Ceremony** | crossfade + hold replaces movement; shortened, **never removed** |

**Additional requirements**
- Every state carried by **at least two channels** — never colour alone.
- Body text ≥ **4.5:1**, large text ≥ **3:1**, measured per palette — **enforced**
  by `Ui.clamp_palette`, which walks every text role away from the lightest
  surface until it clears the bar, and gated by `self_check` across all eight
  palettes. This line was aspirational until 2026-08-04: measuring found four
  real violations, including `horror`'s `danger` at **3.74:1** — the colour an
  error message is printed in.
- Sound is never the only signal of anything.
- Focus always visible — the amethyst ring, keyboard and pad alike.

*Text scaling and colourblind palettes are queued (VerticalSlice §G), out of VS-1 scope.*

---

## 17. Compliance checklist

Applied to **every screen** before it may be called done:

- [ ] Every control hovers (motion + rim + sound + cursor)
- [ ] Every control clicks (depress + sound on press)
- [ ] Every control has a tooltip; disabled ones say why
- [ ] Every state change shows a delta or a moving thing
- [ ] Every refusal shakes, pulses, sounds, and explains in the world's voice
- [ ] Every wait is composed — nothing frozen, nothing blank
- [ ] Every window opens and closes with the full ritual
- [ ] Every milestone that should be remembered has a ceremony; every ceremony is skippable
- [ ] Every animation has a reduce-motion variant preserving the information
- [ ] **No literal timing/scale/alpha/dB values** — tokens only
- [ ] No raw glyphs/emoji — drawn icons only (MDL law)
- [ ] No engineering strings visible to a player
- [ ] Both harnesses green (`ui_playthrough`, `click_driver`)

## 18. What this document does not permit

Scope armour for VS-1:

- New game systems, new screens, new mechanics
- Redesigning layouts that already read correctly
- World-skinned audio timbres, text scaling, colourblind palettes (queued)
- Dialogue UI, quest journal, combat rebuild (queued — separate sprints)
- Any change that alters what the engine *computes*

MIL changes how things **feel**, never what they **do**.
