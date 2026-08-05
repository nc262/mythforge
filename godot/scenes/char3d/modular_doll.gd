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
## sleeve. The published answers are a vertex bitmask, an alpha mask on the body
## texture, or one mesh per body zone toggled off. We get the third for free —
## these bodies already arrive split into head/torso/arms/legs — so a garment
## simply declares which zones it hides and they are switched off. No shader, no
## mask textures, nothing to keep in sync.
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
	# And the body is ONE mesh, not a set of zones — so there is nothing to hide
	# under a sleeve. `hides` is empty on purpose: these garments are authored
	# for this exact body and enclose it. If poke-through ever shows, the fix is
	# an alpha mask on the body texture, NOT a fake zone split.
	"quaternius": {
		"body": "res://assets3d/bodies/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf",
		# The clips live in their OWN file on this rig, so they are attached at
		# build time. Track paths read `Armature/Skeleton3D:pelvis` and the body
		# has exactly that shape, so an AnimationPlayer rooted at the body root
		# resolves them with no retargeting at all — which is the dividend of
		# every pack sharing one skeleton.
		"anim": "res://assets3d/anim/UAL2_Standard.glb",
		# UAL2 is a SITUATIONAL library — farming, zombies, sword combos — with no
		# plain "Idle". Folded arms is the one unambiguous standing pose in it.
		"stand": ["Idle_FoldArms", "Idle_Rail", "Idle_No", "Idle_Shield"],
		"sockets": {"weapon": "hand_r", "offhand": "hand_l", "shield": "hand_l",
			"head": "Head", "cloak": "spine_03"},
		"zones": {},
		"hides": {},
		"parts": {},
		# NO WEAPONS OR SHIELDS. The outfit pack is clothing only, so `weapon`,
		# `offhand` and `shield` have sockets waiting on the right bones and no
		# geometry to hang on them — those slots resolve to "" and the figurine
		# goes unarmed. Weapons are RIGID props: they ride a BoneAttachment3D and
		# never need matching skin weights, so any CC0 weapon mesh can fill them
		# later without touching the rig. Tracked in the backlog, not pretended
		# away with a stand-in sword from the other rig at the wrong scale.
		"scenes": {
			"armor":  {"ranger": "res://assets3d/outfits/Modular Parts/Male_Ranger_Body.gltf",
				"peasant": "res://assets3d/outfits/Modular Parts/Male_Peasant_Body.gltf"},
			"hands":  {"ranger": "res://assets3d/outfits/Modular Parts/Male_Ranger_Arms.gltf",
				"peasant": "res://assets3d/outfits/Modular Parts/Male_Peasant_Arms.gltf"},
			"legs":   {"ranger": "res://assets3d/outfits/Modular Parts/Male_Ranger_Legs.gltf",
				"peasant": "res://assets3d/outfits/Modular Parts/Male_Peasant_Legs.gltf"},
			"feet":   {"ranger": "res://assets3d/outfits/Modular Parts/Male_Ranger_Feet_Boots.gltf",
				"peasant": "res://assets3d/outfits/Modular Parts/Male_Peasant_Feet.gltf"},
			"head":   {"hood": "res://assets3d/outfits/Modular Parts/Male_Ranger_Head_Hood.gltf"},
			"cloak":  {"pauldrons": "res://assets3d/outfits/Modular Parts/Male_Ranger_Acc_Pauldron.gltf"},
		},
		# UNDERCLOTHES. A hero with no leggings equipped is not naked, they are in
		# whatever they own — so an empty slot falls back to the peasant set
		# rather than to skin. Without this the figurine stands in its underwear
		# any time the player has not found trousers yet, which is most of act
		# one. `head` and `cloak` are absent on purpose: bare-headed and
		# cloakless are normal, bare-legged is not.
		"default": {"armor": "peasant", "hands": "peasant", "legs": "peasant", "feet": "peasant"},
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
	return prof.get("parts", {}).has(slot) or prof.get("scenes", {}).has(slot)

var rig := "quaternius"
var skeleton: Skeleton3D = null


## The body this rig dresses, so a caller does not have to know the path.
func body_path() -> String:
	return str(profile().get("body", "res://spike3d/models/Knight.glb"))

var _body: Node3D = null
var _zone_meshes := {}    # zone → Array[MeshInstance3D]
var _worn := {}           # slot → part id (or "" when bare)
var _extern := {}         # slot → the Node3D we instanced for an external part


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
	_extern.clear()
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
	stand()
	_refresh_zones()


## Borrow a shared animation library. Only needed where the clips ship apart from
## the body — the KayKit rig carries its own, so this is a no-op there.
func _attach_anim(prof: Dictionary) -> void:
	var path := str(prof.get("anim", ""))
	if path == "" or _body == null or not ResourceLoader.exists(path):
		return
	if _find_anim(_body) != null:
		return                       # the body already brought clips of its own
	var src = load(path).instantiate()
	var sap := _find_anim(src)
	if sap == null:
		src.queue_free()
		return
	var ap := AnimationPlayer.new()
	_body.add_child(ap)
	# Rooted at the body, because the clips' track paths are written relative to
	# the glTF root they came from and both files share that shape.
	ap.root_node = ap.get_path_to(_body)
	for lib in sap.get_animation_library_list():
		ap.add_animation_library(str(lib), sap.get_animation_library(lib))
	src.queue_free()


## Put the figurine on its feet and FREEZE it there. A looping animation in a
## menu is a viewport that never stops redrawing, which is GPU the narrator
## wants — and a miniature does not fidget.
func stand() -> void:
	var ap := _find_anim(_body)
	if ap == null:
		return
	var want: Array = profile().get("stand", ["Idle", "Idle_Loop", "1H_Melee_Idle"])
	for lib in ap.get_animation_library_list():
		for nm in ap.get_animation_library(lib).get_animation_list():
			for w in want:
				if str(nm).nocasecmp_to(str(w)) != 0:
					continue
				ap.play((str(lib) + "/" + str(nm)) if str(lib) != "" else str(nm))
				ap.advance(0.35)   # a step in, past any wind-up on frame zero
				ap.pause()
				return


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
	if files.has(part_id):
		# A garment carries its own copy of the skeleton; it is worn by borrowing
		# THIS doll's pose, so one animation drives body and clothing together.
		var path := str(files[part_id])
		if not ResourceLoader.exists(path):
			return false
		if not _wear_file(slot, load(path)):
			return false
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


## Instance a garment scene and re-point its meshes at this doll's skeleton.
func _wear_file(slot: String, scene: PackedScene) -> bool:
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


## The world's poured material, dropped on body and gear alike. Triplanar, so it
## ignores every mesh's own UV atlas — which is exactly what lets ONE material
## cover any garment from any source (see the material spike: pushing a tileable
## texture through a game mesh's atlas produced stretched garbage).
func apply_world_material(tex: Texture2D, shader: Shader, tri_scale := 0.25) -> void:
	if tex == null or shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("triplanar", true)
	mat.set_shader_parameter("tri_scale", tri_scale)
	for mi in _all_meshes(self):
		mi.material_override = mat


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
