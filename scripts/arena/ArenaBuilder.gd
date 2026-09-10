@tool
extends Node3D
## Builds the Lone Wolf greybox arena from a data table.
##
## The layout is mirrored across the X axis so neither duellist gets a better
## side, which matters a lot in a 1v1. Geometry is generated under NavRegion so
## Main can bake navigation from it at runtime.

const ARENA_SIZE := 52.0
const WALL_HEIGHT := 7.0
const WALL_THICK := 1.0

## Half the arena, mirrored to produce the other half.
## Each entry: position (x, y, z), size (x, y, z).
const COVER_HALF := [
	# --- long cover flanking the centre lane ---
	[Vector3(-6.0, 1.2, 0.0), Vector3(1.2, 2.4, 9.0)],
	[Vector3(-13.0, 1.5, -8.0), Vector3(5.0, 3.0, 1.2)],
	[Vector3(-13.0, 1.5, 8.0), Vector3(5.0, 3.0, 1.2)],
	# --- corner bunkers ---
	[Vector3(-19.0, 2.0, -18.0), Vector3(6.0, 4.0, 1.2)],
	[Vector3(-18.0, 2.0, -19.5), Vector3(1.2, 4.0, 4.0)],
	[Vector3(-19.0, 2.0, 18.0), Vector3(6.0, 4.0, 1.2)],
	[Vector3(-18.0, 2.0, 19.5), Vector3(1.2, 4.0, 4.0)],
	# --- scattered crates (chest-high, vaultable sight blockers) ---
	[Vector3(-10.0, 0.6, -16.0), Vector3(2.2, 1.2, 2.2)],
	[Vector3(-10.0, 1.4, -16.0), Vector3(1.2, 0.4, 1.2)],
	[Vector3(-10.0, 0.6, 16.0), Vector3(2.2, 1.2, 2.2)],
	[Vector3(-21.0, 0.75, 0.0), Vector3(3.0, 1.5, 3.0)],
	[Vector3(-14.5, 0.6, -2.5), Vector3(1.6, 1.2, 1.6)],
	[Vector3(-14.5, 0.6, 2.5), Vector3(1.6, 1.2, 1.6)],
]

## Centre structure, not mirrored (it is already symmetric).
const CENTRE = [
	[Vector3(0.0, 2.25, 0.0), Vector3(7.0, 4.5, 7.0)],
	[Vector3(0.0, 0.9, -6.0), Vector3(4.0, 1.8, 2.0)],
	[Vector3(0.0, 0.9, 6.0), Vector3(4.0, 1.8, 2.0)],
	[Vector3(0.0, 1.2, -13.0), Vector3(1.2, 2.4, 4.0)],
	[Vector3(0.0, 1.2, 13.0), Vector3(1.2, 2.4, 4.0)],
]

## Duellists always start far apart and out of each other's line of sight.
const SPAWN_POINTS := [
	Vector3(-22.0, 0.1, -20.0),
	Vector3(-23.0, 0.1, 0.0),
	Vector3(-22.0, 0.1, 20.0),
	Vector3(22.0, 0.1, -20.0),
	Vector3(23.0, 0.1, 0.0),
	Vector3(22.0, 0.1, 20.0),
]

var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_cover: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_clear_generated()
	_build_floor()
	_build_walls()
	_build_cover()
	_build_spawns()


func _make_materials() -> void:
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.16, 0.17, 0.19)
	_mat_floor.roughness = 0.95

	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.22, 0.235, 0.26)
	_mat_wall.roughness = 0.9

	_mat_cover = StandardMaterial3D.new()
	_mat_cover.albedo_color = Color(0.30, 0.34, 0.38)
	_mat_cover.roughness = 0.85


func _nav_region() -> Node3D:
	var region := get_node_or_null("NavRegion")
	return region if region != null else self


func _clear_generated() -> void:
	for child in _nav_region().get_children():
		if child.name.begins_with("Gen_"):
			child.free()
	var spawns := get_node_or_null("Spawns")
	if spawns != null:
		for child in spawns.get_children():
			child.free()


func _build_floor() -> void:
	_add_box("Gen_Floor", Vector3(0.0, -0.5, 0.0),
			Vector3(ARENA_SIZE, 1.0, ARENA_SIZE), _mat_floor, "concrete")


func _build_walls() -> void:
	var half := ARENA_SIZE * 0.5
	var h := WALL_HEIGHT
	var t := WALL_THICK
	_add_box("Gen_WallN", Vector3(0.0, h * 0.5, -half),
			Vector3(ARENA_SIZE, h, t), _mat_wall, "concrete")
	_add_box("Gen_WallS", Vector3(0.0, h * 0.5, half),
			Vector3(ARENA_SIZE, h, t), _mat_wall, "concrete")
	_add_box("Gen_WallW", Vector3(-half, h * 0.5, 0.0),
			Vector3(t, h, ARENA_SIZE), _mat_wall, "concrete")
	_add_box("Gen_WallE", Vector3(half, h * 0.5, 0.0),
			Vector3(t, h, ARENA_SIZE), _mat_wall, "concrete")


func _build_cover() -> void:
	var index := 0
	for entry in COVER_HALF:
		var pos: Vector3 = entry[0]
		var size: Vector3 = entry[1]
		_add_box("Gen_Cover_%dA" % index, pos, size, _mat_cover, "metal")
		# Mirror across X for the opposing half.
		_add_box("Gen_Cover_%dB" % index,
				Vector3(-pos.x, pos.y, pos.z), size, _mat_cover, "metal")
		index += 1

	for entry in CENTRE:
		_add_box("Gen_Centre_%d" % index, entry[0], entry[1], _mat_cover, "metal")
		index += 1


func _build_spawns() -> void:
	var parent := get_node_or_null("Spawns")
	if parent == null:
		parent = Node3D.new()
		parent.name = "Spawns"
		add_child(parent)
		if Engine.is_editor_hint():
			parent.owner = self

	for i in SPAWN_POINTS.size():
		var marker := Marker3D.new()
		marker.name = "Spawn%d" % (i + 1)
		marker.position = SPAWN_POINTS[i]
		marker.add_to_group(&"spawn_point")
		parent.add_child(marker)
		if Engine.is_editor_hint():
			marker.owner = self


## One static box: collision, mesh and surface tag in a single node.
func _add_box(box_name: String, origin: Vector3, extents: Vector3,
		material: StandardMaterial3D, surface: String) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = origin
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", surface)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extents
	shape.shape = box
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = extents
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	_nav_region().add_child(body)
	if Engine.is_editor_hint():
		body.owner = self
		shape.owner = self
		mesh_instance.owner = self
