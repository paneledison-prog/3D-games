extends Object
class_name CombatFX
## Small code-built combat visuals. Built in script rather than as scenes so the
## effects stay in one place and need no art dependencies.

const TRACER_LIFETIME := 0.055
const IMPACT_LIFETIME := 0.28
const MUZZLE_LIFETIME := 0.045


## A thin fading line from the muzzle to the bullet's stopping point.
static func spawn_tracer(parent: Node, from: Vector3, to: Vector3,
		color := Color(1.0, 0.86, 0.55)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if from.distance_to(to) < 0.25:
		return

	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.disable_receive_shadows = true

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_set_color(Color(color.r, color.g, color.b, 0.0))
	mesh.surface_add_vertex(to - from)
	mesh.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = from

	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, TRACER_LIFETIME)
	tw.tween_callback(mi.queue_free)


## A brief sprite-less spark plus a fading point light at the impact site.
static func spawn_impact(parent: Node, position: Vector3, normal: Vector3,
		color := Color(1.0, 0.75, 0.4)) -> void:
	if parent == null or not parent.is_inside_tree():
		return

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 2.4
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = position + normal * 0.08

	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	sphere.radial_segments = 6
	sphere.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	puff.mesh = sphere
	puff.material_override = mat
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(puff)
	puff.global_position = position + normal * 0.05

	var tw := puff.create_tween()
	tw.set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, IMPACT_LIFETIME)
	tw.tween_property(mat, "albedo_color:a", 0.0, IMPACT_LIFETIME)
	tw.tween_property(puff, "scale", Vector3.ONE * 2.2, IMPACT_LIFETIME)
	tw.chain().tween_callback(light.queue_free)
	tw.tween_callback(puff.queue_free)


## Expanding flash plus a bright falling light, sized to the blast radius so
## what you see matches what actually damages you.
static func spawn_explosion(parent: Node, position: Vector3, radius: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.35)
	light.light_energy = 14.0
	light.omni_range = radius * 2.2
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = position

	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.78, 0.42, 0.95)
	ball.mesh = sphere
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ball)
	ball.global_position = position
	ball.scale = Vector3.ONE * 0.4

	var tw := ball.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 1.6, 0.34) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.42)
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.chain().tween_callback(light.queue_free)
	tw.tween_callback(ball.queue_free)


## Punchy one-frame muzzle light. Cheap, and it sells the shot in a dark arena.
static func flash_muzzle(muzzle: Node3D, scale := 1.0) -> void:
	if muzzle == null or not muzzle.is_inside_tree():
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.82, 0.5)
	light.light_energy = 3.2 * scale
	light.omni_range = 4.5 * scale
	light.shadow_enabled = false
	muzzle.add_child(light)

	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, MUZZLE_LIFETIME)
	tw.tween_callback(light.queue_free)
