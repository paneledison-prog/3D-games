extends Node3D
## Character preview harness.
##
## Lines the articulated stand-in up in every pose it can hit, so proportions
## and bone rotations can be checked at a glance instead of by playing a match.
##
## Run it from the editor (F6 with tools/CharacterPreview.tscn open), or:
##     godot --path . tools/CharacterPreview.tscn
##
## Pass --shot to have it save preview.png and quit, which is how it gets
## checked without a human watching.

## label, speed_ratio, forward, strafe, crouch, airborne, aiming, dead
const POSES := [
	["IDLE", 0.0, 0.0, 0.0, false, false, false, false],
	["WALK", 0.55, 1.0, 0.0, false, false, false, false],
	["SPRINT", 1.0, 1.0, 0.0, false, false, false, false],
	["CROUCH", 0.0, 0.0, 0.0, true, false, false, false],
	["AIM", 0.0, 0.0, 0.0, false, false, true, false],
	["JUMP", 0.4, 1.0, 0.0, false, true, false, false],
	["DEAD", 0.0, 0.0, 0.0, false, false, false, true],
]

const ACCENTS := [
	Color(0.32, 0.62, 0.98), Color(0.98, 0.72, 0.20), Color(0.42, 0.92, 0.45),
	Color(0.68, 0.45, 0.98), Color(0.98, 0.38, 0.55), Color(0.35, 0.95, 0.75),
	Color(0.85, 0.45, 0.25),
]

const SPACING := 1.5
const SETTLE_FRAMES := 90

var _humanoids: Array[ProceduralHumanoid] = []
var _frames := 0
var _shot_mode := false


func _ready() -> void:
	_shot_mode = "--shot" in OS.get_cmdline_user_args() \
			or "--shot" in OS.get_cmdline_args()

	var start := -(POSES.size() - 1) * 0.5 * SPACING
	for i in POSES.size():
		var holder := Node3D.new()
		holder.position = Vector3(start + i * SPACING, 0.0, 0.0)
		# In game a character faces -Z; spin them to face the camera here.
		holder.rotation_degrees.y = 180.0
		add_child(holder)

		var h := ProceduralHumanoid.new()
		holder.add_child(h)
		h.build(ACCENTS[i % ACCENTS.size()])
		_humanoids.append(h)

		_add_label(holder, String(POSES[i][0]))

	# Put a rifle in one hand to check the grip lands somewhere believable.
	_give_weapon(_humanoids[4])
	_give_weapon(_humanoids[0])

	if _shot_mode:
		_capture()


## Let the pose blends settle, then save a frame and exit. Kept out of _process
## so the await chain runs exactly once.
func _capture() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://preview.png")
	var err := img.save_png(path)
	print("preview capture: %s (%s)" % [path, "ok" if err == OK else "error %d" % err])
	get_tree().quit()


func _add_label(parent: Node3D, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.0022
	label.position = Vector3(0.0, 2.05, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 1, 1, 0.85)
	parent.add_child(label)


func _give_weapon(h: ProceduralHumanoid) -> void:
	var bone := CharacterRig.find_bone(h.skeleton, "RightHand")
	if bone < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = h.skeleton.get_bone_name(bone)
	attach.bone_idx = bone
	h.skeleton.add_child(attach)

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.13, 0.66)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.11, 0.13)
	mat.metallic = 0.7
	mi.material_override = mat
	mi.rotation_degrees = ProceduralHumanoid.GRIP_CORRECTION
	attach.add_child(mi)


func _process(delta: float) -> void:
	for i in _humanoids.size():
		var p: Array = POSES[i]
		_humanoids[i].update_pose(delta, float(p[1]), float(p[2]), float(p[3]),
				bool(p[4]), bool(p[5]), bool(p[6]), bool(p[7]))

	_frames += 1
