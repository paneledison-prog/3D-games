extends Node3D
class_name CharacterRig
## Assembles a character's visible body.
##
## If the profile's Mixamo model is present it is instanced, auto-scaled to the
## collider height, and given a weapon socket on the right hand bone. If it is
## absent the placeholder capsule stays up. Either way the rest of the game
## talks to the same interface, so nothing downstream depends on the art being
## there yet.

signal rig_built(has_model: bool)

const PROFILE_DIR := "res://resources/characters"

## Which profile to build. The player's is overridden from GameState at runtime.
@export var profile_id: String = "swat_guy"
## First-person owners see a viewmodel, so their third-person body renders as a
## shadow only - it still grounds them in the scene without blocking the view.
@export var shadows_only := false
@export var verbose := false

var profile: CharacterProfile
var model_root: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var weapon_socket: Node3D
var has_model := false
## Set when no Mixamo model was found and the articulated stand-in is in use.
var humanoid: ProceduralHumanoid

var _placeholder: Node3D
var _weapon_model: Node3D


static func load_profile(id: String) -> CharacterProfile:
	var path := "%s/%s.tres" % [PROFILE_DIR, id]
	if not ResourceLoader.exists(path):
		push_warning("CharacterRig: no profile '%s'" % id)
		return null
	return load(path)


## Every profile on disk, for the roster UI.
static func all_profiles() -> Array[CharacterProfile]:
	var out: Array[CharacterProfile] = []
	var dir := DirAccess.open(PROFILE_DIR)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for file in names:
		# Godot appends .remap to exported resources.
		var clean := file.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var res: Resource = load("%s/%s" % [PROFILE_DIR, clean])
		if res is CharacterProfile:
			out.append(res)
	return out


## Controllers call build() explicitly so the character choice is read from
## GameState at the right moment. Standalone use can flip this on.
@export var auto_build := false


func _ready() -> void:
	_placeholder = get_node_or_null("Placeholder")
	if auto_build:
		build(profile_id)


func build(id: String) -> void:
	profile_id = id
	profile = load_profile(id)

	_clear_model()
	has_model = false

	if profile == null:
		_fall_back()
		return

	_tint_placeholder(profile.accent_color)

	if not profile.has_model():
		if verbose:
			print("CharacterRig '%s': no model at '%s' - using placeholder."
					% [id, profile.model_path])
		_fall_back()
		return

	var packed: PackedScene = load(profile.resolve_model_path())
	if packed == null:
		_fall_back()
		return

	model_root = packed.instantiate() as Node3D
	if model_root == null:
		_fall_back()
		return

	model_root.name = "Model"
	add_child(model_root)

	skeleton = _find_node(model_root, Skeleton3D) as Skeleton3D
	animation_player = _find_node(model_root, AnimationPlayer) as AnimationPlayer
	if animation_player == null:
		# Mixamo character downloads carry no clips, so they often ship without
		# a player. Make one rooted at the model so "Skeleton3D:<bone>" track
		# paths from the shared library resolve.
		animation_player = AnimationPlayer.new()
		animation_player.name = "AnimationPlayer"
		model_root.add_child(animation_player)
	animation_player.root_node = animation_player.get_path_to(model_root)

	_fit_model()
	_build_weapon_socket()

	if shadows_only:
		_set_shadows_only(model_root)

	_show_placeholder(false)
	has_model = true

	if verbose:
		print("CharacterRig '%s': model loaded (%d bones, socket=%s)" % [
			id,
			skeleton.get_bone_count() if skeleton != null else 0,
			"yes" if weapon_socket != null else "no"])

	rig_built.emit(true)

# ------------------------------------------------------------------- weapons

## Swap the gun held in the character's hand. Falls back to a simple block when
## the weapon has no model, so the hand is never empty.
func equip_model(weapon: WeaponData) -> void:
	if weapon_socket == null:
		return
	if is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
	_weapon_model = null

	var node: Node3D = null
	var path := weapon.resolve_model_path()
	if not path.is_empty():
		var packed: PackedScene = load(path)
		if packed != null:
			node = packed.instantiate() as Node3D

	if node == null:
		node = _placeholder_gun(weapon)

	node.position = weapon.model_offset + (profile.grip_offset if profile else Vector3.ZERO)
	node.rotation_degrees = weapon.model_rotation \
			+ (profile.grip_rotation if profile else Vector3.ZERO)
	node.scale = Vector3.ONE * weapon.fit_scale(node)

	weapon_socket.add_child(node)
	_weapon_model = node

	if shadows_only:
		_set_shadows_only(node)


## Flip the whole body between fully drawn and shadow-only. Third person needs
## to see the character; first person must not have it in front of the lens.
func set_shadows_only(value: bool) -> void:
	shadows_only = value
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if value 			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for root in [model_root, _placeholder, _weapon_model]:
		if root == null or not is_instance_valid(root):
			continue
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(root, meshes)
		for mi in meshes:
			mi.cast_shadow = mode


func _placeholder_gun(weapon: WeaponData) -> Node3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	# Roughly silhouette the weapon class so the placeholder still reads.
	match weapon.category:
		WeaponData.Category.PISTOL:
			box.size = Vector3(0.06, 0.14, 0.24)
		WeaponData.Category.SNIPER:
			box.size = Vector3(0.07, 0.12, 1.05)
		WeaponData.Category.SHOTGUN:
			box.size = Vector3(0.08, 0.13, 0.82)
		_:
			box.size = Vector3(0.08, 0.13, 0.66)
	mi.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.13, 0.15)
	mat.metallic = 0.7
	mat.roughness = 0.45
	mi.material_override = mat
	return mi

# ------------------------------------------------------------------ internals

func _fit_model() -> void:
	model_root.rotation_degrees.y = profile.model_rotation_y

	var scale_factor := profile.model_scale
	if profile.auto_fit_height:
		var height := _measure_height(model_root)
		if height > 0.001:
			scale_factor = profile.target_height / height
		elif verbose:
			push_warning("CharacterRig: could not measure '%s'; using model_scale."
					% profile.id)

	model_root.scale = Vector3.ONE * scale_factor
	model_root.position = profile.model_offset


## Combined height of every mesh in the model, in the model's own space.
func _measure_height(root: Node3D) -> float:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	if meshes.is_empty():
		return 0.0

	var total := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in meshes:
		var local := inv * mi.global_transform
		var box := local * mi.get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
	return total.size.y


func _build_weapon_socket() -> void:
	if skeleton == null:
		# No skeleton: hang the socket off the model root so guns still show.
		weapon_socket = Node3D.new()
		weapon_socket.name = "WeaponSocket"
		model_root.add_child(weapon_socket)
		return

	var bone := find_bone(skeleton, profile.right_hand_bone)
	if bone < 0:
		push_warning("CharacterRig '%s': no bone matching '%s'; "
				% [profile.id, profile.right_hand_bone]
				+ "weapon will not follow the hand.")
		weapon_socket = Node3D.new()
		weapon_socket.name = "WeaponSocket"
		model_root.add_child(weapon_socket)
		return

	var attach := BoneAttachment3D.new()
	attach.name = "WeaponSocket"
	attach.bone_name = skeleton.get_bone_name(bone)
	attach.bone_idx = bone
	skeleton.add_child(attach)

	# The socket sits inside the skeleton, which the auto-fit already scaled.
	# Counter-scale so weapon offsets stay in real metres.
	var holder := Node3D.new()
	holder.name = "Grip"
	var s := model_root.scale.x
	if s > 0.0001:
		holder.scale = Vector3.ONE / s
	attach.add_child(holder)
	weapon_socket = holder


## Find a bone by exact name, then by suffix so "RightHand" matches
## "mixamorig:RightHand".
static func find_bone(skel: Skeleton3D, wanted: String) -> int:
	if skel == null or wanted.is_empty():
		return -1
	var want := wanted.to_lower()
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower() == want:
			return i
	for i in skel.get_bone_count():
		var bone_name := skel.get_bone_name(i).to_lower()
		if bone_name.ends_with(":" + want) or bone_name.ends_with(want):
			return i
	return -1


## No Mixamo model available. Rather than a capsule, build the articulated
## stand-in: it uses the same bone names, so the weapon socket, the hand
## attachment and (later) the Mixamo clips all behave identically.
func _fall_back() -> void:
	_show_placeholder(false)

	humanoid = ProceduralHumanoid.new()
	humanoid.name = "Humanoid"
	add_child(humanoid)
	humanoid.build(profile.accent_color if profile else Color(0.35, 0.95, 0.75))

	# Treat it as the model for everything downstream. has_model stays false so
	# callers can still tell a stand-in from the real thing.
	model_root = humanoid
	skeleton = humanoid.skeleton
	_build_weapon_socket()

	if shadows_only:
		_set_shadows_only(humanoid)

	rig_built.emit(false)


func _clear_model() -> void:
	if is_instance_valid(model_root):
		model_root.queue_free()
	humanoid = null
	model_root = null
	skeleton = null
	animation_player = null
	weapon_socket = null
	_weapon_model = null


func _show_placeholder(visible_state: bool) -> void:
	if _placeholder != null:
		_placeholder.visible = visible_state
		if visible_state and shadows_only:
			_set_shadows_only(_placeholder)


func _tint_placeholder(color: Color) -> void:
	if _placeholder == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_placeholder, meshes)
	for mi in meshes:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.7
		mat.emission_enabled = true
		mat.emission = color * 0.4
		mat.emission_energy_multiplier = 0.3
		mi.material_override = mat


func _set_shadows_only(root: Node) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _find_node(node: Node, type) -> Node:
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var found := _find_node(child, type)
		if found != null:
			return found
	return null
