# Inventory & Economy

Engine-owned. Source: `GameState` (inv/gold mutations) + `Rules` (item math).

## Model
`inv` kind: `{slots: 24, items[], equipped{weapon|armor|shield: id}}`.
Item: `{id, name, qty, rarity, type, dmg?, atk?, acBonus?}` — built by
`Rules.mk_item` from the name (weapon die by name regex, magic +atk from
rarity, armor AC by name with shield +2, epic/legendary +1/+2).

## Acquisition
- `[[loot name=… rarity=…]]` from the GM (typed item lands in the pack)
- 🛒 the trader: fixed `vendor_stock` (weapon/armor/potion/food/general) at
  honest prices; **haggle** = Persuasion vs DC 12 → ×0.8 or ×1.1 session
  markup; purse enforced; purchases narrated by the GM
- selling: half `item_value` by rarity (6/20/65/175/500), unequips if worn

## Equipment effects (real math, not flavor)
- weapon: `atk` feeds `Rules.attack_mod`; `dmg` feeds combat damage dice
- armor: `acBonus` with DEX caps (≥6 zeroes DEX, ≥3 caps +2) — heavy armor
  behaves like heavy armor; Unarmored Defense (Barbarian CON / Monk WIS)
  when no body armor
- shield: flat +2

## Gold
One number, world-named (gold/credits/cash — display currency roadmapped).
`[[gold delta=±N]]` and all trades route through `GameState.add_gold`
(floored at 0). Chime on gains.

## UI today / target
Today: the sheet panel's Pack section — worn markers, equip/unequip, sell
links, slot count. Target (M3): drag-and-drop grid + paper-doll equipment
window per the production UI spec (see UI.md); the data model already
supports it — this is presentation work only.

## Not yet ported (tracked in FeatureMatrix)
Encumbrance/carry capacity, item weight halving when worn, item icons/art,
crafting (`_craftItem`), give-to-companion, use-item (potions as effects).
