extends Node3D
class_name WeaponSystem
## Hitscan firing, ammo, spread, recoil and reloading for one character.
##
## Deliberately agnostic about who is shooting: the player feeds it the camera
## transform, the bot feeds it its own aim transform, and the rest is identical.

signal fired(weapon: WeaponData, recoil_v: float, recoil_h: float)
signal ammo_changed(mag: int, reserve: int)
signal weapon_changed(weapon: WeaponData, slot: int)
signal reload_started(duration: float)
signal reload_finished()
signal hit_confirmed(is_headshot: bool)
signal target_killed(victim: Node)

const WEAPON_DIR := "res://resources/weapons"
## world | player | enemy | hitbox
const HIT_MASK := 0b1111

static var _registry: Dictionary = {}

@export var is_local_player := false

var shooter: Node3D
var muzzle: Node3D
var fx_parent: Node

var weapons: Array[WeaponData] = []
var slot := 0
var mags: Array[int] = []
var reserves: Array[int] = []

var current_spread := 0.0
var is_reloading := false
var is_aiming := false

var _cooldown := 0.0
var _equip_timer := 0.0
var _reload_elapsed := 0.0
var _reload_stage := 0
var _shooter_speed := 0.0


static func get_weapon(id: String) -> WeaponData:
	if _registry.has(id):
		return _registry[id]
	var path := "%s/%s.tres" % [WEAPON_DIR, id]
	if not ResourceLoader.exists(path):
		push_error("WeaponSystem: unknown weapon id '%s'" % id)
		return null
	var data: WeaponData = load(path)
	_registry[id] = data
	return data


func setup(loadout: Array[String], p_shooter: Node3D, p_muzzle: Node3D, p_fx_parent: Node) -> void:
	shooter = p_shooter
	muzzle = p_muzzle
	fx_parent = p_fx_parent

	weapons.clear()
	mags.clear()
	reserves.clear()
	for id in loadout:
		var data := get_weapon(id)
		if data == null:
			continue
		weapons.append(data)
		mags.append(data.mag_size)
		reserves.append(data.reserve_ammo)

	slot = 0
	_apply_slot(true)


func refill() -> void:
	for i in weapons.size():
		mags[i] = weapons[i].mag_size
		reserves[i] = weapons[i].reserve_ammo
	slot = 0
	is_reloading = false
	_reload_elapsed = 0.0
	current_spread = 0.0
	_apply_slot(true)


func current() -> WeaponData:
	if weapons.is_empty():
		return null
	return weapons[slot]


func mag() -> int:
	return 0 if mags.is_empty() else mags[slot]


func reserve() -> int:
	return 0 if reserves.is_empty() else reserves[slot]


func can_fire() -> bool:
	return current() != null and _cooldown <= 0.0 and _equip_timer <= 0.0 \
			and not is_reloading and mags[slot] > 0


## Called every frame by the owning character with its current planar speed.
func tick(delta: float, shooter_speed := 0.0) -> void:
	_shooter_speed = shooter_speed
	_cooldown = maxf(_cooldown - delta, 0.0)
	_equip_timer = maxf(_equip_timer - delta, 0.0)

	var w := current()
	if w == null:
		return

	current_spread = maxf(current_spread - w.spread_recovery * delta, 0.0)

	if is_reloading:
		_reload_elapsed += delta
		if _reload_stage == 0 and _reload_elapsed >= w.reload_time * 0.45:
			_reload_stage = 1
			_play(w.sfx_reload_in, -4.0)
		if _reload_elapsed >= w.reload_time:
			_finish_reload()


func base_spread() -> float:
	var w := current()
	if w == null:
		return 0.0
	var base := w.spread_ads if is_aiming else w.spread_hip
	var move := w.spread_move_penalty * clampf(_shooter_speed / 6.0, 0.0, 1.0)
	return base + move + current_spread


## Fire one trigger pull. Returns true if a shot actually left the barrel.
func try_fire(origin: Vector3, direction: Vector3) -> bool:
	var w := current()
	if w == null:
		return false

	if _cooldown > 0.0 or _equip_timer > 0.0 or is_reloading:
		return false

	# Melee and throwables run on entirely different rules to hitscan guns.
	if w.is_melee():
		return _swing_melee(w, origin, direction)
	if w.is_throwable():
		return _throw(w, origin, direction)

	if mags[slot] <= 0:
		_play("wpn_dry_fire", -8.0)
		_cooldown = 0.25
		return false

	mags[slot] -= 1
	_cooldown = w.seconds_per_shot()
	ammo_changed.emit(mags[slot], reserves[slot])

	var spread := base_spread()
	var any_hit := false
	var any_headshot := false

	for pellet in w.pellets:
		var dir := _apply_spread(direction, spread)
		var result := _trace(origin, dir, w)
		if result.is_empty():
			continue
		if result.get("hit_character", false):
			any_hit = true
			if result.get("headshot", false):
				any_headshot = true

	current_spread = minf(current_spread + w.spread_per_shot, w.spread_max)

	# Audio + visuals
	_play(w.sfx_fire, w.fire_volume_db, w.fire_pitch_variation)
	if muzzle != null:
		CombatFX.flash_muzzle(muzzle, w.muzzle_flash_scale)

	var kick_h: float = w.recoil_horizontal * (1.0 if randf() < 0.5 else -1.0)
	fired.emit(w, w.recoil_vertical, kick_h)

	if any_hit:
		hit_confirmed.emit(any_headshot)
		if is_local_player:
			AudioManager.play_2d(
				"hitmarker_headshot" if any_headshot else "hitmarker", -6.0)
	return true


# ---------------------------------------------------------------------- melee

## A knife swing. No ammo, no spread; the damage lands a moment after the swing
## starts so it connects when the blade visually arrives rather than instantly.
func _swing_melee(w: WeaponData, origin: Vector3, direction: Vector3) -> bool:
	_cooldown = w.seconds_per_shot()
	_play("melee_swing", -4.0, 0.10)
	fired.emit(w, w.recoil_vertical, 0.0)

	# The hit is resolved on a timer rather than with await, so try_fire stays a
	# plain synchronous bool instead of turning into a coroutine.
	var tree := get_tree()
	if tree != null and w.melee_hit_delay > 0.0:
		tree.create_timer(w.melee_hit_delay).timeout.connect(
				_resolve_melee_hit.bind(w, origin, direction), CONNECT_ONE_SHOT)
	else:
		_resolve_melee_hit(w, origin, direction)
	return true


## Traces the blade once the swing has visually landed.
func _resolve_melee_hit(w: WeaponData, origin: Vector3, direction: Vector3) -> void:
	if not is_inside_tree():
		return

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction.normalized() * w.melee_range, HIT_MASK)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	if shooter != null:
		query.exclude = _shooter_rids()

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return

	var target := _resolve_target(hit.collider)
	if target.is_empty():
		AudioManager.play_3d("melee_hit_world", hit.position, -5.0, 0.1, 30.0)
		CombatFX.spawn_impact(fx_parent, hit.position, hit.normal)
		return

	var zone: String = target["zone"]
	var victim: Node = target["node"]
	var damage := w.damage
	var headshot := zone == "head"
	if headshot:
		damage *= w.headshot_multiplier

	AudioManager.play_3d("melee_hit_flesh", hit.position, -2.0, 0.08, 35.0)
	CombatFX.spawn_impact(fx_parent, hit.position, hit.normal, Color(0.9, 0.2, 0.2))

	if victim.has_method("apply_damage"):
		victim.apply_damage(damage, shooter, headshot)
	hit_confirmed.emit(headshot)
	if is_local_player:
		AudioManager.play_2d("hitmarker_headshot" if headshot else "hitmarker", -6.0)

# ------------------------------------------------------------------ throwable

## Pull the pin and throw. Grenades consume from the magazine count, which for
## a throwable is simply how many you are carrying.
func _throw(w: WeaponData, origin: Vector3, direction: Vector3) -> bool:
	if mags[slot] <= 0:
		_play("wpn_dry_fire", -10.0)
		_cooldown = 0.3
		return false

	var scene_path := w.projectile_scene
	if not ResourceLoader.exists(scene_path):
		push_error("WeaponSystem: missing projectile scene '%s'" % scene_path)
		return false
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return false

	mags[slot] -= 1
	_cooldown = w.seconds_per_shot()
	ammo_changed.emit(mags[slot], reserves[slot])

	_play("grenade_pin", -8.0)
	_play("grenade_throw", -6.0, 0.08)

	var projectile := packed.instantiate()
	# Parented to the level, never to the thrower, so it keeps its own momentum.
	var host := fx_parent if fx_parent != null else get_tree().current_scene
	host.add_child(projectile)
	projectile.global_position = origin + direction.normalized() * 0.6
	if projectile.has_method("setup"):
		projectile.setup(w, shooter, direction)

	fired.emit(w, w.recoil_vertical, 0.0)
	return true


func start_reload() -> void:
	var w := current()
	if w == null or is_reloading:
		return
	if w.is_melee() or w.is_throwable():
		return
	if mags[slot] >= w.mag_size or reserves[slot] <= 0:
		return
	is_reloading = true
	_reload_elapsed = 0.0
	_reload_stage = 0
	_play(w.sfx_reload_out, -5.0)
	reload_started.emit(w.reload_time)


func next_weapon() -> void:
	if weapons.size() < 2:
		return
	switch_to((slot + 1) % weapons.size())


## Step through the loadout, wrapping at either end.
func cycle(step: int) -> void:
	if weapons.size() < 2:
		return
	switch_to(wrapi(slot + step, 0, weapons.size()))


func switch_to(index: int) -> void:
	if index < 0 or index >= weapons.size() or index == slot:
		return
	slot = index
	_apply_slot(false)

# ------------------------------------------------------------------ internals

func _apply_slot(silent: bool) -> void:
	var w := current()
	if w == null:
		return
	is_reloading = false
	_reload_elapsed = 0.0
	current_spread = 0.0
	_equip_timer = w.equip_time
	if not silent:
		_play("wpn_swap", -8.0)
	weapon_changed.emit(w, slot)
	ammo_changed.emit(mags[slot], reserves[slot])


func _finish_reload() -> void:
	var w := current()
	is_reloading = false
	_reload_elapsed = 0.0
	var needed: int = w.mag_size - mags[slot]
	var taken: int = mini(needed, reserves[slot])
	mags[slot] += taken
	reserves[slot] -= taken
	ammo_changed.emit(mags[slot], reserves[slot])
	reload_finished.emit()


func _apply_spread(direction: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.001:
		return direction
	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(direction).normalized()

	var angle := randf() * TAU
	var radius := sqrt(randf()) * tan(deg_to_rad(spread_deg))
	return (direction + right * cos(angle) * radius + up * sin(angle) * radius).normalized()


func _trace(origin: Vector3, direction: Vector3, w: WeaponData) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction * w.max_range, HIT_MASK)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = false
	if shooter != null:
		query.exclude = _shooter_rids()

	var hit := space.intersect_ray(query)
	var end_point := origin + direction * w.max_range
	if hit.is_empty():
		if muzzle != null:
			CombatFX.spawn_tracer(fx_parent, muzzle.global_position, end_point)
		return {}

	end_point = hit.position
	var collider: Node = hit.collider
	var target := _resolve_target(collider)

	if muzzle != null:
		CombatFX.spawn_tracer(fx_parent, muzzle.global_position, end_point)

	if target.is_empty():
		CombatFX.spawn_impact(fx_parent, end_point, hit.normal)
		AudioManager.play_impact(_surface_of(collider), end_point)
		return {"hit_character": false}

	var zone: String = target["zone"]
	var victim: Node = target["node"]
	var distance := origin.distance_to(end_point)

	var dmg := w.damage * w.falloff_scale(distance)
	var headshot := zone == "head"
	if headshot:
		dmg *= w.headshot_multiplier
	elif zone == "limb":
		dmg *= w.limb_multiplier

	CombatFX.spawn_impact(fx_parent, end_point, hit.normal, Color(0.9, 0.2, 0.2))
	AudioManager.play_impact("flesh", end_point)

	if victim.has_method("apply_damage"):
		victim.apply_damage(dmg, shooter, headshot)
		if victim.has_method("is_dead") and victim.is_dead():
			target_killed.emit(victim)

	return {"hit_character": true, "headshot": headshot}


func _shooter_rids() -> Array[RID]:
	var rids: Array[RID] = []
	if shooter is CollisionObject3D:
		rids.append((shooter as CollisionObject3D).get_rid())
	for child in shooter.get_children():
		if child is CollisionObject3D:
			rids.append((child as CollisionObject3D).get_rid())
	return rids


## Walk up from the collider to whoever actually owns a health pool.
func _resolve_target(collider: Node) -> Dictionary:
	if collider == null:
		return {}
	var zone := "body"
	if collider.has_meta("hit_zone"):
		zone = String(collider.get_meta("hit_zone"))

	var node := collider
	while node != null:
		if node.has_method("apply_damage"):
			return {"node": node, "zone": zone}
		node = node.get_parent()
	return {}


func _surface_of(collider: Node) -> String:
	if collider != null and collider.has_meta("surface"):
		return String(collider.get_meta("surface"))
	return "concrete"


func _play(sound: String, volume_db: float, pitch_var := 0.0) -> void:
	if sound.is_empty():
		return
	if is_local_player:
		AudioManager.play_2d(sound, volume_db, pitch_var)
	elif muzzle != null:
		AudioManager.play_3d(sound, muzzle.global_position, volume_db, pitch_var, 80.0)
