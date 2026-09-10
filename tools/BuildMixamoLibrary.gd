@tool
extends EditorScript
## Build the Mixamo AnimationLibrary.
##
## HOW TO RUN: open this file in the Godot script editor and press
## Ctrl+Shift+X (File > Run). Output goes to the Output panel.
##
## Input : assets/mixamo/raw/*.fbx (or .glb)
## Output: assets/mixamo/retargeted/lonewolf_anims.res

## Our characters are Mixamo rigs, so their bones keep the "mixamorig_"
## prefix and the clips must keep it too. Flip this on only if the target
## rig uses plain bone names.
const STRIP_BONE_PREFIX := false

## Remove hip translation from locomotion clips so the character does not slide
## away from its collision body. Turn OFF if you want true root motion.
const FORCE_IN_PLACE := true


func _run() -> void:
	print("")
	print("=== Lone Wolf :: Mixamo library build ===")

	var report := MixamoPipeline.build(STRIP_BONE_PREFIX, FORCE_IN_PLACE)

	print("source files found : %d" % report["sources"])

	if not report["error"].is_empty():
		printerr("BUILD FAILED: %s" % report["error"])
		_print_help()
		return

	var clips: Array = report["clips"]
	clips.sort_custom(func(a, b): return a["name"] < b["name"])
	print("clips extracted    : %d" % clips.size())
	print("")
	print("  %-14s %-28s %7s %7s %s" % ["CLIP", "SOURCE", "LENGTH", "TRACKS", "LOOP"])
	for c in clips:
		print("  %-14s %-28s %6.2fs %7d %s" % [
			c["name"], c["source"].left(28), c["length"], c["tracks"],
			"yes" if c["looping"] else "-"])

	var skipped: Array = report["skipped"]
	if not skipped.is_empty():
		print("")
		print("skipped:")
		for s in skipped:
			print("  - %s" % s)

	var lib: AnimationLibrary = load(report["saved"])
	var missing := MixamoPipeline.missing_clips(lib)
	if not missing.is_empty():
		print("")
		print("still missing (game will substitute fallbacks):")
		print("  %s" % ", ".join(missing))

	print("")
	print("saved -> %s" % report["saved"])
	print("Reload the project or re-enter play mode to pick up the new clips.")
	_print_help()


func _print_help() -> void:
	print("")
	print("--- Mixamo download settings that match this pipeline ---")
	print("  Format     : FBX Binary (.fbx)")
	print("  Skin       : 'With Skin' for the character, 'Without Skin' for clips")
	print("  Frames/sec : 30")
	print("  Keyframe   : uncheck 'Reduce Keyframes'")
	print("  In Place   : CHECK for walk/run/strafe/crouch clips")
	print("  Filenames  : keep Mixamo's names, e.g. 'Rifle Run.fbx' -> run_fwd")
	print("  See docs/MIXAMO_PIPELINE.md for the full clip list.")
