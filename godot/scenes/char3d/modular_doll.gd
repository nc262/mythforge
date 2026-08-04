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
	},
}

var rig := "kaykit"
var skeleton: Skeleton3D = null

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
	_refresh_zones()


## Wear a part that already lives inside the body scene. "" bares the slot.
func equip(slot: String, part_id: String) -> bool:
	var prof := profile()
	var table: Dictionary = prof.get("parts", {}).get(slot, {})
	var prev := str(_worn.get(slot, ""))
	if prev != "" and table.has(prev):
		var old := _find_mesh(_body, str(table[prev]))
		if old != null:
			old.visible = false
	if part_id == "":
		_worn[slot] = ""
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


func unequip_scene(slot: String) -> void:
	if _extern.has(slot) and is_instance_valid(_extern[slot]):
		_extern[slot].queue_free()
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
