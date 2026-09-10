extends Node3D
class_name ProceduralHumanoid
## An articulated stand-in character, built in code.
##
## This exists so the game looks and animates like a shooter before any Mixamo
## download happens. It is not a capsule: it is a real Skeleton3D using Mixamo's
## own bone names, with body segments attached to those bones. That buys three
## things:
##
##   1. it reads as a person on screen right now
##   2. the weapon attaches to an actual RightHand bone, like the real rig
##   3. Mixamo clips drive it directly when they arrive - same bone names
##
## Drop a real Mixamo character in and CharacterRig uses that instead; this
## never gets in the way.

const TOTAL_HEIGHT := 1.8

## name, parent, rest offset from parent (metres)
const BONES := [
	["Hips", "", Vector3(0.0, 0.98, 0.0)],
	["Spine", "Hips", Vector3(0.0, 0.11, 0.0)],
	["Spine1", "Spine", Vector3(0.0, 0.12, 0.0)],
	["Spine2", "Spine1", Vector3(0.0, 0.13, 0.0)],
	["Neck", "Spine2", Vector3(0.0, 0.15, 0.0)],
	["Head", "Neck", Vector3(0.0, 0.07, 0.0)],

	["LeftShoulder", "Spine2", Vector3(0.045, 0.10, 0.0)],
	["LeftArm", "LeftShoulder", Vector3(0.13, 0.0, 0.0)],
	["LeftForeArm", "LeftArm", Vector3(0.27, 0.0, 0.0)],
	["LeftHand", "LeftForeArm", Vector3(0.25, 0.0, 0.0)],

	["RightShoulder", "Spine2", Vector3(-0.045, 0.10, 0.0)],
	["RightArm", "RightShoulder", Vector3(-0.13, 0.0, 0.0)],
	["RightForeArm", "RightArm", Vector3(-0.27, 0.0, 0.0)],
	["RightHand", "RightForeArm", Vector3(-0.25, 0.0, 0.0)],

	["LeftUpLeg", "Hips", Vector3(0.09, -0.05, 0.0)],
	["LeftLeg", "LeftUpLeg", Vector3(0.0, -0.44, 0.0)],
	["LeftFoot", "LeftLeg", Vector3(0.0, -0.42, 0.0)],

	["RightUpLeg", "Hips", Vector3(-0.09, -0.05, 0.0)],
	["RightLeg", "RightUpLeg", Vector3(0.0, -0.44, 0.0)],
	["RightFoot", "RightLeg", Vector3(0.0, -0.42, 0.0)],
]

## bone, box size, offset along the bone, material role
const SEGMENTS := [
	["Hips", Vector3(0.30, 0.17, 0.20), Vector3(0.0, -0.02, 0.0), "suit"],
	["Spine1", Vector3(0.33, 0.26, 0.21), Vector3(0.0, 0.07, 0.0), "suit"],
	["Spine2", Vector3(0.37, 0.17, 0.22), Vector3(0.0, 0.06, 0.0), "armor"],
	["Neck", Vector3(0.10, 0.08, 0.10), Vector3(0.0, 0.03, 0.0), "dark"],
	["Head", Vector3(0.19, 0.23, 0.21), Vector3(0.0, 0.11, 0.0), "dark"],
	# Visor: the one bright detail, so you can read which way a body is facing.
	["Head", Vector3(0.155, 0.06, 0.02), Vector3(0.0, 0.11, -0.106), "visor"],

	["LeftShoulder", Vector3(0.11, 0.13, 0.15), Vector3(0.075, 0.0, 0.0), "armor"],
	["LeftArm", Vector3(0.27, 0.105, 0.105), Vector3(0.135, 0.0, 0.0), "suit"],
	["LeftForeArm", Vector3(0.25, 0.09, 0.09), Vector3(0.125, 0.0, 0.0), "dark"],
	["LeftHand", Vector3(0.10, 0.08, 0.08), Vector3(0.05, 0.0, 0.0), "dark"],

	["RightShoulder", Vector3(0.11, 0.13, 0.15), Vector3(-0.075, 0.0, 0.0), "armor"],
	["RightArm", Vector3(0.27, 0.105, 0.105), Vector3(-0.135, 0.0, 0.0), "suit"],
	["RightForeArm", Vector3(0.25, 0.09, 0.09), Vector3(-0.125, 0.0, 0.0), "dark"],
	["RightHand", Vector3(0.10, 0.08, 0.08), Vector3(-0.05, 0.0, 0.0), "dark"],

	["LeftUpLeg", Vector3(0.135, 0.44, 0.145), Vector3(0.0, -0.22, 0.0), "suit"],
	["LeftLeg", Vector3(0.115, 0.42, 0.125), Vector3(0.0, -0.21, 0.0), "dark"],
	["LeftFoot", Vector3(0.115, 0.075, 0.25), Vector3(0.0, -0.04, 0.055), "dark"],

	["RightUpLeg", Vector3(0.135, 0.44, 0.145), Vector3(0.0, -0.22, 0.0), "suit"],
	["RightLeg", Vector3(0.115, 0.42, 0.125), Vector3(0.0, -0.21, 0.0), "dark"],
	["RightFoot", Vector3(0.115, 0.075, 0.25), Vector3(0.0, -0.04, 0.055), "dark"],
]

## Rifle-ready arm pose, in degrees. Held constant while alive: the character is
## always carrying, so swinging the arms like a jogger would look wrong.
const POSE_L_ARM := Vector3(0.0, 26.0, -72.0)
const POSE_L_FOREARM := Vector3(0.0, 74.0, 0.0)
const POSE_R_ARM := Vector3(0.0, -20.0, 68.0)
const POSE_R_FOREARM := Vector3(0.0, -68.0, 0.0)

## Applied to whatever is parented to the right hand, to point the barrel down
## the character's -Z instead of wherever the wrist ended up.
const GRIP_CORRECTION := Vector3(18.0, -104.0, 0.0)

var skeleton: Skeleton3D
var accent := Color(0.35, 0.95, 0.75)

var _bone: Dictionary = {}
var _phase := 0.0
var _bob := 0.0
var _lean := 0.0
var _crouch_blend := 0.0
var _death_blend := 0.0


func build(accent_color: Color) -> void:
	accent = accent_color
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)

	for entry in BONES:
		var bone_name: String = entry[0]
		skeleton.add_bone(bone_name)
		var idx := skeleton.find_bone(bone_name)
		_bone[bone_name] = idx
		var parent_name: String = entry[1]
		if not parent_name.is_empty():
			skeleton.set_bone_parent(idx, _bone[parent_name])
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, entry[2]))

	skeleton.reset_bone_poses()

	var mats := _materials()
	for seg in SEGMENTS:
		_attach_segment(seg[0], seg[1], seg[2], mats[seg[3]])

	_apply_arm_pose()


func _materials() -> Dictionary:
	var suit := StandardMaterial3D.new()
	suit.albedo_color = accent
	suit.roughness = 0.65

	var armor := StandardMaterial3D.new()
	armor.albedo_color = accent.darkened(0.35)
	armor.roughness = 0.45
	armor.metallic = 0.35

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.16)
	dark.roughness = 0.7

	var visor := StandardMaterial3D.new()
	visor.albedo_color = accent.lightened(0.4)
	visor.emission_enabled = true
	visor.emission = accent.lightened(0.25)
	visor.emission_energy_multiplier = 1.6
	visor.roughness = 0.2

	return {"suit": suit, "armor": armor, "dark": dark, "visor": visor}


func _attach_segment(bone_name: String, size: Vector3, offset: Vector3,
		material: StandardMaterial3D) -> void:
	if not _bone.has(bone_name):
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone_name
	attach.bone_idx = _bone[bone_name]
	skeleton.add_child(attach)

	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = offset
	attach.add_child(mi)


func _set_rot(bone_name: String, degrees: Vector3) -> void:
	if not _bone.has(bone_name):
		return
	skeleton.set_bone_pose_rotation(_bone[bone_name],
			Quaternion.from_euler(Vector3(
				deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))))


func _apply_arm_pose() -> void:
	_set_rot("LeftArm", POSE_L_ARM)
	_set_rot("LeftForeArm", POSE_L_FOREARM)
	_set_rot("RightArm", POSE_R_ARM)
	_set_rot("RightForeArm", POSE_R_FOREARM)

# ------------------------------------------------------------------ animation

## Drive the pose from gameplay state. Called by CharacterAnimator whenever no
## Mixamo clip library is loaded.
func update_pose(delta: float, speed_ratio: float, forward: float, strafe: float,
		crouching: bool, airborne: bool, aiming: bool, dead: bool) -> void:
	if skeleton == null:
		return

	_death_blend = move_toward(_death_blend, 1.0 if dead else 0.0, delta * 4.0)
	if _death_blend > 0.001:
		_pose_death()
		if dead:
			return

	_crouch_blend = move_toward(_crouch_blend, 1.0 if crouching else 0.0, delta * 8.0)

	# Stride frequency scales with speed, so walking and sprinting read apart.
	var stride := 5.0 + 5.0 * speed_ratio
	if speed_ratio > 0.05:
		_phase += delta * stride
	else:
		# Settle the legs rather than freezing mid-stride.
		_phase = lerp_angle(_phase, 0.0, delta * 6.0)

	# Ramp the stride in over the first third of the speed range so stepping off
	# from standing does not snap straight to a full swing.
	var gait: float = clampf(speed_ratio / 0.35, 0.0, 1.0)
	var amplitude: float = (20.0 + 28.0 * speed_ratio) * gait
	var swing: float = sin(_phase) * amplitude
	var lift: float = maxf(0.0, -cos(_phase)) * (0.7 * amplitude)

	if airborne:
		# Tuck: front knee up, trailing leg extended.
		_set_rot("LeftUpLeg", Vector3(-38.0, 0.0, 0.0))
		_set_rot("LeftLeg", Vector3(52.0, 0.0, 0.0))
		_set_rot("RightUpLeg", Vector3(12.0, 0.0, 0.0))
		_set_rot("RightLeg", Vector3(28.0, 0.0, 0.0))
	else:
		var crouch_thigh := 60.0 * _crouch_blend
		var crouch_shin := 85.0 * _crouch_blend
		_set_rot("LeftUpLeg", Vector3(-swing - crouch_thigh, 0.0, 0.0))
		_set_rot("LeftLeg", Vector3(lift + crouch_shin, 0.0, 0.0))
		_set_rot("RightUpLeg", Vector3(swing - crouch_thigh, 0.0, 0.0))
		_set_rot("RightLeg", Vector3(maxf(0.0, cos(_phase)) * 0.7 * amplitude
				+ crouch_shin, 0.0, 0.0))
		_set_rot("LeftFoot", Vector3(-crouch_shin * 0.35, 0.0, 0.0))
		_set_rot("RightFoot", Vector3(-crouch_shin * 0.35, 0.0, 0.0))

	# Torso counter-rotates against the stride, and leans into the movement.
	var target_lean := forward * 7.0
	_lean = lerpf(_lean, target_lean, delta * 6.0)
	_set_rot("Spine", Vector3(_lean * 0.5 + 8.0 * _crouch_blend,
			-sin(_phase) * 5.0 * speed_ratio, -strafe * 4.0))
	_set_rot("Spine1", Vector3(_lean * 0.3, sin(_phase) * 3.0 * speed_ratio, 0.0))

	# Head stays level while the body works underneath it.
	_set_rot("Neck", Vector3(-_lean * 0.6 - 6.0 * _crouch_blend, 0.0, 0.0))

	# Aiming squares the shoulders up; hip-firing relaxes them.
	var aim_pull := 8.0 if aiming else 0.0
	_set_rot("LeftArm", POSE_L_ARM + Vector3(0.0, -aim_pull, 0.0))
	_set_rot("RightArm", POSE_R_ARM + Vector3(0.0, aim_pull * 0.5, 0.0))
	_set_rot("LeftForeArm", POSE_L_FOREARM)
	_set_rot("RightForeArm", POSE_R_FOREARM)

	# Vertical bob: a small sink on each footfall, plus the crouch drop.
	# 0.26 is what the 60/85 degree knee fold actually shortens the leg by;
	# dropping further would bury the feet.
	_bob = lerpf(_bob, -0.26 * _crouch_blend
			+ absf(sin(_phase)) * 0.035 * speed_ratio, delta * 14.0)
	position.y = _bob


func _pose_death() -> void:
	var t := _death_blend

	# Slacken the limbs out of the rifle carry...
	_set_rot("Spine", Vector3(lerpf(0.0, 14.0, t), 0.0, lerpf(0.0, 10.0, t)))
	_set_rot("Spine1", Vector3(lerpf(0.0, 10.0, t), 0.0, 0.0))
	_set_rot("Neck", Vector3(lerpf(0.0, 22.0, t), 0.0, 0.0))
	_set_rot("LeftUpLeg", Vector3(lerpf(0.0, -28.0, t), 0.0, lerpf(0.0, 16.0, t)))
	_set_rot("LeftLeg", Vector3(lerpf(0.0, 46.0, t), 0.0, 0.0))
	_set_rot("RightUpLeg", Vector3(lerpf(0.0, -12.0, t), 0.0, lerpf(0.0, -22.0, t)))
	_set_rot("RightLeg", Vector3(lerpf(0.0, 24.0, t), 0.0, 0.0))
	_set_rot("LeftArm", POSE_L_ARM.lerp(Vector3(0.0, 10.0, -96.0), t))
	_set_rot("LeftForeArm", POSE_L_FOREARM.lerp(Vector3(0.0, 24.0, 0.0), t))
	_set_rot("RightArm", POSE_R_ARM.lerp(Vector3(0.0, -10.0, 96.0), t))
	_set_rot("RightForeArm", POSE_R_FOREARM.lerp(Vector3(0.0, -18.0, 0.0), t))

	# ...then topple the whole body onto its back.
	rotation.x = deg_to_rad(lerpf(0.0, -84.0, t))
	position.y = lerpf(0.0, 0.28, t)
	position.z = lerpf(0.0, -0.35, t)


func revive() -> void:
	_death_blend = 0.0
	_crouch_blend = 0.0
	_phase = 0.0
	_bob = 0.0
	_lean = 0.0
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	if skeleton != null:
		skeleton.reset_bone_poses()
		_apply_arm_pose()
