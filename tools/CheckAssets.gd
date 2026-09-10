@tool
extends EditorScript
## Reports which characters, weapon models and animation clips are actually
## present, and inspects each imported character's skeleton.
##
## HOW TO RUN: open this file in the script editor and press Ctrl+Shift+X.
##
## Run it after dropping downloads in, to confirm Godot imported them and the
## bone names match what CharacterRig expects.

func _run() -> void:
	print("")
	print("=== Lone Wolf :: asset check ===")
	_check_characters()
	_check_weapons()
	_check_animations()
	print("")
	print("Anything marked MISSING falls back to a placeholder - the game still")
	print("runs. See docs/ASSET_GUIDE.md for where each file comes from.")


func _check_characters() -> void:
	print("")
	print("-- Characters ------------------------------------------------")
	var profiles := CharacterRig.all_profiles()
	if profiles.is_empty():
		print("  no profiles in res://resources/characters/")
		return

	for p in profiles:
		var file := p.model_path.get_file()
		if not p.has_model():
			print("  [MISSING] %-16s expects %s" % [p.display_name, file])
			continue

		var packed: PackedScene = load(p.resolve_model_path())
		if packed == null:
			print("  [BAD]     %-16s %s failed to load" % [p.display_name, file])
			continue

		var scene: Node = packed.instantiate()
		var skel := _find(scene, Skeleton3D) as Skeleton3D
		var anim := _find(scene, AnimationPlayer) as AnimationPlayer
		var meshes: Array[MeshInstance3D] = []
		_meshes(scene, meshes)

		if skel == null:
			print("  [BAD]     %-16s no Skeleton3D - re-download 'With Skin'"
					% p.display_name)
			scene.queue_free()
			continue

		var hand := CharacterRig.find_bone(skel, p.right_hand_bone)
		var head := CharacterRig.find_bone(skel, p.head_bone)
		var height := _height(scene)

		print("  [OK]      %-16s %d bones, %d meshes, %.2fm tall"
				% [p.display_name, skel.get_bone_count(), meshes.size(), height])
		print("            hand bone : %s" % (
				skel.get_bone_name(hand) if hand >= 0
				else "NOT FOUND (looked for '%s')" % p.right_hand_bone))
		print("            head bone : %s" % (
				skel.get_bone_name(head) if head >= 0
				else "NOT FOUND (looked for '%s')" % p.head_bone))
		if p.auto_fit_height and height > 0.001:
			print("            auto-fit  : x%.3f -> %.2fm"
					% [p.target_height / height, p.target_height])
		if anim == null:
			print("            note      : no AnimationPlayer (clips come from "
					+ "the shared Mixamo library, which is fine)")
		scene.queue_free()


func _check_weapons() -> void:
	print("")
	print("-- Weapon models ---------------------------------------------")
	var dir := DirAccess.open("res://resources/weapons")
	if dir == null:
		print("  no weapon resources")
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		var clean := file.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var w: Resource = load("res://resources/weapons/%s" % clean)
		if not (w is WeaponData):
			continue
		var data := w as WeaponData
		if data.model_path.is_empty():
			print("  [PLACEHOLDER] %-16s no model path set" % data.display_name)
		elif data.has_model():
			print("  [OK]          %-16s %s"
					% [data.display_name, data.resolve_model_path().get_file()])
		else:
			print("  [MISSING]     %-16s expects %s"
					% [data.display_name, data.model_path.get_file()])


func _check_animations() -> void:
	print("")
	print("-- Animation library -----------------------------------------")
	if not ResourceLoader.exists(MixamoPipeline.OUT_PATH):
		print("  [MISSING] no library yet - drop clips in assets/mixamo/raw/")
		print("            and run tools/BuildMixamoLibrary.gd")
		var raw := MixamoPipeline.list_source_files()
		if not raw.is_empty():
			print("            (%d source file(s) are waiting to be built)" % raw.size())
		return

	var lib: AnimationLibrary = load(MixamoPipeline.OUT_PATH)
	var clips := lib.get_animation_list()
	print("  [OK] %d clips in the library" % clips.size())
	var missing := MixamoPipeline.missing_clips(lib)
	if missing.is_empty():
		print("  every expected clip is present")
	else:
		print("  missing (fallbacks will substitute): %s" % ", ".join(missing))


func _height(root: Node) -> float:
	var meshes: Array[MeshInstance3D] = []
	_meshes(root, meshes)
	if meshes.is_empty():
		return 0.0
	var total := AABB()
	var first := true
	for mi in meshes:
		var box := mi.transform * mi.get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
	return total.size.y


func _meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_meshes(child, out)


func _find(node: Node, type) -> Node:
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var found := _find(child, type)
		if found != null:
			return found
	return null
