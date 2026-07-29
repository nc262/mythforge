#!/usr/bin/env python3
"""Give the nine heritages a BODY, and give `size` a home in data.

Two problems solved at once.

## 1. Size was a regex on a name

combat.gd decided Small by pattern-matching the race STRING:

    RegEx.create_from_string("(?i)halfling|gnome|goblin|kobold|imp|sprite|fairy|pixie")

That rule is live — heavy weapons swing at disadvantage for Small heroes — but a
world reskin that renames Halfling silently makes them Medium, and a homebrew
"Stoutfolk" is Medium by accident. `size` belongs on the heritage.

## 2. SIZE AND PROPORTION ARE DIFFERENT THINGS

The Dwarf proves it: mechanically **Medium** in 5e, but visibly short and broad.
Conflate the two and you get either a Dwarf that plays as Small (wrong rules) or
a Dwarf drawn at Human height (wrong look). So:

  size  -> a RULES category (small/medium). Drives the heavy-weapon rule, and
           later the token footprint on the battle board.
  body  -> a RENDER profile. Multipliers applied to bone scale on the one shared
           skeleton, never new geometry.

## Why this is data and not 9 meshes

Race and sex are bone-scale profiles on ONE rig. Equipment is skinned to the
same bones, so it follows the scaling for free — that is the whole reason 9
races x 2 sexes does not mean 18 armour sets. `tier` says which authored body an
armour piece is fitted against; everything else is arithmetic.

    python scripts/add_heritage_bodies.py [--dry-run]
"""
import argparse
import json
import os

TABLES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "godot", "data", "tables.json")

# height: overall scale, Human = 1.0.  girth: torso/limb thickness.
# head: head bone scale — small folk read as small partly through a
#   proportionally LARGER head, which is why Halfling/Gnome go above 1.0.
# leg/arm: limb length. The Dwarf is short mostly in the LEGS, not the torso;
#   scaling height alone gives a shrunken human instead of a dwarf.
# tier: which authored body equipment is fitted to (Quaternius ships 3
#   proportions x 2 sexes; slim/regular/heavy is that split).
# features: extra meshes parented to a bone. These do not affect armour fitting
#   at all — except helm vs horns, which every RPG resolves by hiding one.
BODIES = {
    "Human":      dict(size="medium", tier="regular", height=1.00, girth=1.00, head=1.00, leg=1.00, arm=1.00, features=[]),
    "Elf":        dict(size="medium", tier="slim",    height=1.02, girth=0.93, head=0.98, leg=1.04, arm=1.03, features=["ears_long"]),
    "Dwarf":      dict(size="medium", tier="heavy",   height=0.80, girth=1.22, head=1.06, leg=0.82, arm=0.90, features=["beard_broad"]),
    "Halfling":   dict(size="small",  tier="slim",    height=0.64, girth=0.98, head=1.12, leg=0.88, arm=0.92, features=["feet_bare"]),
    "Half-Orc":   dict(size="medium", tier="heavy",   height=1.08, girth=1.18, head=1.02, leg=1.02, arm=1.06, features=["tusks"]),
    "Tiefling":   dict(size="medium", tier="regular", height=1.01, girth=1.00, head=1.00, leg=1.02, arm=1.00, features=["horns", "tail"]),
    "Dragonborn": dict(size="medium", tier="heavy",   height=1.10, girth=1.14, head=1.04, leg=1.03, arm=1.04, features=["snout", "tail", "scales"]),
    "Gnome":      dict(size="small",  tier="slim",    height=0.58, girth=1.00, head=1.16, leg=0.84, arm=0.90, features=["ears_wide"]),
    "Half-Elf":   dict(size="medium", tier="regular", height=1.01, girth=0.97, head=0.99, leg=1.02, arm=1.01, features=["ears_slight"]),
}

# Sex is a TIER, not a pipeline: the same three proportion classes authored for a
# second body. Applied on top of the heritage profile.
SEXES = {
    "female": dict(height=0.96, girth=0.94, shoulder=0.94, hip=1.06),
    "male":   dict(height=1.00, girth=1.00, shoulder=1.00, hip=1.00),
    "neutral": dict(height=0.98, girth=0.97, shoulder=0.97, hip=1.03),
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    with open(TABLES, encoding="utf-8") as f:
        tables = json.load(f)

    her = tables.get("heritages")
    if not isinstance(her, dict):
        raise SystemExit("heritages table missing or not an object")

    missing = [k for k in BODIES if k not in her]
    extra = [k for k in her if k not in BODIES]
    if missing:
        raise SystemExit("heritages in BODIES but not in tables.json: %s" % missing)
    if extra:
        print("WARNING: heritage(s) with no body profile, will fall back to Human: %s" % extra)

    for name, spec in BODIES.items():
        entry = her[name]
        entry["size"] = spec["size"]
        entry["tier"] = spec["tier"]
        entry["body"] = {k: spec[k] for k in ("height", "girth", "head", "leg", "arm")}
        if spec["features"]:
            entry["features"] = spec["features"]
        print("  %-12s size=%-6s tier=%-7s h=%.2f girth=%.2f head=%.2f leg=%.2f  %s"
              % (name, spec["size"], spec["tier"], spec["height"], spec["girth"],
                 spec["head"], spec["leg"], ",".join(spec["features"]) or "-"))

    tables["body_sexes"] = SEXES

    if a.dry_run:
        print("\n--dry-run: nothing written")
        return
    # Write-then-rename, matching how the game persists its own JSON.
    #
    # ensure_ascii=True on purpose. The file already stores non-ASCII as \uXXXX
    # escapes, and writing it out as literal UTF-8 rewrote every em-dash, x and
    # ellipsis in the whole table — a 188-line diff for a 9-field change, with the
    # actual edit buried in it. Match the file's existing convention.
    tmp = TABLES + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(tables, f, indent=1, ensure_ascii=True)
    os.replace(tmp, TABLES)
    print("\nwrote %s" % TABLES)


if __name__ == "__main__":
    main()
