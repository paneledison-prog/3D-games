extends CharacterBody3D
class_name PlayerController
## First-person controller: movement, look, ADS, recoil, and the local player's
## bridge into WeaponSystem.

signal died(attacker: Node)
signal respawned()

# Tuned against the animation set: Rifle Run is authored at 2.89 m/s, and the
# animator clamps playback to 1.9x, so anything past ~5.5 m/s cannot be shown
# without the feet skating. Raising these means downloading a faster clip.
const WALK_SPEED := 4.2
const SPRINT_SPEED := 5.5
const CROUCH_SPEED := 1.9
const ACCEL_GROUND := 12.0
const ACCEL_AIR := 3.0
const FRICTION := 14.0
const JUMP_VELOCITY := 7.0

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.15
const STAND_EYE := 1.62
const CROUCH_EYE := 1.02
const CROUCH_LERP := 11.0

const PITCH_LIMIT := deg_to_rad(89.0)
const BASE_FOV := 78.0
const TP_FOV := 74.0
## Over-the-shoulder distance, and how far the camera tucks in while aiming.
const TP_SPRING := 2.1
const TP_SPRING_ADS := 1.25
## One Rifle Run cycle covers 2.12 m in two steps, so a footfall every ~1.05 m
## lines the audio up with the feet actually hitting the ground.
const FOOTSTEP_DISTANCE := 1.05

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var collision: CollisionShape3D = $Collision
@onready var head_box: Area3D = $HeadBox
@onready var weapons: WeaponSystem = $Head/Camera/WeaponSystem
@onready var muzzle: Marker3D = $Head/Camera/WeaponSystem/Muzzle
@onready var health: Health = $Health
@onready var animator: CharacterAnimator = $Animator
@onready var rig: CharacterRig = $Body
@onready var spring_arm: SpringArm3D = $Head/SpringArm
@onready var tp_camera: Camera3D = $Head/SpringArm/TPCamera

var input_enabled := true
var _yaw := 0.0
var _pitch := 0.0
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _crouching := false
var _sprinting := false
var _step_accum := 0.0
var _target_fov := BASE_FOV
var _capsule: CapsuleShape3D
## Third person draws the character and hides the viewmodel; first person does
## the opposite. Toggled with T.
var third_person := false


func _ready() -> void:
	add_to_group(&"player")
	head_box.set_meta("hit_zone", "head")
	_capsule = collision.shape as CapsuleShape3D

	# Build the chosen body first: the weapon socket and any AnimationPlayer
	# that ships with the model have to exist before the rest wires up.
	rig.build(GameState.player_character)
	if rig.animation_player != null:
		animator.bind_animation_player(rig.animation_player, rig.skeleton)
	animator.bind_humanoid(rig.humanoid)

	weapons.is_local_player = true
	weapons.setup(GameState.player_loadout, self, muzzle, get_tree().current_scene)
	weapons.fired.connect(_on_weapon_fired)
	weapons.weapon_changed.connect(_on_weapon_model_changed)
	var starting := weapons.current()
	if starting != null:
		rig.equip_model(starting)

	health.died.connect(_on_died)
	camera.fov = BASE_FOV
	_yaw = rotation.y

	_apply_view_mode()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and input_enabled \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens := GameState.mouse_sensitivity
		if weapons.is_aiming:
			var w := weapons.current()
			sens *= (w.ads_move_scale if w != null else 0.6)
		_yaw -= motion.relative.x * sens
		var dy := motion.relative.y * sens * (-1.0 if GameState.invert_y else 1.0)
		_pitch = clampf(_pitch - dy, -PITCH_LIMIT, PITCH_LIMIT)

	# The mouse is captured during play, so the wheel is the natural way to
	# flick between slots without taking a hand off the movement keys.
	if event is InputEventMouseButton and event.pressed and input_enabled:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			weapons.cycle(-1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			weapons.cycle(1)

	if event.is_action_pressed(&"toggle_view"):
		third_person = not third_person
		_apply_view_mode()

	if event.is_action_pressed(&"pause"):
		_toggle_mouse()


func _physics_process(delta: float) -> void:
	if health.is_dead:
		velocity = velocity.move_toward(Vector3.ZERO, FRICTION * delta)
		move_and_slide()
		animator.update(delta, 0.0, 0.0, 0.0, false, false, false, 0.0)
		return

	_update_stance(delta)
	_update_movement(delta)
	_update_look(delta)
	_update_weapons(delta)
	_update_footsteps(delta)

	var planar := Vector2(velocity.x, velocity.z).length()
	var local_vel := global_transform.basis.inverse() * velocity
	animator.update(delta, clampf(planar / SPRINT_SPEED, 0.0, 1.0),
			clampf(-local_vel.z / SPRINT_SPEED, -1.0, 1.0),
			clampf(local_vel.x / SPRINT_SPEED, -1.0, 1.0),
			_crouching, not is_on_floor(), weapons.is_aiming, planar)

## Point the right camera, and make the body and viewmodel agree with it.
func _apply_view_mode() -> void:
	if third_person:
		tp_camera.current = true
	else:
		camera.current = true

	# The owner's body is shadow-only in first person so it never fills the
	# lens; in third person it is the thing you are looking at.
	rig.set_shadows_only(not third_person)

	var view_model := weapons.get_node_or_null("ViewModel")
	if view_model != null:
		view_model.visible = not third_person


func active_camera() -> Camera3D:
	return tp_camera if third_person else camera


## Where the shot actually starts and which way it goes.
##
## In first person that is simply the camera. In third person the camera sits
## behind and to the side, so firing along it would send rounds from over the
## shoulder at an angle. Instead the crosshair is projected into the world and
## the shot is fired from the character toward that point, which is what makes
## the reticle agree with where bullets land.
func aim_ray() -> Array:
	if not third_person:
		return [camera.global_position, -camera.global_transform.basis.z]

	var cam_origin := tp_camera.global_position
	var cam_forward := -tp_camera.global_transform.basis.z
	var far_point := cam_origin + cam_forward * 500.0

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(cam_origin, far_point,
			WeaponSystem.HIT_MASK)
	query.collide_with_areas = true
	query.exclude = [get_rid(), head_box.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		far_point = hit.position

	var muzzle_origin := head.global_position
	return [muzzle_origin, (far_point - muzzle_origin).normalized()]

# ------------------------------------------------------------------- movement

func _input_vector() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


func _current_speed() -> float:
	var speed := WALK_SPEED
	if _crouching:
		speed = CROUCH_SPEED
	elif _sprinting:
		speed = SPRINT_SPEED
	if weapons.is_aiming:
		var w := weapons.current()
		speed *= (w.ads_move_scale if w != null else 0.6)
	return speed


func _update_stance(delta: float) -> void:
	var want_crouch := input_enabled and Input.is_action_pressed(&"crouch")
	# Do not stand up into geometry.
	if _crouching and not want_crouch and _blocked_above():
		want_crouch = true
	_crouching = want_crouch

	var target_h := CROUCH_HEIGHT if _crouching else STAND_HEIGHT
	var target_eye := CROUCH_EYE if _crouching else STAND_EYE
	_capsule.height = lerpf(_capsule.height, target_h, delta * CROUCH_LERP)
	collision.position.y = _capsule.height * 0.5
	head.position.y = lerpf(head.position.y, target_eye, delta * CROUCH_LERP)
	head_box.position.y = head.position.y + 0.06


func _blocked_above() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * CROUCH_HEIGHT
	var to := global_position + Vector3.UP * (STAND_HEIGHT + 0.1)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


func _update_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 22.0) * delta
	elif input_enabled and Input.is_action_just_pressed(&"jump"):
		velocity.y = JUMP_VELOCITY
		AudioManager.play_3d("jump", global_position, -12.0, 0.1, 20.0)

	var input := _input_vector()
	var dir := (global_transform.basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	dir = dir.normalized()

	# Sprint only applies to genuine forward movement, and never while aiming.
	_sprinting = input_enabled and Input.is_action_pressed(&"sprint") \
			and input.y < -0.3 and not weapons.is_aiming and not _crouching

	var speed := _current_speed()
	var accel := ACCEL_GROUND if is_on_floor() else ACCEL_AIR
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if dir.length_squared() > 0.01:
		horizontal = horizontal.move_toward(dir * speed, accel * speed * delta)
	elif is_on_floor():
		horizontal = horizontal.move_toward(Vector3.ZERO, FRICTION * delta * speed)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var was_airborne := not is_on_floor()
	move_and_slide()
	if was_airborne and is_on_floor():
		AudioManager.play_3d("land", global_position, -10.0, 0.1, 25.0)


func _update_look(delta: float) -> void:
	var w := weapons.current()
	var recovery: float = (w.recoil_recovery if w != null else 8.0)
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, delta * recovery)
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, delta * recovery)

	rotation.y = _yaw + _recoil_yaw
	head.rotation.x = clampf(_pitch + _recoil_pitch, -PITCH_LIMIT, PITCH_LIMIT)

	if third_person:
		tp_camera.fov = lerpf(tp_camera.fov, _target_fov * (TP_FOV / BASE_FOV),
				delta * 12.0)
		# Aiming pulls the camera in over the shoulder rather than zooming.
		spring_arm.spring_length = lerpf(spring_arm.spring_length,
				TP_SPRING_ADS if weapons.is_aiming else TP_SPRING, delta * 10.0)
	else:
		camera.fov = lerpf(camera.fov, _target_fov, delta * 12.0)

# -------------------------------------------------------------------- weapons

func _update_weapons(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	weapons.tick(delta, planar)

	if not input_enabled:
		weapons.is_aiming = false
		_target_fov = BASE_FOV
		return

	var w := weapons.current()
	weapons.is_aiming = Input.is_action_pressed(&"aim") and not _sprinting
	_target_fov = (w.ads_fov if (weapons.is_aiming and w != null) else BASE_FOV)

	if Input.is_action_just_pressed(&"reload"):
		weapons.start_reload()
		if weapons.is_reloading and w != null:
			animator.play_action(CharacterAnimator.Action.RELOAD, w.reload_time)

	if Input.is_action_just_pressed(&"weapon_next"):
		weapons.next_weapon()
	if Input.is_action_just_pressed(&"weapon_1"):
		weapons.switch_to(0)
	if Input.is_action_just_pressed(&"weapon_2"):
		weapons.switch_to(1)
	if Input.is_action_just_pressed(&"weapon_3"):
		weapons.switch_to(2)
	if Input.is_action_just_pressed(&"weapon_4"):
		weapons.switch_to(3)
	# V is a shortcut straight to the blade rather than a separate attack.
	if Input.is_action_just_pressed(&"melee"):
		weapons.switch_to(2)

	var wants_fire := Input.is_action_pressed(&"fire") if (w != null and w.automatic) \
			else Input.is_action_just_pressed(&"fire")
	if wants_fire and not _sprinting:
		var origin := camera.global_position
		var direction := -camera.global_transform.basis.z
		if weapons.try_fire(origin, direction):
			animator.play_action(CharacterAnimator.Action.FIRE, 0.12)


func _on_weapon_fired(_w: WeaponData, recoil_v: float, recoil_h: float) -> void:
	_recoil_pitch += deg_to_rad(recoil_v)
	_recoil_yaw += deg_to_rad(recoil_h)


## Keep the third-person body holding the same gun as the viewmodel, so the
## shadow and any killcam stay honest.
func _on_weapon_model_changed(weapon: WeaponData, _slot: int) -> void:
	rig.equip_model(weapon)

# ------------------------------------------------------------------ feedback

func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		_step_accum = 0.0
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	if planar < 0.8:
		_step_accum = 0.0
		return
	_step_accum += planar * delta
	var interval := FOOTSTEP_DISTANCE * (1.35 if _crouching else 1.0)
	if _step_accum >= interval:
		_step_accum = 0.0
		AudioManager.play_footstep(global_position, -10.0 if _crouching else -5.0)

# --------------------------------------------------------------------- damage

func apply_damage(amount: float, attacker: Node, is_headshot: bool) -> void:
	health.take_damage(amount, attacker, is_headshot)
	if not health.is_dead:
		animator.play_action(CharacterAnimator.Action.HIT, 0.25)


func is_dead() -> bool:
	return health.is_dead


func _on_died(attacker: Node) -> void:
	animator.die()
	weapons.is_aiming = false
	_target_fov = BASE_FOV
	AudioManager.play_2d("death", -4.0)
	died.emit(attacker)


func respawn(at: Transform3D) -> void:
	global_transform = at
	_yaw = at.basis.get_euler().y
	_pitch = 0.0
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	velocity = Vector3.ZERO
	health.armor = 50.0
	health.reset()
	weapons.refill()
	animator.revive()
	input_enabled = true
	respawned.emit()


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled


func _toggle_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			else Input.MOUSE_MODE_CAPTURED
