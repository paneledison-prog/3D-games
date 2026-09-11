extends Resource
class_name WeaponData
## Data-driven weapon definition. One .tres per gun in res://resources/weapons/.
##
## Everything the firing code needs lives here, so balancing the arsenal never
## means touching WeaponSystem.

enum Category { PISTOL, SMG, RIFLE, SNIPER, SHOTGUN, MELEE, THROWABLE }

@export_group("Identity")
@export var id: String = "weapon"
@export var display_name: String = "Weapon"
@export var category: Category = Category.RIFLE

@export_group("Damage")
## Damage per bullet at point blank, before falloff and headshot multiplier.
@export var damage: float = 24.0
@export var headshot_multiplier: float = 2.0
@export var limb_multiplier: float = 0.85
## Pellets per trigger pull. Shotguns fire many, everything else fires one.
@export var pellets: int = 1
## Beyond falloff_start damage ramps down, reaching min_damage_scale at falloff_end.
@export var falloff_start: float = 25.0
@export var falloff_end: float = 60.0
@export var min_damage_scale: float = 0.55
@export var max_range: float = 200.0

@export_group("Handling")
## Rounds per minute.
@export var fire_rate: float = 600.0
@export var automatic: bool = true
@export var mag_size: int = 30
@export var reserve_ammo: int = 120
@export var reload_time: float = 2.1
@export var equip_time: float = 0.45

@export_group("Accuracy")
## Cone half-angle in degrees.
@export var spread_hip: float = 2.4
@export var spread_ads: float = 0.35
## Added to spread while moving, scaled by speed.
@export var spread_move_penalty: float = 2.0
## Added per shot fired, decays back toward the base cone.
@export var spread_per_shot: float = 0.5
@export var spread_max: float = 8.0
@export var spread_recovery: float = 6.0

@export_group("Recoil")
## Degrees kicked up per shot.
@export var recoil_vertical: float = 0.55
## Degrees kicked sideways per shot; sign alternates randomly.
@export var recoil_horizontal: float = 0.22
@export var recoil_recovery: float = 8.0

@export_group("Aiming")
@export var ads_fov: float = 52.0
@export var ads_time: float = 0.16
@export var ads_move_scale: float = 0.55

@export_group("Audio")
@export var sfx_fire: String = "wpn_rifle_fire"
@export var sfx_reload_out: String = "wpn_mag_out"
@export var sfx_reload_in: String = "wpn_mag_in"
@export var sfx_bolt: String = "wpn_bolt"
@export var fire_volume_db: float = -2.0
@export var fire_pitch_variation: float = 0.06

@export_group("Presentation")
## Which Mixamo animation set the character plays while holding this weapon.
@export var anim_profile: String = "rifle"
@export var viewmodel_offset: Vector3 = Vector3(0.22, -0.18, -0.42)
@export var viewmodel_scale: float = 1.0
@export var muzzle_flash_scale: float = 1.0

@export_group("Melee")
## How far the blade reaches. Only used by MELEE weapons.
@export var melee_range: float = 2.2
## Half-angle of the swing sweep, in degrees. A wider arc is more forgiving.
@export var melee_arc: float = 22.0
## Seconds between the swing starting and the damage being applied, so the hit
## lands when the blade visually connects rather than on the button press.
@export var melee_hit_delay: float = 0.12

@export_group("Throwable")
## Initial speed the grenade leaves the hand at, in m/s.
@export var throw_force: float = 16.0
## Extra upward push so a flat throw still arcs.
@export var throw_arc: float = 4.0
## Seconds from the pin pulling to detonation.
@export var fuse_time: float = 2.6
## Damage at the centre of the blast, falling off to zero at blast_radius.
@export var blast_damage: float = 130.0
@export var blast_radius: float = 7.0
## Scene spawned when thrown. Defaults to the shared grenade projectile.
@export var projectile_scene: String = "res://scenes/weapons/Grenade.tscn"

@export_group("Model")
## Real-world length of the weapon in metres. Downloaded models arrive at wildly
## different scales - a Quaternius rifle imports 5.2 m long - so the model is
## measured on load and scaled to this, instead of hand-tuning a magic factor
## per model. Set to 0 to disable and use model_scale directly.
@export var target_length: float = 0.0
## res:// path to a real weapon model (Free3D, Sketchfab, your own). Empty
## falls back to a class-shaped placeholder block, so the game never breaks
## waiting on art.
@export var model_path: String = ""
## Third-person scale, applied in the character's hand socket.
@export var model_scale: float = 1.0
@export var model_offset: Vector3 = Vector3.ZERO
@export var model_rotation: Vector3 = Vector3.ZERO
## First-person scale. Viewmodels usually want to read slightly larger.
@export var viewmodel_model_scale: float = 1.0
@export var viewmodel_rotation: Vector3 = Vector3(0.0, 180.0, 0.0)
## Muzzle tip in model space, used to place the flash and tracer origin when a
## real model replaces the placeholder.
@export var muzzle_local: Vector3 = Vector3(0.0, 0.0, -0.35)


## Formats Godot can import, in the order we prefer them.
const MODEL_EXTS := ["glb", "gltf", "fbx", "obj", "dae", "blend"]


## Resolve the model file, tolerating whatever format it was downloaded in.
## Free3D hands out .obj/.fbx/.blend depending on the model, so rather than
## forcing a conversion we accept any basename match. Returns "" if none exist.
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


## Longest dimension of every mesh under root, in root-local metres.
static func longest_axis(root: Node3D) -> float:
	var meshes: Array[MeshInstance3D] = []
	_gather_meshes(root, meshes)
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
	var s := total.size
	return maxf(s.x, maxf(s.y, s.z))


static func _gather_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_gather_meshes(child, out)


## Uniform scale that brings an instanced model to target_length. Falls back to
## the manual model_scale when auto-fit is off or the model cannot be measured.
func fit_scale(root: Node3D) -> float:
	if target_length <= 0.0:
		return model_scale
	var length := longest_axis(root)
	if length <= 0.001:
		return model_scale
	return target_length / length


func seconds_per_shot() -> float:
	return 60.0 / maxf(fire_rate, 1.0)


## Damage multiplier from distance falloff.
func falloff_scale(distance: float) -> float:
	if distance <= falloff_start:
		return 1.0
	if distance >= falloff_end:
		return min_damage_scale
	var t := (distance - falloff_start) / maxf(falloff_end - falloff_start, 0.001)
	return lerpf(1.0, min_damage_scale, t)


func category_name() -> String:
	return ["PISTOL", "SMG", "RIFLE", "SNIPER", "SHOTGUN", "MELEE",
			"THROWABLE"][int(category)]


func is_melee() -> bool:
	return category == Category.MELEE


func is_throwable() -> bool:
	return category == Category.THROWABLE
