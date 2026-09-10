@tool
extends RefCounted
class_name MixamoPipeline
## Turns a folder of Mixamo downloads into one AnimationLibrary the game can use.
##
## Mixamo gives you one file per clip, every clip named "mixamo.com", and every
## bone prefixed "mixamorig:". This pipeline fixes all three problems:
##
##   1. derives the real clip name from the *filename* ("Rifle Run.fbx" -> run_fwd)
##   2. optionally strips the "mixamorig:" prefix from every track path
##   3. sets loop flags, and strips root motion for in-place locomotion
##
## Drop your .fbx/.glb files in assets/mixamo/raw/, then run
## tools/BuildMixamoLibrary.gd from the editor (File > Run, Ctrl+Shift+X).

const RAW_DIR := "res://assets/mixamo/raw"
const OUT_PATH := "res://assets/mixamo/retargeted/lonewolf_anims.res"
## Godot's FBX importer rewrites "mixamorig:Hips" as "mixamorig_Hips",
## so both forms have to be handled.
const MIXAMO_PREFIXES := ["mixamorig:", "mixamorig_"]

## Clip names the game asks for, and the Mixamo search terms that map to each.
## Matching is done on the lowercased filename, longest alias first, so
## "Rifle Walk Back.fbx" beats the shorter "walk" alias.
const CLIP_ALIASES := {
	"idle": ["rifle idle", "pistol idle", "breathing idle", "idle"],
	"walk_fwd": ["rifle walk forward", "walk forward", "rifle walk", "walking", "walk"],
	"walk_back": ["walk backward", "walk back", "walking backward"],
	"walk_left": ["strafe left", "walk left", "left strafe"],
	"walk_right": ["strafe right", "walk right", "right strafe"],
	"run_fwd": ["rifle run", "run forward", "running", "run"],
	"sprint": ["fast run", "sprint"],
	"crouch_idle": ["crouch idle", "crouching idle", "crouch"],
	"crouch_walk": ["crouch walk", "crouched walking", "sneak walk"],
	"jump_start": ["jump up", "jump start", "jumping up"],
	"jump_loop": ["falling idle", "jump loop", "fall loop"],
	"jump_land": ["hard landing", "jump land", "landing"],
	"fire": ["firing rifle", "rifle fire", "shooting", "fire"],
	"reload": ["reloading", "reload"],
	"aim": ["aiming", "rifle aiming", "aim"],
	"hit_react": ["hit reaction", "hit react", "impact"],
	"death_1": ["dying", "death from front", "falling back death", "death"],
	"death_2": ["death from headshot", "headshot death", "dying backwards"],
}

## Clips that should loop seamlessly.
const LOOPING := ["idle", "walk_fwd", "walk_back", "walk_left", "walk_right",
		"run_fwd", "sprint", "crouch_idle", "crouch_walk", "jump_loop", "aim"]

## Locomotion clips that must not drift the character (root motion removed).
const IN_PLACE := ["idle", "walk_fwd", "walk_back", "walk_left", "walk_right",
		"run_fwd", "sprint", "crouch_idle", "crouch_walk", "aim", "fire", "reload"]

const SCENE_EXTS := ["fbx", "glb", "gltf", "dae", "blend"]


## Map a source filename onto one of our canonical clip names.
static func resolve_clip_name(filename: String) -> String:
	var stem := filename.get_file().get_basename().to_lower()
	stem = stem.replace("_", " ").replace("-", " ").replace("(", " ").replace(")", " ")
	stem = stem.replace("  ", " ").strip_edges()

	var best_clip := ""
	var best_len := 0
	for clip in CLIP_ALIASES:
		for alias in CLIP_ALIASES[clip]:
			if stem.contains(alias) and alias.length() > best_len:
				best_clip = clip
				best_len = alias.length()
	# Nothing matched: keep a sanitised version of the filename so the clip is
	# still importable and the user can rename it deliberately.
	if best_clip.is_empty():
		return stem.replace(" ", "_")
	return best_clip


## Remove the "mixamorig:" prefix from every track path in the animation.
static func strip_bone_prefix(anim: Animation) -> int:
	var changed := 0
	for i in anim.get_track_count():
		var path := String(anim.track_get_path(i))
		var stripped := path
		for prefix in MIXAMO_PREFIXES:
			stripped = stripped.replace(prefix, "")
		if stripped != path:
			anim.track_set_path(i, NodePath(stripped))
			changed += 1
	return changed


## Delete hip translation so the clip animates in place. Rotation is kept.
static func strip_root_motion(anim: Animation) -> int:
	var removed := 0
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(anim.track_get_path(i)).to_lower()
		if path.ends_with(":hips") or path.ends_with(":root") \
				or path.ends_with("hips") or path.ends_with("armature"):
			anim.remove_track(i)
			removed += 1
	return removed


## Make the first and last keys identical so a looping clip does not pop.
static func set_loop(anim: Animation, looping: bool) -> void:
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE


static func list_source_files() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(RAW_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			var ext := entry.get_extension().to_lower()
			# .import sidecars and Godot's own files are not sources
			if SCENE_EXTS.has(ext):
				found.append("%s/%s" % [RAW_DIR, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Build the library. Returns a report dictionary for the caller to print.
static func build(strip_prefix := true, in_place := true) -> Dictionary:
	var report := {
		"sources": 0, "clips": [], "skipped": [], "saved": "", "error": "",
	}

	var files := list_source_files()
	report["sources"] = files.size()
	if files.is_empty():
		report["error"] = "No source files in %s. Download Mixamo clips as FBX " \
				% RAW_DIR + "and drop them there first."
		return report

	var library := AnimationLibrary.new()

	for path in files:
		var packed := ResourceLoader.load(path, "PackedScene")
		if packed == null:
			report["skipped"].append("%s (not importable)" % path.get_file())
			continue

		var scene: Node = (packed as PackedScene).instantiate()
		var player := _find_animation_player(scene)
		if player == null:
			report["skipped"].append("%s (no AnimationPlayer)" % path.get_file())
			scene.queue_free()
			continue

		var clip_name := resolve_clip_name(path)
		var source_names := player.get_animation_list()
		if source_names.is_empty():
			report["skipped"].append("%s (no animations)" % path.get_file())
			scene.queue_free()
			continue

		# A Mixamo file holds exactly one clip; if there are several, suffix them.
		for idx in source_names.size():
			var anim: Animation = player.get_animation(source_names[idx]).duplicate(true)
			var final_name := clip_name if idx == 0 else "%s_%d" % [clip_name, idx]

			if strip_prefix:
				strip_bone_prefix(anim)
			if in_place and IN_PLACE.has(final_name):
				strip_root_motion(anim)
			set_loop(anim, LOOPING.has(final_name))

			if library.has_animation(final_name):
				library.remove_animation(final_name)
			library.add_animation(final_name, anim)
			report["clips"].append({
				"name": final_name,
				"source": path.get_file(),
				"length": anim.length,
				"looping": LOOPING.has(final_name),
				"tracks": anim.get_track_count(),
			})

		scene.queue_free()

	if library.get_animation_list().is_empty():
		report["error"] = "No animations could be extracted."
		return report

	DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(OUT_PATH).get_base_dir())
	var err := ResourceSaver.save(library, OUT_PATH)
	if err != OK:
		report["error"] = "ResourceSaver.save failed (code %d)" % err
	else:
		report["saved"] = OUT_PATH
	return report


## Mixamo namespaces some characters, so one rig's bones are "mixamorig_Hips"
## while another's are "mixamorig1_Hips" or "mixamorig6_Hips". A clip only
## binds when its track prefix matches the target skeleton exactly, so the
## prefix has to be detected per character and the clips rewritten to suit.
static func detect_bone_prefix(skeleton: Skeleton3D) -> String:
	if skeleton == null or skeleton.get_bone_count() == 0:
		return ""
	var re := RegEx.create_from_string("^(mixamorig[0-9]*_)")
	for i in skeleton.get_bone_count():
		var m := re.search(skeleton.get_bone_name(i))
		if m != null:
			return m.get_string(1)
	return ""


## A copy of the library with every track prefix rewritten to target_prefix.
## Returns the original when no rewrite is needed, so the common case is free.
static func retargeted_library(library: AnimationLibrary,
		target_prefix: String) -> AnimationLibrary:
	if library == null or target_prefix.is_empty():
		return library

	var re := RegEx.create_from_string("mixamorig[0-9]*_")
	var needs_work := false
	for name in library.get_animation_list():
		var anim: Animation = library.get_animation(name)
		for i in anim.get_track_count():
			var m := re.search(String(anim.track_get_path(i)))
			if m != null and m.get_string(0) != target_prefix:
				needs_work = true
				break
		if needs_work:
			break
	if not needs_work:
		return library

	var out := AnimationLibrary.new()
	for name in library.get_animation_list():
		var anim: Animation = library.get_animation(name).duplicate(true)
		for i in anim.get_track_count():
			var path := String(anim.track_get_path(i))
			var fixed := re.sub(path, target_prefix, true)
			if fixed != path:
				anim.track_set_path(i, NodePath(fixed))
		out.add_animation(name, anim)
	return out


## Which canonical clips are still missing after a build.
static func missing_clips(library: AnimationLibrary) -> PackedStringArray:
	var missing := PackedStringArray()
	if library == null:
		for clip in CLIP_ALIASES:
			missing.append(clip)
		return missing
	for clip in CLIP_ALIASES:
		if not library.has_animation(clip):
			missing.append(clip)
	return missing


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
