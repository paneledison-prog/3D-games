extends SceneTree
## Headless entry point for the Mixamo library build.
##
## Same work as tools/BuildMixamoLibrary.gd, but runnable without opening the
## editor, so the animation library can be rebuilt from a script or CI:
##
##     godot --headless --path . --script tools/build_mixamo_headless.gd

## Our characters are Mixamo rigs, so their bones keep the "mixamorig_"
## prefix and the clips must keep it too. Flip this on only if the target
## rig uses plain bone names.
const STRIP_BONE_PREFIX := false
const FORCE_IN_PLACE := true


func _initialize() -> void:
	print("")
	print("=== Lone Wolf :: Mixamo library build (headless) ===")

	var report := MixamoPipeline.build(STRIP_BONE_PREFIX, FORCE_IN_PLACE)
	print("source files found : %d" % report["sources"])

	if not report["error"].is_empty():
		printerr("BUILD FAILED: %s" % report["error"])
		quit(1)
		return

	var clips: Array = report["clips"]
	clips.sort_custom(func(a, b): return a["name"] < b["name"])
	print("clips extracted    : %d" % clips.size())
	print("")
	print("  %-14s %-26s %8s %7s %s" % ["CLIP", "SOURCE", "LENGTH", "TRACKS", "LOOP"])
	for c in clips:
		print("  %-14s %-26s %7.2fs %7d %s" % [
			c["name"], String(c["source"]).left(26), c["length"], c["tracks"],
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
		print("not downloaded yet (fallbacks will substitute):")
		print("  %s" % ", ".join(missing))

	print("")
	print("saved -> %s" % report["saved"])
	quit(0)
