extends RigidBody3D
class_name Grenade
## A thrown explosive. Arcs, bounces, and detonates on a fuse.
##
## Blast damage falls off with distance and is blocked by geometry, so cover
## actually protects you - otherwise a grenade anywhere in the arena would be a
## guaranteed kill through walls.

signal exploded(position: Vector3)

const BOUNCE_COOLDOWN := 0.12

var weapon: WeaponData
var thrower: Node3D

var _fuse := 2.6
var _blast_damage := 130.0
var _blast_radius := 7.0
var _bounce_timer := 0.0
var _done := false


func setup(p_weapon: WeaponData, p_thrower: Node3D, direction: Vector3) -> void:
	weapon = p_weapon
	thrower = p_thrower
	_fuse = weapon.fuse_time
	_blast_damage = weapon.blast_damage
	_blast_radius = weapon.blast_radius

	# A flat throw still needs some lift or it just skids along the floor.
	linear_velocity = direction.normalized() * weapon.throw_force \
			+ Vector3.UP * weapon.throw_arc
	angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0),
			randf_range(-8.0, 8.0))

	# Never collide with whoever threw it, or it detonates at their feet.
	if thrower is CollisionObject3D:
		add_collision_exception_with(thrower)
	for child in thrower.get_children():
		if child is CollisionObject3D:
			add_collision_exception_with(child)

	_build_visual()


## The thrown object looks like the weapon it came from, so the grenade in your
## hand and the one in the air are the same model.
func _build_visual() -> void:
	var path := weapon.resolve_model_path()
	if not path.is_empty():
		var packed: PackedScene = load(path)
		if packed != null:
			var visual := packed.instantiate() as Node3D
			if visual != null:
				visual.scale = Vector3.ONE * maxf(weapon.model_scale, 0.01)
				add_child(visual)
				return

	# No model yet: a small dark sphere still reads as a thrown object.
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.2, 0.14)
	mat.roughness = 0.6
	mi.material_override = mat
	add_child(mi)


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_bounce_timer = maxf(_bounce_timer - delta, 0.0)
	_fuse -= delta
	if _fuse <= 0.0:
		explode()


func _on_body_entered(_body: Node) -> void:
	if _done or _bounce_timer > 0.0:
		return
	_bounce_timer = BOUNCE_COOLDOWN
	AudioManager.play_3d("grenade_bounce", global_position, -8.0, 0.12, 30.0)


func explode() -> void:
	if _done:
		return
	_done = true

	var origin := global_position
	var parent := get_parent()

	AudioManager.play_3d("explosion", origin, 2.0, 0.05, 120.0)
	CombatFX.spawn_explosion(parent, origin, _blast_radius)

	for victim in _characters_in_range(origin):
		var target_point: Vector3 = victim.global_position + Vector3(0.0, 1.0, 0.0)
		var distance := origin.distance_to(target_point)
		if distance > _blast_radius:
			continue
		if not _has_line_of_sight(origin, target_point, victim):
			continue

		# Linear falloff to zero at the edge of the blast.
		var scale := 1.0 - clampf(distance / _blast_radius, 0.0, 1.0)
		var damage := _blast_damage * scale
		if damage > 1.0 and victim.has_method("apply_damage"):
			victim.apply_damage(damage, thrower, false)

	exploded.emit(origin)
	queue_free()


func _characters_in_range(origin: Vector3) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for group in [&"player", &"bot"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D and node.global_position.distance_to(origin) <= _blast_radius + 2.0:
				out.append(node as Node3D)
	return out


## Walls stop the blast. Only world geometry is tested, so two fighters never
## shield each other.
func _has_line_of_sight(from: Vector3, to: Vector3, victim: Node) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	if victim is CollisionObject3D:
		query.exclude = query.exclude + [(victim as CollisionObject3D).get_rid()]
	return space.intersect_ray(query).is_empty()
