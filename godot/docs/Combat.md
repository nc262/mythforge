# Combat

Engine-owned, turn-based, tracker-driven (tactical grid roadmapped M2).
Source: `autoload/combat.gd` — a faithful port of the web original's math.

## Model
`combat` world-state kind: `{active, round, turn, combatants[]}`;
combatant: `{id, name, hp, hpMax, ac, init, side(ally|enemy), conditions[], ds?}`.
Persists mid-round — a fight survives app restarts.

## Flow
1. Entry: `[[combat-start foes="goblin x3, boss"]]` (xN multipliers, cap 6)
   or the ported prose fallback (`detect_combat_start` + plausible-foe
   denylist). Sting plays; screen tints ember-red; tracker panel opens.
2. Initiative: d20 + DEX (hero), d20 flat (others); sorted order, ▶ marker.
3. Player attack (`player_attack`): action budget per round (Extra Attack
   ×2), weapon props from name (finesse/ranged pick DEX, versatile
   two-hands when off-hand empty, heavy), d20 + abil + prof + magic atk vs
   AC (12 unrevealed), Champion crits 19–20, crit doubles dice, Rage +2
   melee, **bestiary typed defenses**: vuln ×2, resist ×½ (skeletons fear
   maces, not rapiers).
4. Enemy turn: atk = min(9, 3 + hpMax/15); dmg = hpMax/18 + d6 (crit ×2);
   lands on the real sheet via `GameState.apply_hp`. Incapacitating
   conditions skip the turn. *(Reactions overlay — Shield/Uncanny
   Dodge/Parry — designed, roadmapped M2.)*
5. Companions: strike a random living foe, scaled by their hpMax; wounds
   persist to the sheet between fights.
6. Death: at 0 HP the roll bar becomes ☠ death save — nat 20 revives at
   1 HP, nat 1 double-fails, 3 successes stabilize, 3 failures = the
   epitaph card (name/level/days/XP/gold) + GM final words.
7. Victory: last foe falls → auto-finish, XP = Σ max(25, 2×hpMax), killing
   blow streamed to the GM for cinema; `[[combat-end]]` covers flight/
   surrender.

## GM contract in combat
The GM narrates around engine-reported numbers, never generates its own —
restated in the protocol every turn. Each mechanical event (hit, miss,
enemy blow, death save) streams to the GM as the player's message.

## Tests
`self_check.tscn` simulates a full fight to victory (budget cycling, XP
paid, state cleared); `playthrough.tscn` runs one live vs the real model.
