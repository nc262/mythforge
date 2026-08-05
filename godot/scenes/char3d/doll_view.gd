class_name DollView extends SubViewportContainer
## The figurine on the Gear page — your hero, wearing exactly what you equipped,
## the instant you equip it.
##
## The page used to show a GENERATED PAINTING of the body, which meant putting on
## a helmet was a request to the image engine and a wait. It is the right picture
## for a scene and the wrong one for a fitting room: the whole point of a paper
## doll is that it answers immediately.
##
## Rendered like a tabletop miniature on purpose. This game calls itself the
## table on every other surface — "the table keeps the tally", "leave the table"
## — so a figurine is not a compromise around fidelity, it is the object the
## fiction already says is there. It also sets the bar honestly: nobody asks a
## 28 mm mini to be photoreal, and the low-poly CC0 body reads as a deliberate
## sculpt at this size rather than as a cheap character.

const BODY := "res://spike3d/models/Knight.glb"

## A stance, not a T-pose. The bind pose is a mannequin on a rack; a miniature
## stands. Tried in name order because rigs disagree — KayKit says "Idle",
## Quaternius says "Idle_Loop" — and the first one present wins.
const IDLE_NAMES := ["Idle", "Idle_Loop", "1H_Melee_Idle", "2H_Melee_Idle",
	"Idle_A", "Unarmed_Idle"]

var doll: ModularDoll = null
var _vp: SubViewport = null
var _yaw := 0.0
var _pivot: Node3D = null
var _dragging := false
## What to wear once there is something to wear it. `wear()` is called by the
## Gear page the instant after `new()`, which is BEFORE `_ready` — so the doll
## does not exist yet and dressing it would silently do nothing. It did exactly
## that: the hero held a dagger and the figurine stood empty-handed.
var _pending: Dictionary = {}
var _built := false


func _init(view_size := Vector2(230, 336)) -> void:
	custom_minimum_size = view_size
	stretch = true
	# SHRINK_CENTER, or the HBox hands this more width than it asked for, the
	# viewport stretches to fill it, and the figurine centres in a box that is no
	# longer where the sockets expect it — which reads as "the doll is off to one
	# side" rather than as a layout bug, so it never gets diagnosed.
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Drag to turn your figurine"


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	# UPDATE_WHEN_VISIBLE, not ALWAYS. A viewport left rendering behind a hidden
	# tab is a GPU cost nobody can see — and on this machine the narrator and the
	# image engine are already fighting over one card.
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	doll = ModularDoll.new()
	_pivot.add_child(doll)
	if ResourceLoader.exists(BODY):
		doll.build(load(BODY))
		_stand()
	_built = true
	if not _pending.is_empty():
		doll.wear_inventory(_pending)
		_pending = {}

	# Three-quarter view: the pose a miniature is photographed in, and the one
	# that shows a shield and a weapon at once instead of hiding one behind the body.
	_yaw = deg_to_rad(-24.0)
	_pivot.rotation.y = _yaw

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 34, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -130, 0)
	fill.light_energy = 0.45
	_vp.add_child(fill)

	# Framed from the figure's own bounds rather than a guessed distance. The
	# first pass hard-coded 2.9 and cropped the arms off a chibi body — and a
	# rig swap would have broken it again, silently and differently.
	var cam := Camera3D.new()
	cam.fov = 34.0
	_vp.add_child(cam)
	if doll != null:
		doll.frame_camera(cam, custom_minimum_size.x / maxf(custom_minimum_size.y, 1.0))


## Show what the hero is actually wearing. Safe to call before the view is in
## the tree — the loadout is held and applied the moment the doll exists.
func wear(inv: Dictionary) -> void:
	if not _built or doll == null or not is_instance_valid(doll):
		_pending = inv.duplicate(true)
		return
	doll.wear_inventory(inv)


## Put the figurine on its feet, and freeze it there — a looping animation in a
## menu is a viewport that never stops redrawing, which is GPU the narrator wants.
func _stand() -> void:
	var ap := _find_anim(doll)
	if ap == null:
		return
	for lib in ap.get_animation_library_list():
		for nm in ap.get_animation_library(lib).get_animation_list():
			for want in IDLE_NAMES:
				if str(nm).nocasecmp_to(want) == 0:
					var full: String = (str(lib) + "/" + str(nm)) if str(lib) != "" else str(nm)
					ap.play(full)
					ap.advance(0.4)   # a step in, past any wind-up on frame zero
					ap.pause()
					return


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null


## Drag to turn. A figurine you can only see from the front hides half of what
## you just put on it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging and _pivot != null:
		_yaw -= event.relative.x * 0.012
		_pivot.rotation.y = _yaw
