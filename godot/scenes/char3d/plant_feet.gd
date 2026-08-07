class_name PlantFeet extends SkeletonModifier3D
## Play a travelling clip IN PLACE, so a sword combo does not walk the hero out
## of the Gear page.
##
## UAL2's clips are authored for a character that moves through a world: the
## three-hit combo steps into each swing and finishes in a deep lunge well
## forward of where it started. Rendered through the Gear page's actual 230x336
## frame that is not a subtlety — the figure ends up hard against the left edge
## with the blade cropped off the top.
##
## The travel lives on `pelvis`, not on `root` — measured, and it matters,
## because it rules out the obvious fix. `AnimationMixer.root_motion_track`
## would strip that track wholesale, and the pelvis track is not only travel: it
## carries the crouch, the weight drop and the bob. Removing it flattens the
## animation into a figure gliding about at a constant height.
##
## So only the HORIZONTAL component goes. X and Z return to the bind pose every
## frame; Y is left exactly as the animator wrote it. The whole body follows the
## pelvis, feet included, which is what "in place" means — the character still
## lunges, it just does not end up somewhere else.
##
## Runs BEFORE the spring simulation (earlier sibling), so the springs answer to
## the corrected pose rather than to a translation that is about to be undone.

## Which bone carries the travel. Data, like every other rig fact in this
## folder: another library could put it on `root` instead.
@export var bone := "pelvis"

var _idx := -1
var _rest := Vector3.ZERO


func _ready() -> void:
	_resolve()


## Re-resolve whenever the skeleton changes underneath us — a doll rebuilds its
## body on a sex swap, and an index into the old skeleton is worse than none.
func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_resolve()


func _resolve() -> void:
	_idx = -1
	var sk := get_skeleton()
	if sk == null:
		return
	_idx = sk.find_bone(bone)
	if _idx >= 0:
		_rest = sk.get_bone_rest(_idx).origin


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _idx < 0:
		return
	var p := sk.get_bone_pose_position(_idx)
	sk.set_bone_pose_position(_idx, Vector3(_rest.x, p.y, _rest.z))
