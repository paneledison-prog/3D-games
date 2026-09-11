extends Node3D
class_name ViewModel
## The gun you actually see in first person.
##
## Rebuilt whenever the held weapon changes: real model when one exists, a
## class-shaped block when it does not. Also drives the ADS transition and
## keeps the muzzle marker parked on the barrel tip.

## Where the weapon sits when aiming: centred under the crosshair.
const ADS_OFFSET := Vector3(0.0, -0.045, -0.30)
const SWAY_AMOUNT := 0.02
const SWAY_SPEED := 7.0

@export var muzzle_path: NodePath = ^"../Muzzle"

var _weapons: WeaponSystem
var _muzzle: Node3D
var _model: Node3D
var _hip_offset := Vector3(0.22, -0.18, -0.42)
var _sway_phase := 0.0


func _ready() -> void:
	_weapons = get_parent() as WeaponSystem
	_muzzle = get_node_or_null(muzzle_path) as Node3D
	if _weapons != null:
		_weapons.weapon_changed.connect(_on_weapon_changed)
		var current := _weapons.current()
		if current != null:
			_on_weapon_changed(current, _weapons.slot)


func _process(delta: float) -> void:
	if _weapons == null:
		return

	var weapon := _weapons.current()
	var aiming := _weapons.is_aiming
	var target := ADS_OFFSET if aiming else _hip_offset

	# A slow figure-eight sway while hip-firing keeps the pose from looking
	# frozen; aiming settles it so precision reads as precision.
	if not aiming:
		_sway_phase += delta * SWAY_SPEED
		target += Vector3(sin(_sway_phase) * SWAY_AMOUNT,
				sin(_sway_phase * 2.0) * SWAY_AMOUNT * 0.5, 0.0)

	var speed: float = 1.0 / maxf(weapon.ads_time if weapon != null else 0.16, 0.01)
	position = position.lerp(target, clampf(delta * speed, 0.0, 1.0))


func _on_weapon_changed(weapon: WeaponData, _slot: int) -> void:
	_hip_offset = weapon.viewmodel_offset
	_rebuild(weapon)
	_place_muzzle(weapon)


func _rebuild(weapon: WeaponData) -> void:
	if is_instance_valid(_model):
		_model.queue_free()
	_model = null

	var node: Node3D = null
	var path := weapon.resolve_model_path()
	if not path.is_empty():
		var packed: PackedScene = load(path)
		if packed != null:
			node = packed.instantiate() as Node3D

	if node == null:
		node = _placeholder(weapon)

	node.rotation_degrees = weapon.viewmodel_rotation
	# Measured against the instanced model, so any download lands the right size.
	var fitted := weapon.fit_scale(node)
	node.scale = Vector3.ONE * fitted * weapon.viewmodel_scale 			* weapon.viewmodel_model_scale
	add_child(node)
	_model = node

	# The viewmodel must never clip into walls the camera is pressed against.
	for mi in _meshes(node):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Park the muzzle marker on the barrel tip so flashes and tracers originate
## from the right place regardless of which model is loaded.
func _place_muzzle(weapon: WeaponData) -> void:
	if _muzzle == null:
		return
	_muzzle.position = _hip_offset + weapon.muzzle_local


func _placeholder(weapon: WeaponData) -> Node3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	match weapon.category:
		WeaponData.Category.PISTOL:
			box.size = Vector3(0.06, 0.13, 0.26)
		WeaponData.Category.SNIPER:
			box.size = Vector3(0.07, 0.11, 0.92)
		WeaponData.Category.SHOTGUN:
			box.size = Vector3(0.08, 0.12, 0.74)
		WeaponData.Category.SMG:
			box.size = Vector3(0.07, 0.12, 0.44)
		_:
			box.size = Vector3(0.07, 0.11, 0.60)
	mi.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.14, 0.16)
	mat.metallic = 0.7
	mat.roughness = 0.45
	mi.material_override = mat
	return mi


func _meshes(node: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_meshes(child, out)
	return out
