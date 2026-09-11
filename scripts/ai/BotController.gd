extends CharacterBody3D
class_name BotController
## The Lone Wolf opponent with Utility AI.
##
## Replaces the old rigid state machine with a dynamic utility evaluation.
## Evaluates actions (Patrol, Attack, Take Cover, Reload, Retreat) based on 
## current context like health, ammo, and distance.

signal died(attacker: Node)

enum Action { PATROL, ATTACK, TAKE_COVER, RELOAD, RETREAT, DEAD }

# Kept inside the same animation-speed envelope as the player.
const WALK_SPEED := 4.0
const CHASE_SPEED := 5.4
const ACCEL := 10.0
const FRICTION := 12.0

const VIEW_RANGE := 65.0
const VIEW_ANGLE := deg_to_rad(105.0)
const LOSE_TARGET_TIME := 2.2
const CHEST_OFFSET := Vector3(0.0, 1.35, 0.0)

@onready var aim_pivot: Node3D = $AimPivot
@onready var collision: CollisionShape3D = $Collision
@onready var head_box: Area3D = $HeadBox
@onready var weapons: WeaponSystem = $AimPivot/WeaponSystem
@onready var muzzle: Marker3D = $AimPivot/WeaponSystem/Muzzle
@onready var health: Health = $Health
@onready var animator: CharacterAnimator = $Animator
@onready var nav: NavigationAgent3D = $NavAgent
@onready var rig: CharacterRig = $Body

var current_action: Action = Action.PATROL
var target: Node3D
var enabled := true

var _profile: Dictionary = {}
var _aim_dir := Vector3.FORWARD
var _aim_error := Vector3.ZERO
var _error_scale := 1.0
var _reaction_timer := 0.0
var _last_seen_pos := Vector3.ZERO
var _time_since_seen := 999.0
var _burst_left := 0
var _burst_cooldown := 0.0

var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _repath_timer := 0.0
var _utility_timer := 0.0
var _step_accum := 0.0
var _preferred_range := 14.0

var _cover_pos := Vector3.ZERO


func _ready() -> void:
	add_to_group(&"bot")
	head_box.set_meta("hit_zone", "head")

	_profile = GameState.bot_profile()

	rig.build(GameState.bot_character)
	if rig.animation_player != null:
		animator.bind_animation_player(rig.animation_player, rig.skeleton)
	animator.bind_humanoid(rig.humanoid)

	weapons.is_local_player = false
	weapons.setup(GameState.bot_loadout, self, muzzle, get_tree().current_scene)
	weapons.reload_started.connect(_on_reload_started)
	weapons.weapon_changed.connect(func(w: WeaponData, _s: int): rig.equip_model(w))
	health.died.connect(_on_died)

	var starting := weapons.current()
	if starting != null:
		rig.equip_model(starting)

	nav.path_desired_distance = 0.8
	nav.target_desired_distance = 1.2
	nav.avoidance_enabled = false

	_aim_dir = -global_transform.basis.z
	_pick_preferred_range()
	call_deferred("_acquire_player")


func _acquire_player() -> void:
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group(&"player")
	if not players.is_empty():
		target = players[0] as Node3D
	current_action = Action.PATROL


func _pick_preferred_range() -> void:
	var w := weapons.current()
	if w == null:
		_preferred_range = 14.0
		return
	match w.category:
		WeaponData.Category.SHOTGUN:
			_preferred_range = 6.0
		WeaponData.Category.SMG:
			_preferred_range = 10.0
		WeaponData.Category.SNIPER:
			_preferred_range = 34.0
		WeaponData.Category.PISTOL:
			_preferred_range = 12.0
		_:
			_preferred_range = 17.0


func _physics_process(delta: float) -> void:
	if current_action == Action.DEAD:
		velocity = velocity.move_toward(Vector3.ZERO, FRICTION * delta)
		move_and_slide()
		animator.update(delta, 0.0, 0.0, 0.0, false, false, false, 0.0)
		return

	if not enabled:
		velocity = velocity.move_toward(Vector3.ZERO, FRICTION * delta)
		move_and_slide()
		return

	weapons.tick(delta, Vector2(velocity.x, velocity.z).length())

	_update_perception(delta)
	
	# Utility evaluation tick
	_utility_timer -= delta
	if _utility_timer <= 0.0:
		_utility_timer = 0.25 # evaluate 4 times a second
		_evaluate_utility()
		
	_execute_action(delta)
	
	_update_aim(delta)
	_apply_gravity(delta)
	move_and_slide()
	_update_footsteps(delta)

	var planar := Vector2(velocity.x, velocity.z).length()
	var local_vel := global_transform.basis.inverse() * velocity
	# Real speed is passed through so the animator can match stride to movement
	# instead of playing the clip at a fixed rate and skating.
	animator.update(delta, clampf(planar / CHASE_SPEED, 0.0, 1.0),
			clampf(-local_vel.z / CHASE_SPEED, -1.0, 1.0),
			clampf(local_vel.x / CHASE_SPEED, -1.0, 1.0),
			false, not is_on_floor(), current_action == Action.ATTACK, planar)


# ------------------------------------------------------------------ utility AI

func _evaluate_utility() -> void:
	if current_action == Action.DEAD: return
	
	var scores := {
		Action.PATROL: 10.0, # Baseline
		Action.ATTACK: 0.0,
		Action.TAKE_COVER: 0.0,
		Action.RELOAD: 0.0,
		Action.RETREAT: 0.0
	}
	
	var health_pct := health.current / health.max_health
	var ammo_pct := 1.0
	var w = weapons.current()
	if w:
		ammo_pct = float(weapons.mag()) / float(max(1, w.mag_size))
		
	var has_los := can_see_target()
	
	if target != null:
		if has_los:
			scores[Action.ATTACK] += 40.0
			
			if ammo_pct > 0.0:
				scores[Action.ATTACK] += 30.0 * ammo_pct
			else:
				scores[Action.RELOAD] += 100.0
				scores[Action.TAKE_COVER] += 80.0
				
			if health_pct < 0.4:
				scores[Action.TAKE_COVER] += (0.4 - health_pct) * 200.0
				scores[Action.RETREAT] += (0.4 - health_pct) * 150.0
				
			# If full health but reloading, cover is good
			if weapons.is_reloading:
				scores[Action.TAKE_COVER] += 60.0
		else:
			if _time_since_seen < LOSE_TARGET_TIME * 2.0:
				scores[Action.ATTACK] += 30.0 # Keep chasing
			elif ammo_pct <= 0.0:
				scores[Action.RELOAD] += 80.0
				
		if weapons.is_reloading:
			scores[Action.RELOAD] = 1000.0 # Lock into reload
	
	# Fallback if we somehow have 0 mag and aren't reloading yet
	if w and weapons.mag() <= 0 and weapons.reserve() > 0 and not weapons.is_reloading:
		scores[Action.RELOAD] += 100.0

	# Find highest scoring action
	var best_action = Action.PATROL
	var best_score = scores[Action.PATROL]
	for a in scores:
		if scores[a] > best_score:
			best_score = scores[a]
			best_action = a
			
	if best_action != current_action:
		_start_action(best_action)


func _start_action(new_action: Action) -> void:
	current_action = new_action
	_repath_timer = 0.0 # force repath
	if new_action == Action.TAKE_COVER:
		_cover_pos = _find_cover_position()
	elif new_action == Action.RELOAD:
		if not weapons.is_reloading and weapons.mag() <= 0 and weapons.reserve() > 0:
			weapons.start_reload()


func _execute_action(delta: float) -> void:
	match current_action:
		Action.ATTACK:
			_do_attack(delta)
		Action.TAKE_COVER:
			_do_take_cover(delta)
		Action.RELOAD:
			_do_reload(delta)
		Action.RETREAT:
			_do_retreat(delta)
		_:
			_do_patrol(delta)


# ------------------------------------------------------------------ perception

func can_see_target() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_dead") and target.is_dead():
		return false

	var eye := aim_pivot.global_position
	var target_point: Vector3 = target.global_position + CHEST_OFFSET
	var to_target := target_point - eye
	var distance := to_target.length()
	if distance > VIEW_RANGE:
		return false

	var facing := -global_transform.basis.z
	if facing.angle_to(to_target.normalized()) > VIEW_ANGLE * 0.5:
		return false

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, target_point, 1)
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _update_perception(delta: float) -> void:
	if can_see_target():
		if _time_since_seen > 0.35:
			_reaction_timer = float(_profile.get("reaction_time", 0.3))
			_error_scale = 1.0
		_time_since_seen = 0.0
		_last_seen_pos = target.global_position
		_error_scale = maxf(_error_scale - float(_profile.get("accuracy_recovery", 1.0)) * delta, 0.25)
	else:
		_time_since_seen += delta
	_reaction_timer = maxf(_reaction_timer - delta, 0.0)


# ---------------------------------------------------------------- behaviours

func _do_attack(delta: float) -> void:
	if target == null: return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	# If we can't see them, chase to last known pos
	if _time_since_seen > 0.1:
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = 0.4
			nav.target_position = _last_seen_pos
		_follow_path(CHASE_SPEED, delta)
		return

	# In combat line of sight
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.7, 1.6)
		if randf() < float(_profile.get("strafe_chance", 0.5)):
			_strafe_dir = 1.0 if randf() < 0.5 else -1.0
		else:
			_strafe_dir = 0.0

	var forward := to_target.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var approach := 0.0
	if distance > _preferred_range * 1.25:
		approach = 1.0
	elif distance < _preferred_range * 0.6:
		approach = -1.0

	var desired := (forward * approach + right * _strafe_dir * 0.85)
	_move_along(desired, WALK_SPEED if approach == 0.0 else CHASE_SPEED, delta)
	_try_shoot(delta, distance)


func _do_take_cover(delta: float) -> void:
	if _cover_pos != Vector3.ZERO:
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = 0.5
			nav.target_position = _cover_pos
		_follow_path(CHASE_SPEED, delta)
	else:
		_do_retreat(delta)
		

func _do_retreat(delta: float) -> void:
	if target != null:
		var away := (global_position - target.global_position)
		away.y = 0.0
		_move_along(away.normalized(), CHASE_SPEED, delta)
	else:
		_move_along(Vector3.ZERO, WALK_SPEED, delta)


func _do_reload(delta: float) -> void:
	# Try to break contact
	_do_retreat(delta)


func _do_patrol(delta: float) -> void:
	_repath_timer -= delta
	if _repath_timer <= 0.0 or nav.is_navigation_finished():
		_repath_timer = randf_range(2.5, 4.5)
		nav.target_position = _random_patrol_point()
	_follow_path(WALK_SPEED, delta)


func _find_cover_position() -> Vector3:
	if target == null: return global_position
	
	var space = get_world_3d().direct_space_state
	var best_pos := global_position
	var best_score := -1.0
	
	# Sample random points around us
	for i in range(12):
		var angle = randf() * TAU
		var radius = randf_range(8.0, 20.0)
		var test_pos = global_position + Vector3(cos(angle)*radius, 1.0, sin(angle)*radius)
		
		# Check if point is behind cover relative to player
		var query = PhysicsRayQueryParameters3D.create(test_pos, target.global_position + CHEST_OFFSET, 1)
		query.exclude = [get_rid()]
		var hit = space.intersect_ray(query)
		
		if not hit.is_empty() and hit.collider != target:
			# It's behind cover! Score based on distance to us (prefer closer)
			var dist_to_cover = global_position.distance_to(test_pos)
			var score = 100.0 - dist_to_cover
			if score > best_score:
				best_score = score
				best_pos = test_pos
				
	if best_score < 0:
		# Fallback: run away
		var away = (global_position - target.global_position).normalized()
		best_pos = global_position + away * 15.0
		
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, best_pos)


func _random_patrol_point() -> Vector3:
	if target != null and is_instance_valid(target) and randf() < 0.7:
		var angle := randf() * TAU
		var radius := randf_range(5.0, 13.0)
		return target.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

	var a := randf() * TAU
	var r := randf_range(10.0, 24.0)
	return global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)


func _follow_path(speed: float, delta: float) -> void:
	if nav.is_navigation_finished():
		_move_along(Vector3.ZERO, speed, delta)
		return
	var next := nav.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	_move_along(dir.normalized(), speed, delta)


func _move_along(direction: Vector3, speed: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction.length_squared() > 0.01:
		horizontal = horizontal.move_toward(direction.normalized() * speed, ACCEL * speed * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, FRICTION * delta * speed)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

# ----------------------------------------------------------------- aim + fire

func _update_aim(delta: float) -> void:
	var desired: Vector3
	if target != null and _time_since_seen < LOSE_TARGET_TIME:
		desired = (target.global_position + CHEST_OFFSET) - aim_pivot.global_position
	elif velocity.length_squared() > 0.2:
		desired = Vector3(velocity.x, 0.0, velocity.z)
	else:
		desired = -global_transform.basis.z
	desired = desired.normalized()

	var err := float(_profile.get("aim_error", 2.4)) * _error_scale
	_aim_error = _aim_error.lerp(Vector3(
			randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), randf_range(-1.0, 1.0)
	) * deg_to_rad(err), delta * 3.0)

	var speed := float(_profile.get("aim_speed", 7.0))
	_aim_dir = _aim_dir.lerp((desired + _aim_error).normalized(), delta * speed).normalized()

	var flat := Vector3(_aim_dir.x, 0.0, _aim_dir.z)
	if flat.length_squared() > 0.001:
		var wanted_yaw := atan2(-flat.x, -flat.z)
		rotation.y = lerp_angle(rotation.y, wanted_yaw, delta * speed)
	aim_pivot.rotation.x = clampf(asin(clampf(_aim_dir.y, -1.0, 1.0)), -1.4, 1.4)


func _try_shoot(delta: float, distance: float) -> void:
	_burst_cooldown = maxf(_burst_cooldown - delta, 0.0)

	if _reaction_timer > 0.0 or _burst_cooldown > 0.0:
		return
	if not can_see_target():
		return

	var w := weapons.current()
	if w == null or distance > w.max_range:
		return

	var true_dir := ((target.global_position + CHEST_OFFSET) - aim_pivot.global_position).normalized()
	if _aim_dir.angle_to(true_dir) > deg_to_rad(9.0):
		return

	if _burst_left <= 0:
		_burst_left = int(_profile.get("burst_len", 6))
		if not w.automatic:
			_burst_left = 1

	if weapons.try_fire(aim_pivot.global_position, _aim_dir):
		_burst_left -= 1
		if _burst_left <= 0:
			_burst_cooldown = randf_range(0.25, 0.6) if w.automatic else w.seconds_per_shot()


func _on_reload_started(duration: float) -> void:
	animator.play_action(CharacterAnimator.Action.RELOAD, duration)

# -------------------------------------------------------------------- support

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 22.0) * delta
	else:
		velocity.y = 0.0


func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	if planar < 0.8:
		return
	_step_accum += planar * delta
	# Matches the player's stride length so both sets of footfalls read alike.
	if _step_accum >= 1.05:
		_step_accum = 0.0
		AudioManager.play_footstep(global_position, -6.0)

# --------------------------------------------------------------------- damage

func apply_damage(amount: float, attacker: Node, is_headshot: bool) -> void:
	health.take_damage(amount, attacker, is_headshot)
	if health.is_dead:
		return
	animator.play_action(CharacterAnimator.Action.HIT, 0.2)
	if attacker is Node3D and _time_since_seen > LOSE_TARGET_TIME:
		_last_seen_pos = (attacker as Node3D).global_position
		_time_since_seen = LOSE_TARGET_TIME - 0.1
		_reaction_timer = float(_profile.get("reaction_time", 0.3)) * 1.5


func is_dead() -> bool:
	return health.is_dead


func _on_died(attacker: Node) -> void:
	current_action = Action.DEAD
	animator.die()
	AudioManager.play_3d("death", global_position, -3.0, 0.05, 50.0)
	died.emit(attacker)


func respawn(at: Transform3D) -> void:
	global_transform = at
	velocity = Vector3.ZERO
	current_action = Action.PATROL
	enabled = true
	_time_since_seen = 999.0
	_last_seen_pos = Vector3.ZERO
	_burst_left = 0
	_burst_cooldown = 0.0
	_error_scale = 1.0
	_aim_dir = -global_transform.basis.z
	health.armor = 50.0
	health.reset()
	weapons.refill()
	animator.revive()
	_profile = GameState.bot_profile()
	_pick_preferred_range()


func set_input_enabled(value: bool) -> void:
	enabled = value
