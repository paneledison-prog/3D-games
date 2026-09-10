extends Resource
class_name CharacterProfile
## One playable body. Describes where the Mixamo model lives and how to fit it
## onto the 1.8m collider the gameplay code assumes.
##
## A profile whose model file is absent still works: the rig falls back to the
## placeholder capsule, so the roster is always selectable.

@export_group("Identity")
@export var id: String = "character"
@export var display_name: String = "Character"
@export var description: String = ""
## Tints the placeholder capsule and the menu entry.
@export var accent_color: Color = Color(0.35, 0.95, 0.75)

@export_group("Model")
## res:// path to the imported Mixamo character ("With Skin" download).
## Leave empty to always use the placeholder.
@export var model_path: String = ""
## Mixamo exports vary between centimetre and metre scale depending on the
## importer. Auto-fit sidesteps the guesswork entirely.
@export var auto_fit_height: bool = true
@export var target_height: float = 1.8
## Used only when auto_fit_height is false.
@export var model_scale: float = 1.0
@export var model_offset: Vector3 = Vector3.ZERO
## Mixamo characters face +Z; the controllers treat -Z as forward.
@export var model_rotation_y: float = 180.0

@export_group("Skeleton")
## Weapon attachment bone. Matched by suffix, so "RightHand" also finds
## "mixamorig:RightHand".
@export var right_hand_bone: String = "RightHand"
@export var head_bone: String = "Head"

@export_group("Weapon hold")
## Fine-tuning for how the gun sits in the hand, applied on top of the
## per-weapon offsets in WeaponData.
@export var grip_offset: Vector3 = Vector3.ZERO
@export var grip_rotation: Vector3 = Vector3.ZERO


## Formats Godot can import, in the order we prefer them.
const MODEL_EXTS := ["glb", "gltf", "fbx", "dae", "blend"]


## Resolve the model file, tolerating whatever format it was exported in. A
## Mixamo FBX and a converted GLB of the same character both resolve, so the
## profile does not have to be edited to match the download.
func resolve_model_path() -> String:
	if model_path.is_empty():
		return ""
	if ResourceLoader.exists(model_path):
		return model_path
	var base := model_path.get_basename()
	for ext in MODEL_EXTS:
		var candidate := "%s.%s" % [base, ext]
		if ResourceLoader.exists(candidate):
			return candidate
	return ""


func has_model() -> bool:
	return not resolve_model_path().is_empty()
