extends Node3D
## Roster preview: builds every CharacterProfile through the real CharacterRig
## and plays a Mixamo clip on each, so the whole cast can be eyeballed without
## starting a match.
##
## Run with F6 in the editor, or:
##     godot --path . tools/RosterPreview.tscn -- --shot

const LIBRARY := "res://assets/mixamo/retargeted/lonewolf_anims.res"
const SPACING := 1.6
const SETTLE_FRAMES := 100

## One clip per character, seeked to a readable moment of the cycle.
const SHOWCASE := [
	["idle", 1.0],
	["walk_fwd", 0.35],
	["run_fwd", 0.30],
	["aim", 0.8],
	["reload", 1.2],
]

var _shot := false
var _frames := 0


func _ready() -> void:
	_shot = "--shot" in OS.get_cmdline_user_args()

	var profiles := CharacterRig.all_profiles()
	if profiles.is_empty():
		push_error("RosterPreview: no character profiles found.")
		return

	var lib: AnimationLibrary = null
	if ResourceLoader.exists(LIBRARY):
		lib = load(LIBRARY)

	var start := -(profiles.size() - 1) * 0.5 * SPACING
	for i in profiles.size():
		var profile := profiles[i]

		var holder := Node3D.new()
		holder.position = Vector3(start + i * SPACING, 0.0, 0.0)
		# Characters face -Z in game; turn them to face the camera.
		holder.rotation_degrees.y = 180.0
		add_child(holder)

		var rig := CharacterRig.new()
		rig.name = "Rig"
		rig.profile_id = profile.id
		rig.auto_build = false
		holder.add_child(rig)
		rig.build(profile.id)

		_label(holder, profile.display_name.to_upper(),
				"" if rig.has_model else "(stand-in)")

		var pair: Array = SHOWCASE[i % SHOWCASE.size()]
		_pose(rig, lib, String(pair[0]), float(pair[1]))

	if _shot:
		_capture()


func _pose(rig: CharacterRig, lib: AnimationLibrary, clip: String, at: float) -> void:
	if lib == null or rig.animation_player == null:
		return
	if not lib.has_animation(clip):
		clip = "idle"
		if not lib.has_animation(clip):
			return
	var player := rig.animation_player
	# Same per-character prefix fix the runtime animator applies.
	var fitted := MixamoPipeline.retargeted_library(
			lib, MixamoPipeline.detect_bone_prefix(rig.skeleton))
	if player.has_animation_library("mixamo"):
		player.remove_animation_library("mixamo")
	player.add_animation_library("mixamo", fitted)
	player.play("mixamo/%s" % clip)
	player.seek(at, true)


func _label(parent: Node3D, name_text: String, note: String) -> void:
	var label := Label3D.new()
	label.text = name_text if note.is_empty() else "%s\n%s" % [name_text, note]
	label.font_size = 80
	label.pixel_size = 0.0022
	label.position = Vector3(0.0, 2.05, 0.0)
	label.rotation_degrees.y = 180.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 1, 1, 0.9)
	parent.add_child(label)


func _capture() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://roster.png")
	print("roster capture: %s (%s)"
			% [path, "ok" if img.save_png(path) == OK else "failed"])
	get_tree().quit()
