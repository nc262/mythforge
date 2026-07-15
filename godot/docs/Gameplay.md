# Gameplay

## The core loop
```
say what you do → GM narrates (streamed) → GM proposes mechanics via tags
→ the roll bar arms → you roll (the dice moment) → engine resolves
→ result streams back → the GM narrates the consequence
```
Around it: loot and gold arrive through tags, time passes on a 7-step clock
with per-world weather, quests and the cast extract themselves in the
background, and the world's art repaints as you travel.

## A session, end to end
1. **Title** → Continue (save-file picker if several) or New Adventure
2. **World** (step 1): built-ins or forge one (idea + five pillars)
3. **Campaign** (step 2): Free Roam / authored stories / craft your own
4. **Hero** (step 3): the hero forge — name, heritage, class, 4d6 destiny —
   then **Session Zero** tone knobs (humor/spice/grit/pace/rules)
5. **Play**: exploration ↔ conversation ↔ combat ↔ trade ↔ rest
6. Returning: the "Previously…" recap card from campaign memory

## Player verbs (today)
Say anything · roll anything (🎲 menu, real modifiers) · attack / next-turn /
end-combat · equip / sell / buy / haggle · cast (slots enforced) · use class
features (per-rest pips) · short/long rest · ask the GM to learn a spell or
recruit an ally · conjure scene art · retell the last GM reply · death saves.

## Difficulty & fairness doctrine
DCs come from the GM but resolution is engine-owned; enemy stats derive from
name-tier + hero level (+20%/level); long rests carry a 1-in-4 ambush; death
is real (3 failures) but the last-dawn recovery is one long rest away.
Fairness = the model can neither fudge for you nor against you.

## Modes (FSM target, M1)
MainMenu · CharacterCreation · Exploration · Conversation(companion) ·
Combat · Merchant · Rest/Camp · Travel · Cutscene(finale) · GameOver.
Today these are implicit; the FSM will make allowed/blocked actions and
visible UI explicit per mode.
