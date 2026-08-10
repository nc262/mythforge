class_name ModularDoll extends Node3D
## Stage C — the character the player is actually wearing.
##
## THE METHOD, which is the same one Uncharted, Dark Souls and Elder Scrolls use:
## split the body into zones, make every garment its own skinned mesh, and bind
## them all to ONE skeleton. Unreal names it the Leader Pose Component; in Godot
## it is simply several MeshInstance3D pointing at the same Skeleton3D, which is
## what a glTF import already gives us.
##
## Two kinds of worn thing, and they are not the same problem:
##
##   RIGID   a helm, a sword, a shield. Parented to a BoneAttachment3D and
##           carried by one bone. Needs no skinning at all.
##   FITTED  a chestpiece, leggings. Must DEFORM with the body, so it has to be
##           skinned to the same skeleton. Sourced pre-skinned, or skinned by
##           transferring vertex weights from the base body (Blender's
##           Data Transfer -> Vertex Groups) — the standard garment workflow.
##
## POKE-THROUGH is the part everyone underestimates: an elbow stabbing through a
## sleeve. The answer is HIDDEN SURFACE REMOVAL, which is what production
## modular-character systems do — the skin under a garment is not pushed away
## from the cloth, it is not drawn. Reallusion ships it as the Hide Body Mesh
## tool and stores the visibility on the GARMENT; Roblox patented it for layered
## avatars; WoW calls the pieces geosets.
##
## Two mechanisms here, because the two rigs are shaped differently. KayKit
## arrives split into head/torso/arms/legs, so a garment names the ZONES it
## covers and those meshes switch off. The Quaternius body is ONE mesh, so it
## gets the mask variant instead: a baked greyscale image per garment in the
## body's own UV layout, unioned across the loadout, and the skin shader
## discards what it covers. See _refresh_body_mask and scripts/bake_body_masks.py.
##
## What was tried first and is WRONG: keeping the body and swelling the garment
## to clear it. Separation enforced in one pose is undone by the next, because
## skinning moves the two surfaces by different weights — the thigh cleared and
## the knee tore. Absent geometry cannot poke through anything, in any pose. If
## it needs tuning to survive standing still it cannot survive animation.
##
## EVERY RIG FACT IS DATA. Bone names, socket bones, zone mesh names and the
## parts themselves live in RIGS below, because the rig WILL change: the KayKit
## body this is verified against has 41 bones and no fingers, while the
## Quaternius base the outfits are authored for has 53 in Rigify naming. Swapping
## families has to be an entry in a dictionary, not a rewrite.

## Logical slots that get GEOMETRY. The game has thirteen; rings, amulets and
## belts are deliberately not among them — they are invisible under a sleeve at
## the size this renders, so they stay icons in the Pack and cost nothing here.
const RENDERED_SLOTS := ["head", "armor", "hands", "legs", "feet", "cloak",
	"weapon", "offhand", "shield"]

## rig id → everything that differs between one humanoid and another.
##   sockets : slot → bone that carries a RIGID piece
##   zones   : zone name → mesh names in the body that make it up
##   hides   : slot → zones a piece in that slot covers
##   parts   : slot → { part id → mesh name inside the body scene }
##             (external garment scenes are handled by equip_scene instead)
const RIGS := {
	# Verified against the CC0 KayKit Adventurers rig actually in the repo.
	# Its equipment already lives INSIDE the character scene under bone
	# attachments, so "equipping" here is showing the right child — which is the
	# cheapest possible proof that the slot/occlusion wiring is correct.
	"kaykit": {
		"body": "res://spike3d/models/Knight.glb",
		"sockets": {"head": "head", "cloak": "chest", "weapon": "handslot.r",
			"offhand": "handslot.l", "shield": "handslot.l"},
		"zones": {
			"head": ["Knight_Head", "Mage_Head"],
			"torso": ["Knight_Body", "Mage_Body"],
			"arm_l": ["Knight_ArmLeft", "Mage_ArmLeft"],
			"arm_r": ["Knight_ArmRight", "Mage_ArmRight"],
			"leg_l": ["Knight_LegLeft", "Mage_LegLeft"],
			"leg_r": ["Knight_LegRight", "Mage_LegRight"],
		},
		"hides": {
			"head": ["head"],
			"armor": ["torso"],
			"legs": ["leg_l", "leg_r"],
		},
		"parts": {
			"head": {"knight_helm": "Knight_Helmet", "mage_hat": "Mage_Hat"},
			"cloak": {"knight_cape": "Knight_Cape", "mage_cape": "Mage_Cape"},
			"weapon": {"sword_1h": "1H_Sword", "sword_2h": "2H_Sword",
				"wand": "1H_Wand", "staff": "2H_Staff"},
			"offhand": {"sword_off": "1H_Sword_Offhand", "spellbook": "Spellbook",
				"spellbook_open": "Spellbook_open"},
			"shield": {"badge": "Badge_Shield", "rect": "Rectangle_Shield",
				"round": "Round_Shield", "spike": "Spike_Shield"},
		},
		# Which part an ITEM NAME resolves to, per slot. Ordered, most specific
		# first, with the last entry as the default — "Greatsword" has to reach
		# the two-hander before "sword" claims it.
		#
		# Unlike Rules.SHAPE_WORDS, a size word is legitimate here: "great" picks
		# a genuinely different MESH, not a hoped-for scale in a picture. The trap
		# there was asking a prompt to imply size with nothing to measure against;
		# there is no such ambiguity when the word selects geometry.
		"match": {
			"head": [["hood", "mage_hat"], ["hat", "mage_hat"], ["cap", "mage_hat"],
				["circlet", "mage_hat"], ["", "knight_helm"]],
			"cloak": [["", "knight_cape"]],
			"weapon": [["greatsword", "sword_2h"], ["greataxe", "sword_2h"],
				["maul", "sword_2h"], ["two-handed", "sword_2h"],
				["staff", "staff"], ["quarterstaff", "staff"],
				["wand", "wand"], ["rod", "wand"], ["scepter", "wand"],
				["", "sword_1h"]],
			"offhand": [["book", "spellbook"], ["tome", "spellbook"],
				["grimoire", "spellbook"], ["", "sword_off"]],
			"shield": [["round", "round"], ["buckler", "round"],
				["kite", "rect"], ["tower", "rect"], ["wall", "rect"],
				["spike", "spike"], ["", "badge"]],
		},
	},

	# THE SHIPPING RIG. Quaternius Universal Base Characters + Modular Character
	# Outfits + Universal Animation Library 2 — measured at 65 shared bones,
	# 100 %, across all three. See assets3d/SOURCE.md.
	#
	# Structurally different from kaykit in one way that matters: every garment
	# is its OWN scene carrying its own copy of the skeleton, so it is worn by
	# instancing and re-pointing its skin at this doll's skeleton, not by
	# unhiding a mesh that was already inside the body. `scenes` below is that
	# list; `parts` stays empty.
	#
	# And the body is ONE mesh, not a set of zones, so `hides` is empty and stays
	# empty: there are no zones to name. This rig hides skin the other way, with
	# a baked per-garment mask — which is what the note here used to predict and
	# _refresh_body_mask now does.
	"quaternius": {
		# `{S}` is the sex token, filled at load with Male or Female. The pack
		# ships both bodies and a complete garment set for each, and writing two
		# parallel tables is how one of them silently loses a boot.
		"body": "res://assets3d/bodies/Base Characters/Godot - UE/Superhero_{S}_FullBody.gltf",
		# The clips live in their OWN file on this rig, so they are attached at
		# build time. Track paths read `Armature/Skeleton3D:pelvis` and the body
		# has exactly that shape, so an AnimationPlayer rooted at the body root
		# resolves them with no retargeting at all — which is the dividend of
		# every pack sharing one skeleton.
		# TWO libraries, and they are not interchangeable. UAL2 is situational —
		# farming, zombies, sword combos — and ships no neutral idle at all,
		# which is why the figure used to stand in a sword guard. UAL1 has the
		# plain idles, the spell set and the punches, and was RETARGETED onto
		# this rig from its Rigify original by scripts/retarget_anim.py.
		#
		# Each becomes its own named animation library, because both contain a
		# clip called `A_TPose` and adding two libraries under one name is an
		# error rather than a merge.
		"anim": [
			["", "res://assets3d/anim/UAL2_Standard.glb"],
			["ual1", "res://assets3d/anim/UAL1_Retargeted.glb"],
			["mf", "res://assets3d/anim/Authored.glb"],
		],
		# Which of the body's three materials is SKIN — the other two are eyes
		# and hair, which no garment covers. Matched on a substring because the
		# name carries the sex (MI_Superhero_Male / _Female).
		"skin_mat": "Superhero",
		# Which bones each body dimension moves. Data, like everything else about
		# a rig — the heritage spike proved this on Rigify names and these are
		# the Unreal ones for the same joints.
		"bones": {
			"head":     ["Head"],
			"leg":      ["thigh_l", "thigh_r", "calf_l", "calf_r"],
			"arm":      ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"],
			"girth":    ["pelvis", "spine_01"],
			"torso":    ["spine_02", "spine_03"],
			"shoulder": ["clavicle_l", "clavicle_r"],
			# SOFT TISSUE, on bones this pack did not ship with — added by
			# scripts/add_jiggle_bones.py to the body AND to every garment, so
			# the cloth swells and jiggles with the flesh under it.
			#
			# `chest` used to scale spine_03, which broadens a whole ribcage:
			# it made a barrel, never a bust, and it stretched the arms hanging
			# off it. These own a hand-sized patch of flesh each and nothing
			# else, which is what lets a slider mean what it says.
			"chest":    ["breast_l", "breast_r"],
			"seat":     ["glute_l", "glute_r"],
			"belly":    ["belly"],
		},
		# UAL2 is a SITUATIONAL library — farming, zombies, sword combos — with no
		# plain "Idle". The first pick here was Idle_FoldArms, which reads well
		# right up until the figurine holds something: crossed arms tuck both
		# hands into the chest and hide the weapon completely, which defeats the
		# entire purpose of a doll that shows what you equipped. A guard stance
		# keeps the hands out where the gear is visible.
		"stand": ["Sword_Block", "Idle_Shield", "Idle_Rail", "Idle_FoldArms"],
		# What the LIVE figurine plays. A different list, because the two
		# surfaces want opposite things: the board wants one readable frame, and
		# a held block is ideal there; the Gear page wants sixty frames that come
		# back round, and a one-shot block would stop dead on its last pose.
		#
		# THESE NAMES ARE GODOT'S, NOT BLENDER'S. The file on disk calls them
		# `Idle_Shield_Loop`; Godot's glTF importer reads the `_Loop` suffix as a
		# loop-mode hint, sets the mode from it and STRIPS IT FROM THE NAME. So a
		# list written from the Blender clip list matches nothing, silently — the
		# figure just keeps whatever pose it already had, which looks like a
		# design decision rather than a lookup that found no clip.
		# Every idle the figure may stand in, and one is chosen AT RANDOM per
		# build rather than first-available, so two heroes on two save files do
		# not hold the identical stance.
		#
		# `ual1/Idle` leads because UAL2 ships no neutral idle AT ALL — that is
		# why the figure used to stand in a sword guard on the Gear page whether
		# or not it was holding a sword.
		# `ual1/Sword_Idle` looks like it belongs here and does not: its source
		# name carries no `_Loop`, so it imports as a one-shot and would leave
		# the figure frozen after one play. It is a gesture instead.
		"live": ["ual1/Idle", "Idle_Shield", "ual1/Idle_Torch", "Idle_Rail",
			"Idle_FoldArms"],
		# WHAT THE FIGURE DOES BETWEEN IDLES. Every entry is a SEQUENCE, because
		# some of these are halves: a hook without its recovery leaves the fist
		# in the air, and a leap without a landing leaves the hero in orbit.
		#
		# Chosen by auditing all 43 clips as contact strips
		# (tests/gesture_shot.tscn) rather than off their names, and the audition
		# earned itself immediately — `ClimbUp_1m`, `Shield_Dash` and the whole
		# `Slide` family walk the figure clean out of the frame, and
		# `Hit_Knockback` ends flat on its back off the bottom edge. None of that
		# is visible in a name.
		#
		# The rule for inclusion is that a clip must START AND END near standing.
		# `Sword_Regular_A/B/C` are combo LINKS that finish mid-swing, so only
		# the assembled `_Combo` versions are here — the singles pop when the
		# idle blends back in.
		"gestures": {
			# With something in the hand. Swings, because a hero holding a sword
			# who never swings it reads as a mannequin holding a sword.
			#
			# The `mf/` entries are AUTHORED — see scripts/author_gestures.py.
			# Between them the two sourced libraries have 86 clips and not one
			# wave, shrug, bow or look-around: they are locomotion and task
			# libraries, and the social emotes a character needs while standing
			# still are simply not in them.
			#
			# A REPEATED ENTRY IS A WEIGHT. The pool is picked from uniformly, so
			# listing the two quiet ones twice makes the figure fidget more often
			# than it performs — which is the right ratio for something a player
			# has open while reading a stat block.
			"armed": [
				["Sword_Regular_Combo"], ["Sword_Heavy_Combo"], ["Sword_Block"],
				["ual1/Sword_Attack"], ["ual1/Sword_Idle"],
				["Melee_Hook", "Melee_Hook_Rec"],
				["OverhandThrow"], ["Idle_Shield_Break"], ["Yes"],
				["Idle_Rail_Call"], ["ual1/Interact"], ["ual1/PickUp_Table"],
				["ual1/Hit_Chest"], ["ual1/Jump_Start", "ual1/Jump_Land"],
				["mf/Bow"], ["mf/Shrug"], ["mf/HandsOnHips"], ["mf/Cheer"],
				["mf/Beckon"],
				["mf/LookAround"], ["mf/LookAround"],
				["mf/ShiftWeight"], ["mf/ShiftWeight"],
			],
			# Empty-handed. Everything above that does not want a blade in it,
			# plus the emotes that only read with a free hand.
			"bare": [
				["Yes"], ["Idle_Rail_Call"], ["Consume"], ["Chest_Open"],
				["ual1/Punch_Jab"], ["ual1/Punch_Cross"], ["ual1/Punch_Enter"],
				["ual1/Interact"], ["ual1/PickUp_Table"], ["OverhandThrow"],
				["Idle_Shield_Break"], ["ual1/Hit_Chest"],
				["ual1/Jump_Start", "ual1/Jump_Land"],
				["mf/Wave"], ["mf/Bow"], ["mf/Shrug"], ["mf/HandsOnHips"],
				["mf/Cheer"], ["mf/Stretch"], ["mf/Beckon"],
				["mf/LookAround"], ["mf/LookAround"],
				["mf/ShiftWeight"], ["mf/ShiftWeight"],
			],
			# ADDED to whichever pool above, for a hero who actually casts.
			# `Rules.caster_level` already answers that, so a barbarian never
			# throws an arcane flourish — which is the sort of thing that reads
			# as the game not knowing who your character is.
			#
			# `Spell_Simple_Idle` is deliberately absent from the sequence: it
			# is a LOOP, and a loop in a gesture stops the director dead.
			"caster": [
				["ual1/Spell_Simple_Enter", "ual1/Spell_Simple_Shoot", "ual1/Spell_Simple_Exit"],
				["ual1/Spell_Simple_Enter", "ual1/Spell_Simple_Shoot",
					"ual1/Spell_Simple_Shoot", "ual1/Spell_Simple_Exit"],
			],
		},
		"sockets": {"weapon": "hand_r", "offhand": "hand_l", "shield": "hand_l",
			"head": "Head", "cloak": "spine_03"},
		"zones": {},
		"hides": {},
		"parts": {},
		# RIGID props — weapons and shields. They ride a BoneAttachment3D on the
		# hand bone and never need skin weights, which is exactly why a pack
		# built for no particular skeleton can fill these slots: a sword is a
		# sword whatever the rig underneath it.
		#
		# These are OBJ, so they arrive as a bare Mesh with no scene, no
		# material and no rig — the doll wraps each in a MeshInstance3D itself.
		"props": {
			"weapon": {"sword": "res://assets3d/weapons/Sword.obj",
				"sword_big": "res://assets3d/weapons/Sword_Big.obj",
				"claymore": "res://assets3d/weapons/Claymore.obj",
				"dagger": "res://assets3d/weapons/Dagger.obj",
				"axe": "res://assets3d/weapons/Axe.obj",
				"axe_big": "res://assets3d/weapons/Axe_Double.obj",
				"hammer": "res://assets3d/weapons/Hammer_Small.obj",
				"maul": "res://assets3d/weapons/Hammer_Double.obj",
				"spear": "res://assets3d/weapons/Spear.obj",
				"scythe": "res://assets3d/weapons/Scythe.obj",
				"bow": "res://assets3d/weapons/Bow_Wooden.obj"},
			"offhand": {"dagger": "res://assets3d/weapons/Dagger_2.obj",
				"sword": "res://assets3d/weapons/Sword_2.obj",
				"axe": "res://assets3d/weapons/Axe_Small.obj"},
			"shield": {"heater": "res://assets3d/weapons/Shield_Heater.obj",
				"round": "res://assets3d/weapons/Shield_Round.obj",
				"celtic": "res://assets3d/weapons/Shield_Celtic_Golden.obj"},
		},
		# How a prop sits in the hand. `len` is a TARGET LENGTH in world units for
		# the mesh's longest axis, not a scale factor — the first version guessed
		# a factor and produced a sword bigger than the man holding it, because a
		# pack's authored scale is nothing you can reason about from here.
		# Measuring the mesh and scaling to a known size works for any pack.
		#
		# Per slot, because a shield is held flat against the forearm and a sword
		# points along it. Numbers set by rendering and looking; a 1.8 m figure
		# carries a ~0.85 m arming sword and a ~0.6 m shield.
		"prop_fit": {
			"weapon":  {"len": 0.85, "rot": Vector3(0, 0, -90), "pos": Vector3(0, 0.02, 0)},
			"offhand": {"len": 0.55, "rot": Vector3(0, 0, -90), "pos": Vector3(0, 0.02, 0)},
			"shield":  {"len": 0.60, "rot": Vector3(0, 90, 0),  "pos": Vector3(0, 0.03, 0)},
		},
		# A dagger is not a claymore. The slot default sizes an arming sword, and
		# using it for everything made a dagger read as a short sword and a spear
		# as a walking stick — the one distinction the ICON pipeline could never
		# draw (KnownIssues #5, size within a category) is free here, because
		# this is geometry and geometry has a length.
		"prop_len": {
			"dagger": 0.38, "hammer": 0.7, "axe": 0.8,
			"sword": 0.85, "bow": 1.1,
			"sword_big": 1.15, "axe_big": 1.15, "maul": 1.2,
			"claymore": 1.35, "scythe": 1.7, "spear": 1.9,
		},
		"scenes": {
			"armor":  {"ranger": "res://assets3d/outfits/Modular Parts/{S}_Ranger_Body.gltf",
				"peasant": "res://assets3d/outfits/Modular Parts/{S}_Peasant_Body.gltf"},
			"hands":  {"ranger": "res://assets3d/outfits/Modular Parts/{S}_Ranger_Arms.gltf",
				"peasant": "res://assets3d/outfits/Modular Parts/{S}_Peasant_Arms.gltf"},
			"legs":   {"ranger": "res://assets3d/outfits/Modular Parts/{S}_Ranger_Legs.gltf",
				"peasant": "res://assets3d/outfits/Modular Parts/{S}_Peasant_Legs.gltf"},
			# The pack's own naming diverges here and nowhere else — the male file
			# is `Ranger_Feet_Boots`, the female just `Ranger_Feet` — so this one
			# entry is an explicit pair rather than a `{S}` template. Worth the
			# exception: the template covers eleven other files correctly, and
			# the alternative is guessing at suffixes.
			"feet":   {"ranger": {"male": "res://assets3d/outfits/Modular Parts/Male_Ranger_Feet_Boots.gltf",
					"female": "res://assets3d/outfits/Modular Parts/Female_Ranger_Feet.gltf"},
				"peasant": "res://assets3d/outfits/Modular Parts/{S}_Peasant_Feet.gltf"},
			"head":   {"hood": "res://assets3d/outfits/Modular Parts/{S}_Ranger_Head_Hood.gltf"},
			# The pack's second naming divergence, and the same shape as `feet`
			# below: the male file is `Acc_Pauldron`, the female `Acc_Pauldrons`.
			# The `{S}` template silently resolved to a path that does not exist,
			# `equip` returned false, and no female hero has ever worn a pauldron
			# — which reads as "the game chose not to draw it" rather than as a
			# missing file, so nobody looked. The mask for it was baked all along.
			"cloak":  {"pauldrons": {"male": "res://assets3d/outfits/Modular Parts/Male_Ranger_Acc_Pauldron.gltf",
				"female": "res://assets3d/outfits/Modular Parts/Female_Ranger_Acc_Pauldrons.gltf"}},
		},
		# UNDERCLOTHES. A hero with no leggings equipped is not naked, they are in
		# whatever they own — so an empty slot falls back to the peasant set
		# rather than to skin. Without this the figurine stands in its underwear
		# any time the player has not found trousers yet, which is most of act
		# one. `head` and `cloak` are absent on purpose: bare-headed and
		# cloakless are normal, bare-legged is not.
		"default": {"armor": "peasant", "hands": "peasant", "legs": "peasant", "feet": "peasant"},
		# ── APPEARANCE, WHICH IS NOT EQUIPMENT ───────────────────────────────
		# Hair is not something a hero finds in a chest, so it is deliberately
		# not one of RENDERED_SLOTS and `wear_inventory` never touches it. It is
		# set once at build from the sheet, like sex and heritage.
		#
		# Mechanically it IS a garment: every one of these is skinned to the same
		# 65 bones, so they ride `_wear_file` with nothing new underneath. That
		# is the dividend of one rig, again — five hairstyles and a beard for a
		# table.
		#
		# EYEBROWS AND EYES ARE NOT HERE because the body already carries them as
		# their own meshes. The pack ships standalone brow meshes too; wearing
		# those as well would give every hero two sets.
		"hair": {
			"long": "res://assets3d/bodies/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Long.gltf",
			"buns": "res://assets3d/bodies/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Buns.gltf",
			"parted": "res://assets3d/bodies/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_SimpleParted.gltf",
			# ONE cut, authored twice. `Hair_BuzzedFemale` is not a second style
			# — it is the same 466-vertex shell sitting 43 mm lower, because the
			# female head is 43 mm lower. Offering both as separate choices gave
			# a menu with a dead entry: whichever one was cut for the other body
			# sinks under the scalp and renders as bald.
			#
			# Same shape as the `feet` entry above, and the same reason.
			"buzzed": {"male": "res://assets3d/bodies/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Buzzed.gltf",
				"female": "res://assets3d/bodies/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_BuzzedFemale.gltf"},
		},
		"beard": {
			"full": "res://assets3d/bodies/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Beard.gltf",
		},
		# HORNS, grown by scripts/author_horns.py rather than sourced — no free
		# pack ships them, and a horn is a swept tube, which is arithmetic.
		#
		# Skinned entirely to the `Head` bone at weight 1, so as far as this
		# class is concerned they are a garment: worn through `_wear_file`, and
		# they follow the head through every animation with no socket, no bone
		# attachment and no second code path.
		#
		# Paired by sex for the same reason the buzz cut is: the two skulls sit
		# 43 mm apart, and the roots are seeded off each body's own surface.
		"horns": {
			"ram":    {"male": "res://assets3d/horns/Male_ram.glb",
				"female": "res://assets3d/horns/Female_ram.glb"},
			"swept":  {"male": "res://assets3d/horns/Male_swept.glb",
				"female": "res://assets3d/horns/Female_swept.glb"},
			"spire":  {"male": "res://assets3d/horns/Male_spire.glb",
				"female": "res://assets3d/horns/Female_spire.glb"},
			"nub":    {"male": "res://assets3d/horns/Male_nub.glb",
				"female": "res://assets3d/horns/Female_nub.glb"},
		},
		# What a hero looks like before anyone chooses. Bald is a CHOICE, not a
		# default — a figurine with no hair reads as unfinished, which is exactly
		# how every render in this repo has read until now.
		"look_default": {
			"male": {"hair": "parted", "beard": ""},
			"female": {"hair": "long", "beard": ""},
		},
		# Two archetypes is what the pack actually ships (see SOURCE.md), so the
		# match table sorts every item name into one of them. Leather, hide and
		# studded read as the ranger; cloth and common wear read as the peasant.
		"match": {
			"armor": [["leather", "ranger"], ["hide", "ranger"], ["studded", "ranger"],
				["scale", "ranger"], ["chain", "ranger"], ["plate", "ranger"],
				["mail", "ranger"], ["", "peasant"]],
			"hands": [["gauntlet", "ranger"], ["bracer", "ranger"], ["vambrace", "ranger"],
				["leather", "ranger"], ["", "peasant"]],
			"legs":  [["greave", "ranger"], ["leather", "ranger"], ["chain", "ranger"],
				["plate", "ranger"], ["", "peasant"]],
			"feet":  [["boot", "ranger"], ["greave", "ranger"], ["", "peasant"]],
			"head":  [["hood", "hood"], ["cowl", "hood"], ["hat", "hood"], ["cap", "hood"],
				["helm", "hood"], ["", "hood"]],
			"cloak": [["", "pauldrons"]],
			# Specific before generic, and the two-handers before their family —
			# "Greataxe" must reach the big axe before "axe" claims it. Same
			# ordering rule the item-icon table learned the hard way.
			"weapon": [["claymore", "claymore"], ["greatsword", "claymore"],
				["longsword", "sword_big"], ["bastard", "sword_big"],
				["greataxe", "axe_big"], ["battleaxe", "axe_big"],
				["maul", "maul"], ["warhammer", "maul"],
				["hammer", "hammer"], ["mace", "hammer"],
				["axe", "axe"], ["hatchet", "axe"],
				["scythe", "scythe"], ["glaive", "scythe"],
				["spear", "spear"], ["pike", "spear"], ["lance", "spear"], ["halberd", "spear"],
				["bow", "bow"], ["sling", "bow"],
				["dagger", "dagger"], ["knife", "dagger"], ["dirk", "dagger"],
				["", "sword"]],
			"offhand": [["axe", "axe"], ["sword", "sword"], ["", "dagger"]],
			"shield": [["round", "round"], ["buckler", "round"],
				["kite", "heater"], ["tower", "heater"], ["heater", "heater"],
				["gold", "celtic"], ["ornate", "celtic"], ["", "heater"]],
		},
	},
}


## Which part of this rig an item NAME calls for in a slot, or "" if the rig has
## nothing for that slot. Case-insensitive substring, first match wins, and the
## empty key is the catch-all — so an unrecognised sword is still a sword rather
## than an empty hand.
func part_for(slot: String, item_name: String) -> String:
	var table: Array = profile().get("match", {}).get(slot, [])
	var low := item_name.to_lower()
	for pair in table:
		var kw := str(pair[0])
		if kw == "" or low.contains(kw):
			return str(pair[1])
	return ""


## Dress the doll from the player's actual equipment. Takes the inventory the
## game already keeps, so nothing here invents a second source of truth about
## what is worn.
func wear_inventory(inv: Dictionary) -> void:
	var equipped: Dictionary = inv.get("equipped", {}) if inv.get("equipped") is Dictionary else {}
	var by_id := {}
	for it in inv.get("items", []):
		if it is Dictionary:
			by_id[str(it.get("id", ""))] = str(it.get("name", ""))
	# Every slot this rig can actually show, asked from the rig rather than
	# hard-coded: kaykit answers for five, quaternius for nine. A slot with no
	# geometry resolves to "" and the doll simply does not wear it — silently
	# doing nothing beats pretending.
	for slot in RENDERED_SLOTS:
		if not _rig_has_slot(slot):
			continue
		var iid := str(equipped.get(slot, ""))
		if iid == "" or not by_id.has(iid):
			# Nothing equipped → the rig's underclothes, or truly bare if it
			# names none for this slot.
			equip(slot, str(profile().get("default", {}).get(slot, "")))
			continue
		equip(slot, part_for(slot, str(by_id[iid])))


func _rig_has_slot(slot: String) -> bool:
	var prof := profile()
	return prof.get("parts", {}).has(slot) or prof.get("scenes", {}).has(slot) \
		or prof.get("props", {}).has(slot)

## Does this hero cast? Gates the spell gestures, and nothing else. Set by the
## view from `Rules.caster_level`, because the doll has no business reading a
## character sheet.
var caster := false

var rig := "quaternius"
## Which body and which garment cut. Set before build(); the pack ships a full
## set for each, and the female ranger is not the male one scaled.
var sex := "male"
var skeleton: Skeleton3D = null


## Fill the `{S}` sex token. Files are named Male_/Female_, so the value is
## capitalised here rather than at every call site.
func _sexed(path: String) -> String:
	return path.replace("{S}", "Female" if sex == "female" else "Male")


## The body this rig dresses, so a caller does not have to know the path.
func body_path() -> String:
	return _sexed(str(profile().get("body", "res://spike3d/models/Knight.glb")))

var _body: Node3D = null
var _zone_meshes := {}    # zone → Array[MeshInstance3D]
var _worn := {}           # slot → part id (or "" when bare)
var _worn_file := {}      # slot → the garment's own res:// path, for its mask
var _extern := {}         # slot → the Node3D we instanced for an external part
## Bind pose, captured once per body. apply_build scales FROM here every time,
## because scaling an already-scaled bone compounds — drag a slider twice and
## the hero doubles.
var _rest := {}


func profile() -> Dictionary:
	return RIGS.get(rig, RIGS["kaykit"])


## Put a body on the stand. Every mesh in the scene is catalogued by zone and
## every part is hidden, so the doll starts BARE and equipping is purely additive
## — a body that arrives with its helmet already on hides the bug where a slot
## never actually took effect.
func build(body_scene: PackedScene) -> void:
	if _body != null and is_instance_valid(_body):
		remove_child(_body)      # same reason as unequip_scene: not next frame, now
		_body.queue_free()
	_zone_meshes.clear()
	_worn.clear()
	_worn_file.clear()
	_extern.clear()
	# The gesture director outlives the body it was driving — the Timer is a
	# child of THIS node, not of `_body`. Left running, it fires into a
	# half-rebuilt figure and picks a pool from a loadout that has been cleared.
	_queue.clear()
	_idle = ""
	if _life != null and is_instance_valid(_life):
		_life.stop()
	_rest.clear()   # a new body has a new bind pose; keeping the old one warps it
	_body = body_scene.instantiate()
	add_child(_body)
	skeleton = _find_skeleton(_body)
	var prof := profile()
	var zones: Dictionary = prof.get("zones", {})
	for zone in zones:
		_zone_meshes[zone] = []
		for nm in zones[zone]:
			var found := _find_mesh(_body, str(nm))
			if found != null:
				_zone_meshes[zone].append(found)
	# Every catalogued PART starts hidden, whatever the scene shipped with.
	for slot in prof.get("parts", {}):
		for pid in prof["parts"][slot]:
			var m := _find_mesh(_body, str(prof["parts"][slot][pid]))
			if m != null:
				m.visible = false
		_worn[slot] = ""
	_attach_anim(prof)
	_add_jiggle()
	stand()
	_refresh_zones()


## Borrow a shared animation library. Only needed where the clips ship apart from
## the body — the KayKit rig carries its own, so this is a no-op there.
func _attach_anim(prof: Dictionary) -> void:
	var libs: Array = prof.get("anim", [])
	if libs.is_empty() or _body == null:
		return
	if _find_anim(_body) != null:
		return                       # the body already brought clips of its own
	var ap: AnimationPlayer = null
	for entry in libs:
		var name := str(entry[0])
		var path := str(entry[1])
		if not ResourceLoader.exists(path):
			continue
		var src = load(path).instantiate()
		var sap := _find_anim(src)
		if sap == null:
			src.queue_free()
			continue
		if ap == null:
			ap = AnimationPlayer.new()
			_body.add_child(ap)
			# Rooted at the body, because the clips' track paths are written
			# relative to the glTF root they came from and every file shares
			# that shape — which is the dividend of one skeleton, and the whole
			# reason UAL1 was retargeted onto it rather than played as it came.
			ap.root_node = ap.get_path_to(_body)
		for lib in sap.get_animation_library_list():
			# A file's own libraries are almost always the unnamed default; the
			# name here is OURS, so two files cannot collide.
			var key: String = name if str(lib) == "" else "%s_%s" % [name, lib]
			if not ap.has_animation_library(key):
				ap.add_animation_library(key, sap.get_animation_library(lib))
		src.queue_free()


## Hair, beard, and the colour of them. Appearance, not equipment — set once at
## build from the sheet, never from the pack.
##
## Mechanically each piece is a garment on the shared skeleton, so it goes
## through the same `_wear_file` the wardrobe uses, with the dye switched off.
func apply_look(look: Dictionary) -> void:
	var prof := profile()
	var fallback: Dictionary = prof.get("look_default", {}).get(sex, {})
	for kind in ["hair", "beard", "horns"]:
		var table: Dictionary = prof.get(kind, {})
		if table.is_empty():
			continue
		# An ABSENT key falls back to the default look; an explicitly EMPTY one
		# means bald or clean-shaven and must be honoured. `has` is the whole
		# distinction, and `get(kind, "")` would collapse it.
		var pick := str(look[kind]) if look.has(kind) else str(fallback.get(kind, ""))
		unequip_scene(kind)
		_worn[kind] = ""
		if pick == "" or not table.has(pick):
			continue
		# A value is either a plain path or, where the pack cut the piece twice,
		# a {male:…, female:…} pair — same convention the wardrobe already uses.
		var entry = table[pick]
		var path := str(entry.get(sex, entry.get("male", ""))) if entry is Dictionary else str(entry)
		if not ResourceLoader.exists(path):
			continue
		if _wear_file(kind, load(path), false):
			_worn[kind] = pick
	_tint_hair(HAIR_COLORS.get(str(look.get("hair_color", DEFAULT_HAIR)),
		HAIR_COLORS[DEFAULT_HAIR]))
	skin_tint = SKIN_TONES.get(str(look.get("skin", DEFAULT_SKIN)), SKIN_TONES[DEFAULT_SKIN])
	_tint_horns(HORN_COLORS.get(str(look.get("horn_color", DEFAULT_HORN)),
		HORN_COLORS[DEFAULT_HORN]))
	_refresh_zones()


## The colour of every hair piece worn.
##
## A MULTIPLY over the pack's own texture, not a flat fill: the strand detail,
## the roots and the specular break-up all live in that albedo, and replacing it
## outright gives a helmet of solid colour.
##
## THE TINT IS THE HAIR COLOUR, not a wash over one. The pack authors its hair
## near-white so that any colour can multiply onto it — which means leaving the
## tint bright does not mean "as authored", it means PLATINUM, and the first
## render of this gave a party of silver-haired seventy-year-olds.
##
## A palette rather than a free colour: six that read at 230x336 and against the
## eight world skins. Free RGB would let a player pick a hair that vanishes into
## whatever hood they later put on.
const HAIR_COLORS := {
	"black": Color(0.10, 0.09, 0.10),
	"brown": Color(0.29, 0.18, 0.11),
	"auburn": Color(0.42, 0.17, 0.09),
	"blond": Color(0.78, 0.62, 0.31),
	"grey": Color(0.62, 0.61, 0.60),
	"white": Color(0.88, 0.87, 0.85),
}
const DEFAULT_HAIR := "brown"

## Skin, multiplied over the pack's own albedo so freckles, lips and brows
## survive it. The natural tones sit near 1.0 because the texture is already a
## skin; the heritage tints are the ones that do real work.
##
## THIS IS WHAT MAKES A TIEFLING POSSIBLE AT ALL on one base body. Horns and a
## tail are geometry and can be attached; the crimson is a tint, and without it
## a tiefling is a human with horns.
const SKIN_TONES := {
	"fair":    Color(1.06, 0.98, 0.94),
	"tan":     Color(0.92, 0.80, 0.66),
	"olive":   Color(0.82, 0.74, 0.56),
	"brown":   Color(0.62, 0.45, 0.33),
	"deep":    Color(0.40, 0.28, 0.21),
	"ashen":   Color(0.74, 0.74, 0.78),
	"crimson": Color(0.86, 0.30, 0.26),
	"violet":  Color(0.60, 0.42, 0.72),
	"verdant": Color(0.52, 0.68, 0.42),
	"azure":   Color(0.44, 0.62, 0.80),
}
const DEFAULT_SKIN := "tan"

## Horn is keratin, not hair, and takes its own colour: a bone-white pair over
## crimson skin is a very different character from a black pair, and neither
## should follow whatever the hero did with their hair.
const HORN_COLORS := {
	"onyx":  Color(0.13, 0.12, 0.13),
	"ash":   Color(0.34, 0.31, 0.29),
	"bone":  Color(0.78, 0.74, 0.65),
	"amber": Color(0.55, 0.36, 0.16),
}
const DEFAULT_HORN := "ash"

## The live tint, set by `apply_look`. Held as a Color rather than a key because
## the shader is rebuilt on every re-dress and re-reading the palette each time
## is the sort of thing that quietly disagrees with itself.
var skin_tint := Color(1.0, 1.0, 1.0)


func _tint_hair(c: Color) -> void:
	# THE EYEBROWS ARE THE BODY'S, not a worn piece — they arrive as their own
	# mesh inside the base character, on the same MI_Hair material the wigs use.
	# Tinting only the worn hair gave every hero white eyebrows over black hair,
	# which at Gear-page size reads as a very surprised old man.
	var holders: Array = [_body]
	for kind in ["hair", "beard"]:
		if _extern.has(kind) and is_instance_valid(_extern[kind]):
			holders.append(_extern[kind])
	for holder in holders:
		if holder == null or not is_instance_valid(holder):
			continue
		for mi in _all_meshes(holder):
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var src = mi.mesh.surface_get_material(i)
				# Only the HAIR material. The body carries eyes and skin on the
				# same mesh list, and dyeing an eyeball black is memorable.
				if not (src is StandardMaterial3D) or not src.resource_name.contains("Hair"):
					continue
				var m: StandardMaterial3D = src.duplicate()
				m.albedo_color = c
				mi.set_surface_override_material(i, m)


func _tint_horns(c: Color) -> void:
	if not _extern.has("horns") or not is_instance_valid(_extern["horns"]):
		return
	for mi in _all_meshes(_extern["horns"]):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src = mi.mesh.surface_get_material(i)
			if not (src is StandardMaterial3D):
				continue
			var m: StandardMaterial3D = src.duplicate()
			m.albedo_color = c
			mi.set_surface_override_material(i, m)


## Give the figurine its body: heritage, sex, and whatever the player set.
##
## Bone scale, never separate geometry — which is the whole reason nine
## heritages times two sexes times five knobs does not mean a wardrobe per
## combination. Every garment is skinned to these same bones, so it follows the
## shape for free.
##
## BONE SCALE COMPOUNDS INTO CHILDREN, and that is the trap the heritage spike
## hit: scaling the chest uniformly stretched the arms hanging off it, so a
## broad hero came out with long arms too. Girth and shoulders are therefore
## WIDTH AND DEPTH ONLY (X/Z, never Y); limbs are the reverse, length only; the
## head is the one group that scales evenly because nothing hangs below it.
func apply_build(shape: Dictionary) -> void:
	if skeleton == null or _body == null:
		return
	var groups: Dictionary = profile().get("bones", {})
	if groups.is_empty():
		return
	if _rest.is_empty():
		for i in skeleton.get_bone_count():
			_rest[i] = skeleton.get_bone_pose(i)
	else:
		for i in _rest:
			skeleton.set_bone_pose(i, _rest[i])   # back to bind, or the scales stack
	for g in groups:
		var f := float(shape.get(g, 1.0))
		if is_equal_approx(f, 1.0):
			continue
		for nm in groups[g]:
			var bi := skeleton.find_bone(str(nm))
			if bi < 0:
				continue
			var t: Transform3D = skeleton.get_bone_pose(bi)
			match str(g):
				# EVEN, because nothing hangs off these. The head has no
				# children, and a soft-tissue bone has none either — it is a
				# lump of flesh on a stick, so scaling it evenly swells that
				# lump radially, which is what a bust or a paunch IS.
				"head", "chest", "seat", "belly":
					t = t.scaled_local(Vector3.ONE * f)
				"girth", "shoulder", "torso":
					t = t.scaled_local(Vector3(f, 1.0, f))
				_:
					t = t.scaled_local(Vector3(1.0, f, 1.0))
			skeleton.set_bone_pose(bi, t)
	# Height is the whole figure, not a bone — scaling a spine to gain height
	# stretches the head and hands with it.
	_body.scale = Vector3.ONE * float(shape.get("height", 1.0))


## Put the figurine on its feet and FREEZE it there. This is the pose the BOARD
## TOKEN and the painted scene hero are made from — one frame, captured once per
## loadout, so a looping animation behind them would be GPU nobody can see.
func stand() -> void:
	var ap := _play(profile().get("stand", ["Idle", "Idle_Loop", "1H_Melee_Idle"]))
	if ap != null:
		ap.pause()


## Put the figurine on its feet and LEAVE IT BREATHING. This is the Gear page,
## which is a different object from the board token and wants the opposite
## trade: the player is looking straight at their hero and a statue reads as a
## bug. The viewport it lives in is UPDATE_WHEN_VISIBLE, so the cost is paid
## only while the page is open.
##
## The spring simulation is switched on HERE and nowhere else. Jiggle on a
## paused pose is a per-frame cost with nothing to show for it.
func live() -> void:
	var ap := _play(_idle_choices())
	if ap == null:
		return
	_idle = ap.current_animation
	if not ap.animation_finished.is_connected(_next_clip):
		ap.animation_finished.connect(_next_clip)
	if _life == null or not is_instance_valid(_life):
		_life = Timer.new()
		_life.one_shot = true
		_life.timeout.connect(_gesture)
		add_child(_life)
	set_living(true)


## Start or stop everything that costs a frame. Its caller is whoever knows
## whether the figure is on screen — this class cannot, because the same doll is
## a live figure on one page and a frozen capture on another.
func set_living(on: bool) -> void:
	var ap := _find_anim(_body)
	if ap != null:
		ap.active = on
	if _spring != null and is_instance_valid(_spring):
		_spring.active = on
	if _life == null or not is_instance_valid(_life):
		return
	if on:
		_life.start(randf_range(GAP_MIN, GAP_MAX))
	else:
		# Or a page left hidden for a minute comes back mid-swing, because the
		# timer went on firing into a viewport nobody was drawing.
		_life.stop()


## ── THE LIFE OF THE FIGURE ───────────────────────────────────────────────────
## An idle on repeat is a screensaver. What reads as ALIVE is an idle that keeps
## being interrupted: a hero looks at the blade, shakes the stance out, swings,
## hops, goes back to standing there.
##
## Deliberately NOT an AnimationTree. A state machine earns its keep when
## transitions are conditional and gameplay drives them; here there is one state
## with a random excursion out of it and straight back, and the whole director is
## the twenty lines below. `play(name, blend)` cross-fades on its own.
##
## Rotation is untouched by any of this. The player drags a Node3D pivot ABOVE
## the doll, and the clips move bones inside the skeleton, so turning the figure
## mid-swing works for free and always did.

## Seconds of idling between gestures. The low end is short enough that the page
## does not feel dead while you are reading a stat block, the high end long
## enough that the figure is not performing at you.
const GAP_MIN := 2.6
const GAP_MAX := 6.5
## Cross-fade into and out of a gesture. Below about 0.15 the swing snaps on;
## above 0.35 the wind-up is eaten by the blend and the swing looks half-hearted.
const BLEND := 0.22

var _life: Timer = null
var _idle := ""
var _queue: Array[String] = []


## Pick a sequence and start it. Which pool depends on what is in the hand — a
## hero holding a sword who never swings it reads as a mannequin holding a sword,
## and one swinging an empty fist reads as a bug.
func _gesture() -> void:
	var ap := _find_anim(_body)
	if ap == null or _idle == "":
		return
	var pools: Dictionary = profile().get("gestures", {})
	var pool: Array = (pools.get("armed" if worn("weapon") != "" else "bare", []) as Array).duplicate()
	if caster:
		pool.append_array(pools.get("caster", []))
	var seq := _playable(ap, pool)
	if seq.is_empty():
		return
	_queue = seq
	_next_clip("")


## Advance the sequence, or fall back to idling and re-arm the timer.
##
## `animation_finished` never fires for a looping clip, which is exactly the
## behaviour wanted: the idle runs until the timer interrupts it, and only a
## gesture — every one of which is a one-shot — comes back here.
func _next_clip(_finished: String) -> void:
	var ap := _find_anim(_body)
	if ap == null:
		return
	if _queue.is_empty():
		ap.play(_idle, BLEND)
		if _life != null and is_instance_valid(_life):
			_life.start(randf_range(GAP_MIN, GAP_MAX))
		return
	ap.play(_queue.pop_front(), BLEND)


## One sequence from the pool, filtered down to clips this library actually has
## and that actually END.
##
## THE LOOP CHECK IS NOT PARANOIA. A looping clip never emits
## `animation_finished`, so one loop in a gesture list does not misbehave — it
## STOPS THE DIRECTOR DEAD, permanently, and the figure stands there repeating
## the last thing it did. Godot's glTF importer decides loop mode from a `_Loop`
## suffix it then strips, so which clips loop is not something you can read off
## the names in the table.
func _playable(ap: AnimationPlayer, pool: Array) -> Array[String]:
	var ok: Array = []
	for seq in pool:
		var good := true
		for nm in seq:
			var clip := ap.get_animation(str(nm))
			if clip == null or clip.loop_mode != Animation.LOOP_NONE:
				good = false
				break
		if good:
			ok.append(seq)
	if ok.is_empty():
		return []
	var out: Array[String] = []
	for nm in ok[randi() % ok.size()]:
		out.append(str(nm))
	return out


## Every idle on the list this library actually has AND that loops, shuffled.
##
## Random rather than first-available, so two heroes on two save files do not
## hold the identical stance — `_play` takes the first entry it can find, so
## shuffling the list IS the choice.
##
## The loop test is the same one the gestures get, inverted: an idle that does
## not loop plays once and leaves the figure frozen until the next gesture,
## which looks exactly like a game that has hung.
func _idle_choices() -> Array:
	var ap := _find_anim(_body)
	var want: Array = profile().get("live", profile().get("stand", ["Idle"]))
	if ap == null:
		return want
	var ok: Array = []
	for w in want:
		var clip := ap.get_animation(str(w))
		if clip != null and clip.loop_mode != Animation.LOOP_NONE:
			ok.append(w)
	if ok.is_empty():
		return want
	ok.shuffle()
	return ok


## Find the first clip on the preference list and play it. Returns the player so
## the caller can decide whether it keeps running.
##
## PREFERENCE OUTERMOST. The first version looped clips on the outside and
## preferences on the inside, so whichever clip came first ALPHABETICALLY and
## appeared anywhere in the list won — `Idle_FoldArms` beat `Sword_Block` every
## time and the priority order was decoration. The list looked obeyed and was
## not, which is the worst kind of wrong.
func _play(want: Array) -> AnimationPlayer:
	var ap := _find_anim(_body)
	if ap == null:
		return null
	for w in want:
		for lib in ap.get_animation_library_list():
			for nm in ap.get_animation_library(lib).get_animation_list():
				if str(nm).nocasecmp_to(str(w)) != 0:
					continue
				var full: String = (str(lib) + "/" + str(nm)) if str(lib) != "" else str(nm)
				ap.play(full)
				ap.advance(0.35)   # a step in, past any wind-up on frame zero
				return ap
	return null


## ── JIGGLE ───────────────────────────────────────────────────────────────────
## Flesh does not stop when the bone carrying it stops. Godot ships
## SpringBoneSimulator3D for exactly this, so there is no simulation to write:
## each soft-tissue bone becomes a ONE-BONE CHAIN whose tip is synthesised by
## `extend_end_bone`, which is why the rig needed no leaf bones added to it.
##
## The garments are weighted to these same bones (scripts/add_jiggle_bones.py),
## so a bust under a tunic moves the tunic. Skip that and the hidden-surface
## mask makes it worse rather than better — the skin under the cloth is deleted,
## so a jiggle that only moved the skin would be invisible right up until it
## punched through.
##
## `stiffness` is how hard the flesh returns to where the animation put it,
## `drag` how fast it gives up, `gravity` how much it sags, and `length` the
## lever the spring pulls on. Chosen off a four-point sweep rendered against a
## FROZEN pose (tests/jiggle_shot.gd), because the obvious test — run the idle
## twice and diff it — cannot work: two real-time runs never land on the same
## animation phase, so the whole silhouette lights up and the jiggle is lost
## inside it. Held still, every pixel that moves is the simulation.
##
## Measured, tightest to loosest: 0.518 / 0.540 / 0.677 / 0.740 peak pixel
## displacement. The looser end keeps paying, so the limit is taste, not range —
## the last step reads as rubber rather than flesh. These sit one notch back
## from it, and the three parts differ because they are different tissue: a
## belly is heavy and slow, a seat is firm, a bust is neither.
const JIGGLE := {
	"breast_l": {"stiffness": 0.14, "drag": 0.14, "gravity": 0.14, "radius": 0.05, "length": 0.16},
	"breast_r": {"stiffness": 0.14, "drag": 0.14, "gravity": 0.14, "radius": 0.05, "length": 0.16},
	"glute_l":  {"stiffness": 0.22, "drag": 0.20, "gravity": 0.10, "radius": 0.05, "length": 0.14},
	"glute_r":  {"stiffness": 0.22, "drag": 0.20, "gravity": 0.10, "radius": 0.05, "length": 0.14},
	"belly":    {"stiffness": 0.12, "drag": 0.22, "gravity": 0.16, "radius": 0.05, "length": 0.16},
}

var _spring: SpringBoneSimulator3D = null


## Hang a spring simulation off whichever soft-tissue bones this body actually
## has. A body rigged before add_jiggle_bones.py existed has none of them, and
## gets no simulator rather than a broken one.
func _add_jiggle() -> void:
	_spring = null
	if skeleton == null:
		return
	var names: Array[String] = []
	for nm in JIGGLE:
		if skeleton.find_bone(str(nm)) >= 0:
			names.append(str(nm))
	if names.is_empty():
		return
	# BEFORE the springs, because modifiers run in child order and the springs
	# should answer to the planted pose rather than to a translation that is
	# about to be undone.
	var plant := PlantFeet.new()
	plant.name = "Plant"
	skeleton.add_child(plant)
	var sim := SpringBoneSimulator3D.new()
	sim.name = "Jiggle"
	skeleton.add_child(sim)
	sim.set_setting_count(names.size())
	for i in names.size():
		var cfg: Dictionary = JIGGLE[names[i]]
		# Root AND end are the same bone. A chain of one is legal here precisely
		# because `extend_end_bone` invents the tip that the spring pulls on —
		# without it the simulator has a chain with no free end and does nothing.
		sim.set_root_bone_name(i, names[i])
		sim.set_end_bone_name(i, names[i])
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, float(cfg.get("length", 0.15)))
		sim.set_stiffness(i, float(cfg.get("stiffness", 0.15)))
		sim.set_drag(i, float(cfg.get("drag", 0.15)))
		sim.set_radius(i, float(cfg.get("radius", 0.05)))
		sim.set_gravity(i, float(cfg.get("gravity", 0.1)))
	# Off until live() asks. The board token is one captured frame and the forge
	# preview is a still; neither has motion for a spring to answer.
	sim.active = false
	_spring = sim


func _find_anim(n: Node) -> AnimationPlayer:
	if n == null:
		return null
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null


## Wear a part. Two shapes, one entry point, because the caller should not have
## to know how a rig happens to package its clothes:
##   `parts`  the mesh is already inside the body scene → unhide it (kaykit)
##   `scenes` the garment is its own file → instance and skin it (quaternius)
## "" bares the slot either way.
func equip(slot: String, part_id: String) -> bool:
	var prof := profile()
	var table: Dictionary = prof.get("parts", {}).get(slot, {})
	var files: Dictionary = prof.get("scenes", {}).get(slot, {})
	var prev := str(_worn.get(slot, ""))
	if prev != "" and table.has(prev):
		var old := _find_mesh(_body, str(table[prev]))
		if old != null:
			old.visible = false
	unequip_scene(slot)
	if part_id == "":
		_worn[slot] = ""
		_refresh_zones()
		return true
	var props: Dictionary = prof.get("props", {}).get(slot, {})
	if props.has(part_id):
		if not _hold_prop(slot, str(props[part_id]), part_id):
			return false
		_worn[slot] = part_id
		_refresh_zones()
		return true
	if files.has(part_id):
		# A garment carries its own copy of the skeleton; it is worn by borrowing
		# THIS doll's pose, so one animation drives body and clothing together.
		# A value is either a `{S}` template or, where the pack's own names
		# diverge by sex, an explicit {male:…, female:…} pair.
		var entry = files[part_id]
		var path := _sexed(str(entry.get(sex, entry.get("male", ""))) if entry is Dictionary else str(entry))
		if not ResourceLoader.exists(path):
			return false
		if not _wear_file(slot, load(path)):
			return false
		# Remembered because the hidden-surface mask is named after the garment
		# FILE, and by the time the body mask is rebuilt the scene is long gone.
		# A slot plus a part id does not identify the file — the sex token lives
		# in the path.
		_worn_file[slot] = path
		_worn[slot] = part_id
		_refresh_zones()
		return true
	if not table.has(part_id):
		return false
	var m := _find_mesh(_body, str(table[part_id]))
	if m == null:
		return false
	m.visible = true
	_worn[slot] = part_id
	_refresh_zones()
	return true


## Put a RIGID prop in the hand. No skinning: it hangs off one bone through a
## BoneAttachment3D and inherits that bone's motion for free, which is why a
## weapon pack built for no particular skeleton works here at all.
##
## An OBJ loads as a bare Mesh — no scene, no material, no rig — so it is wrapped
## in a MeshInstance3D here. The fit (scale, rotation, offset) comes from the
## rig profile because it is a property of THIS pack meeting THIS rig, not of
## either alone.
func _hold_prop(slot: String, path: String, part_id := "") -> bool:
	if not ResourceLoader.exists(path):
		return false
	var res = load(path)
	var mesh: Mesh = res if res is Mesh else null
	if mesh == null and res is PackedScene:
		var tmp = res.instantiate()
		for mi in _all_meshes(tmp):
			mesh = mi.mesh
			break
		tmp.queue_free()
	if mesh == null:
		return false
	var bone := str(profile().get("sockets", {}).get(slot, ""))
	var att := _socket(bone)
	if att == null:
		return false
	var held := MeshInstance3D.new()
	held.mesh = mesh
	var fit: Dictionary = profile().get("prop_fit", {}).get(slot, {})
	# Scale DERIVED from the mesh, not asserted: measure its longest axis and
	# shrink it to the target length. A pack's authored units are arbitrary, so
	# a hard factor is a guess that happens to work for one pack — this one held
	# a sword three times the height of the man carrying it.
	var box := mesh.get_aabb()
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	# The weapon's own length if it has one, else the slot's default.
	var want := float(profile().get("prop_len", {}).get(part_id, fit.get("len", 0.8)))
	held.scale = Vector3.ONE * (want / maxf(longest, 0.0001))
	held.rotation_degrees = fit.get("rot", Vector3.ZERO)
	held.position = fit.get("pos", Vector3.ZERO)
	var holder := Node3D.new()
	holder.name = "held_" + slot
	att.add_child(holder)
	holder.add_child(held)
	_extern[slot] = holder
	return true


## Instance a garment scene and re-point its meshes at this doll's skeleton.
func _wear_file(slot: String, scene: PackedScene, dye := true) -> bool:
	if skeleton == null or scene == null:
		return false
	var inst := scene.instantiate()
	# Its own Skeleton3D comes along in the scene and must NOT drive anything —
	# the meshes are re-parented under ours so there is exactly one pose in play.
	var meshes := _all_meshes(inst)
	if meshes.is_empty():
		inst.queue_free()
		return false
	var holder := Node3D.new()
	holder.name = "worn_" + slot
	skeleton.add_child(holder)
	for mi in meshes:
		mi.get_parent().remove_child(mi)
		mi.owner = null   # else it still belongs to the scene we are about to free
		holder.add_child(mi)
		mi.skeleton = mi.get_path_to(skeleton)
	inst.queue_free()
	_extern[slot] = holder
	# Hair is not cut from the world's cloth. Pouring denim over it turns a
	# hero's head into a hat.
	if dye:
		_dye(holder)
	return true


## Wear a garment from its OWN file — the case every sourced or generated piece
## falls into. A rigid piece rides a bone; a fitted one is re-pointed at this
## doll's skeleton so one animation drives body and clothing together.
func equip_scene(slot: String, scene: PackedScene, fitted := false) -> bool:
	unequip_scene(slot)
	if scene == null:
		return false
	var inst := scene.instantiate()
	if fitted:
		if skeleton == null:
			inst.queue_free()
			return false
		skeleton.add_child(inst)
		# THE WHOLE TRICK: the garment keeps its own vertices and skin, and
		# borrows this skeleton's pose. Nothing is merged, nothing is copied.
		for mi in _all_meshes(inst):
			mi.skeleton = mi.get_path_to(skeleton)
	else:
		var bone := str(profile().get("sockets", {}).get(slot, ""))
		var att := _socket(bone)
		if att == null:
			inst.queue_free()
			return false
		att.add_child(inst)
	_extern[slot] = inst
	# Same reason as in equip(): the hidden-surface mask is named after the
	# garment file. This path is how every SOURCED or FORGED piece is worn, so
	# without it exactly the new garments — the ones with no fallback — would
	# hide no skin, and they were still tearing while the pack's own were clean.
	if scene.resource_path != "":
		_worn_file[slot] = scene.resource_path
	_worn[slot] = "scene"
	_refresh_zones()
	return true


## Off-tree NOW, then freed. `queue_free` alone defers to the end of the frame,
## so a swapped shirt is still hanging on the doll for the rest of it — two
## garments in one slot, briefly, and a re-query in the same frame counts both.
## `character_screen._refill_gear` carries this same note about the same trap.
func unequip_scene(slot: String) -> void:
	if _extern.has(slot) and is_instance_valid(_extern[slot]):
		var old: Node = _extern[slot]
		if old.get_parent() != null:
			old.get_parent().remove_child(old)
		old.queue_free()
	_extern.erase(slot)
	# Or the skin stays hidden under a garment that is no longer there.
	_worn_file.erase(slot)
	if str(_worn.get(slot, "")) == "scene":
		_worn[slot] = ""


func worn(slot: String) -> String:
	return str(_worn.get(slot, ""))


## A zone is visible unless SOMETHING worn covers it. Recomputed from the whole
## loadout every time rather than toggled per change: an incremental version
## leaves a leg hidden when the boots come off but the leggings stay, and that
## bug is invisible until a player undresses in an order nobody tested.
func _refresh_zones() -> void:
	var hides: Dictionary = profile().get("hides", {})
	var covered := {}
	for slot in _worn:
		if str(_worn[slot]) == "":
			continue
		for z in hides.get(slot, []):
			covered[str(z)] = true
	for zone in _zone_meshes:
		for mi in _zone_meshes[zone]:
			if is_instance_valid(mi):
				mi.visible = not covered.has(zone)
	# A HOOD EATS THE HAIR. There is no mask for this and there does not need to
	# be one: hair is its own mesh, so hiding it is a boolean, and long hair
	# through a hood is the one poke-through nobody would forgive.
	#
	# The beard stays. A hood does not cover a chin, and the pack's does not.
	if _extern.has("hair") and is_instance_valid(_extern["hair"]):
		_extern["hair"].visible = str(_worn.get("head", "")) == ""
	_refresh_body_mask()


## Hide the skin every worn garment covers — HIDDEN SURFACE REMOVAL, the thing
## production modular-character systems actually do. See
## scripts/bake_body_masks.py for the technique and why pushing the cloth out
## instead can never survive a pose change.
##
## Rebuilt from the WHOLE loadout, for the same reason the zones above are: an
## incremental version leaves a leg hidden when the leggings come off but the
## boots stay, and that is invisible until someone undresses in an order nobody
## tested.
func _refresh_body_mask() -> void:
	var want := str(profile().get("skin_mat", ""))
	if want == "" or _body == null:
		return
	var union: Image = null
	for slot in _worn_file:
		if str(_worn[slot] if _worn.has(slot) else "") == "":
			continue
		var mask := _mask_for(str(_worn_file[slot]))
		if mask == null:
			continue
		if union == null:
			union = mask.duplicate()
		else:
			_max_into(union, mask)
	_apply_body_mask(want, union)


## The baked mask for a garment file, or null where none was baked. Missing is
## not an error at runtime — a garment with no mask simply hides no skin, which
## is the pre-mask behaviour. self_check is where a missing mask must fail.
func _mask_for(garment_path: String) -> Image:
	var stem := garment_path.get_file().get_basename()
	var p := MASK_DIR + stem + "_mask.png"
	if not ResourceLoader.exists(p):
		return null
	var tex = load(p)
	return tex.get_image() if tex is Texture2D else null


## Pixel-wise max, because blend_rect on an opaque image just overwrites.
func _max_into(dst: Image, src: Image) -> void:
	var size := dst.get_size()
	for y in size.y:
		for x in size.x:
			if src.get_pixel(x, y).r > dst.get_pixel(x, y).r:
				dst.set_pixel(x, y, src.get_pixel(x, y))


func _apply_body_mask(want: String, union: Image) -> void:
	for mi in _all_meshes(_body):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src = mi.mesh.surface_get_material(i)
			if not (src is StandardMaterial3D) or not src.resource_name.contains(want):
				continue
			# ALWAYS the shader, even bare. It used to fall back to the pack's
			# own material whenever nothing was worn, which meant the skin tone
			# only reached a DRESSED hero — and it meant the surface changed
			# under you the moment you took a shirt off.
			var sm := ShaderMaterial.new()
			sm.shader = load(BODY_MASK_SHADER)
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			# CARRIED THROUGH, not dropped. The pack's skin ships both of these
			# and the material references them; the old shader sampled albedo
			# alone, so putting on a shirt turned a hero's skin to plastic.
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("has_normal", src.normal_texture != null)
			sm.set_shader_parameter("normal_depth", src.normal_scale if src.normal_enabled else 0.0)
			sm.set_shader_parameter("rough_tex", src.roughness_texture)
			sm.set_shader_parameter("has_rough", src.roughness_texture != null)
			sm.set_shader_parameter("rough_flat", src.roughness)
			sm.set_shader_parameter("tint", skin_tint)
			sm.set_shader_parameter("cover_mask",
				ImageTexture.create_from_image(union) if union != null else _no_mask())
			mi.set_surface_override_material(i, sm)


## A 1x1 black texture: "nothing is covered". Cached, because a bare doll would
## otherwise build one per mesh per re-dress.
static var _blank: ImageTexture = null


static func _no_mask() -> ImageTexture:
	if _blank == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.fill(Color.BLACK)
		_blank = ImageTexture.create_from_image(img)
	return _blank


## Which body zones are currently hidden — the doll's own answer, for checks.
func hidden_zones() -> Array:
	var out: Array[String] = []
	for zone in _zone_meshes:
		var vis := true
		for mi in _zone_meshes[zone]:
			if is_instance_valid(mi):
				vis = mi.visible
		if not vis:
			out.append(str(zone))
	out.sort()
	return out


## The world's cloth, poured over GARMENTS ONLY.
##
## The outfit pack is fantasy: two archetypes in leather and homespun. Four
## world families have no wardrobe at all — cyber, everyday, space, steam — and
## a material cannot turn a tunic into a jacket, but it can stop a cyberpunk
## hero being dressed in a peasant's brown wool. The cut stays fantasy; the
## substance becomes the world's. An honest half-measure, and the alternative is
## four wardrobes that do not exist.
##
## The other four families are absent from this table ON PURPOSE. Fantasy,
## pirate, horror and norse are exactly what the pack was authored for, and
## pouring a material over a good texture only costs the detail painted into it.
const CLOTH := {
	"cyber": "res://assets3d/cloth/cyber-cloth.png",
	"everyday": "res://assets3d/cloth/everyday-cloth.png",
	"space": "res://assets3d/cloth/space-cloth.png",
	"steam": "res://assets3d/cloth/steam-cloth.png",
}
const CLOTH_SHADER := "res://assets3d/cloth/world_cloth.gdshader"

const BODY_MASK_SHADER := "res://assets3d/cloth/body_mask.gdshader"
## Where bake_body_masks.py writes, and the naming it uses.
const MASK_DIR := "res://assets3d/masks/"

## Garments used to be pushed out along their normals to clear the body. That is
## gone: hidden-surface removal deletes the skin underneath instead, so there is
## nothing left to clear, and swelling every garment only made the silhouette
## puffy. See _refresh_body_mask and scripts/bake_body_masks.py.

## Object-space tiling repeats. A var, not a const, because the only way to pick
## it is to render a sweep and look — tests/doll_shot.gd does exactly that. The
## material spike's 0.25 was tuned against a different mesh at a different scale
## and on this body it puts one thigh-sized blotch per limb.
##
## 2.5 was chosen off that sweep: the weave still reads as weave, and the belts,
## straps and boot tops stay legible. 9.0 looks finer standing still and is the
## wrong answer — the figurine renders at 256 px, where that grain aliases into
## mush.
var cloth_scale := 2.5

## World skin FAMILY, not world id, so a FORGED world is dressed too — it
## resolves to a family long before it reaches here. Left empty the doll asks
## the live skin, which is what every caller in the game wants; a harness sets
## it directly to render a family it is not currently playing.
var family := ""


func _cloth_family() -> String:
	if family != "":
		return family
	# `Ui` is skin.gd's autoload name, not `Skin` — which resolves to something
	# else entirely and fails at PARSE time, taking the whole harness down with a
	# hang rather than an error.
	return WorldSkin.family_for_id(str(Ui.world_id))


## The poured texture for the active family, or null where the pack's own
## clothes are already right. Godot caches `load`, so this is a dictionary
## lookup after the first call.
func cloth_tex() -> Texture2D:
	var path := str(CLOTH.get(_cloth_family(), ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var t = load(path)
	return t if t is Texture2D else null


## Dye one worn garment. Called from _wear_file so nothing else has to remember
## to — one place to forget instead of nine, and a hero half in denim and half
## in homespun only shows up on the slot nobody happened to re-equip.
##
## Props are NOT dyed: a sword is not made of the same stuff as a shirt, and
## `_hold_prop` builds its own holder for exactly that reason.
func _dye(holder: Node) -> void:
	var tex := cloth_tex()
	var sh = load(CLOTH_SHADER)
	for mi in _all_meshes(holder):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src = mi.mesh.surface_get_material(i)
			if tex == null or not (sh is Shader):
				# Undyed: the pack's own material is already right.
				continue
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("cloth", tex)
			# The garment's own albedo carries every strap, lace and seam; the
			# shader keeps its luminance and replaces only the hue. Without it
			# the piece flattens into one untailored silhouette.
			if src is StandardMaterial3D and src.albedo_texture != null:
				sm.set_shader_parameter("garment", src.albedo_texture)
			sm.set_shader_parameter("tri_scale", cloth_scale)
			mi.set_surface_override_material(i, sm)


## Pull a camera back until the whole figurine is in shot.
##
## Lives here rather than in a view because BOTH views need it and they must not
## drift: the Gear page frames it loosely at 230x336, the board token frames it
## tight and square. A second copy of this is how one of them silently starts
## cropping an arm off after a rig swap.
##
## Uses the union of every VISIBLE mesh's AABB. Bone positions alone sit inside
## the silhouette and miss a held sword entirely — the token spike had that exact
## bug, and it is invisible until someone equips a greatsword.
func frame_camera(cam: Camera3D, aspect := 1.0, margin := 0.54) -> void:
	var box := AABB()
	var first := true
	for mi in _all_meshes(self):
		if not mi.visible:
			continue
		var world: AABB = mi.global_transform * mi.get_aabb()
		if first:
			box = world
			first = false
		else:
			box = box.merge(world)
	if first:
		cam.position = Vector3(0, 0.9, 3.2)
		cam.look_at(Vector3(0, 0.85, 0), Vector3.UP)
		return
	var mid := box.get_center()
	# Frame on HEIGHT, letting width only push it further back. A chibi body is
	# wider than it is tall with the arms out, so framing on the largest axis
	# alone left the figure small in a tall box with dead air above it.
	var wide: float = maxf(box.size.x, box.size.z)
	var reach: float = maxf(box.size.y, wide * aspect)
	var back: float = (reach * margin) / tan(deg_to_rad(cam.fov) * 0.5) + wide * 0.5
	cam.position = Vector3(mid.x, mid.y, mid.z + back)
	cam.look_at(mid, Vector3.UP)


func _socket(bone_name: String) -> BoneAttachment3D:
	if skeleton == null or bone_name == "":
		return null
	for c in skeleton.get_children():
		if c is BoneAttachment3D and c.bone_name == bone_name:
			return c
	var att := BoneAttachment3D.new()
	att.name = "socket_" + bone_name
	skeleton.add_child(att)
	att.bone_name = bone_name    # set AFTER add_child, or it resolves against nothing
	return att


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skeleton(c)
		if f != null:
			return f
	return null


func _find_mesh(n: Node, nm: String) -> MeshInstance3D:
	if n == null:
		return null
	if n is MeshInstance3D and n.name == nm:
		return n
	for c in n.get_children():
		var f := _find_mesh(c, nm)
		if f != null:
			return f
	return null


func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out
