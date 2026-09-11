extends Control
class_name WeaponBar
## Free Fire style weapon selector: a grid of slot tiles in the corner, each
## showing the weapon, its ammo, and whether it is the one in your hands.
##
## Icons are rendered once at startup from the real weapon models through a
## SubViewport, so a tile always depicts the gun you actually get rather than a
## hand-drawn approximation that drifts out of date.

signal slot_requested(slot: int)

const TILE := Vector2(112.0, 74.0)
const GAP := 6.0
const COLUMNS := 2
const ICON_SIZE := 128

const ACCENT := Color(0.35, 0.95, 0.75)
const IDLE_BG := Color(0.05, 0.06, 0.08, 0.72)
const ACTIVE_BG := Color(0.10, 0.16, 0.15, 0.88)

var _weapons: WeaponSystem
var _tiles: Array[Dictionary] = []
var _icons: Dictionary = {}
var _active := 0


func bind(weapons: WeaponSystem) -> void:
	_weapons = weapons
	_build_tiles()
	weapons.weapon_changed.connect(_on_weapon_changed)
	weapons.ammo_changed.connect(func(_m: int, _r: int): refresh())
	_active = weapons.slot
	refresh()
	_render_icons()


func _build_tiles() -> void:
	for child in get_children():
		child.queue_free()
	_tiles.clear()

	var count := _weapons.weapons.size()
	var rows := int(ceil(float(count) / COLUMNS))
	custom_minimum_size = Vector2(
			COLUMNS * TILE.x + (COLUMNS - 1) * GAP,
			rows * TILE.y + (rows - 1) * GAP)
	size = custom_minimum_size

	for i in count:
		var col := i % COLUMNS
		var row := i / COLUMNS
		var tile := _make_tile(i, Vector2(col * (TILE.x + GAP), row * (TILE.y + GAP)))
		_tiles.append(tile)


func _make_tile(index: int, pos: Vector2) -> Dictionary:
	var panel := Panel.new()
	panel.position = pos
	panel.size = TILE
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)

	# Clicking works whenever the cursor is free; keys 1-4 and the wheel cover
	# the mouse-captured case.
	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): slot_requested.emit(index))
	panel.add_child(button)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(6.0, 2.0)
	icon.size = Vector2(TILE.x - 12.0, TILE.y - 22.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)

	var slot_label := _label(str(index + 1), 11, Color(1, 1, 1, 0.4))
	slot_label.position = Vector2(7.0, 2.0)
	panel.add_child(slot_label)

	var name_label := _label("", 10, Color(1, 1, 1, 0.45))
	name_label.position = Vector2(7.0, TILE.y - 17.0)
	name_label.size = Vector2(TILE.x - 14.0, 14.0)
	panel.add_child(name_label)

	var ammo_label := _label("", 15, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	ammo_label.position = Vector2(TILE.x - 62.0, TILE.y - 20.0)
	ammo_label.size = Vector2(56.0, 18.0)
	panel.add_child(ammo_label)

	return {"panel": panel, "icon": icon, "ammo": ammo_label, "name": name_label}


func _label(text: String, size_px: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _on_weapon_changed(_weapon: WeaponData, slot: int) -> void:
	_active = slot
	refresh()


## Repaint every tile: ammo, name, and which one is live.
func refresh() -> void:
	if _weapons == null:
		return
	for i in _tiles.size():
		if i >= _weapons.weapons.size():
			continue
		var w: WeaponData = _weapons.weapons[i]
		var tile: Dictionary = _tiles[i]
		var is_active := i == _active

		tile["panel"].add_theme_stylebox_override("panel",
				_tile_style(is_active))
		tile["name"].text = w.display_name.to_upper()
		tile["name"].add_theme_color_override("font_color",
				ACCENT if is_active else Color(1, 1, 1, 0.45))

		var ammo: Label = tile["ammo"]
		if w.is_melee():
			# A blade never runs out, so it reads as infinite the way Free Fire
			# marks its fist slot.
			ammo.text = "∞"
			ammo.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		elif w.is_throwable():
			ammo.text = "x%d" % _weapons.mags[i]
			ammo.add_theme_color_override("font_color",
					Color(0.95, 0.28, 0.28) if _weapons.mags[i] == 0 else Color.WHITE)
		else:
			ammo.text = str(_weapons.mags[i])
			ammo.add_theme_color_override("font_color",
					Color(0.95, 0.28, 0.28) if _weapons.mags[i] == 0
					else Color.WHITE)

		tile["icon"].modulate = Color(1, 1, 1, 1.0 if is_active else 0.55)


func _tile_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACTIVE_BG if active else IDLE_BG
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(2 if active else 1)
	sb.border_color = ACCENT if active else Color(1, 1, 1, 0.12)
	return sb

# ------------------------------------------------------------------- icons

## Render each weapon model to a texture once, off-screen.
func _render_icons() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	add_child(viewport)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.15
	cam.position = Vector3(0.0, 0.0, 3.0)
	viewport.add_child(cam)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.90, 1.0)
	environment.ambient_light_energy = 2.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	viewport.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28.0, 138.0, 0.0)
	key.light_energy = 3.2
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20.0, -40.0, 0.0)
	fill.light_energy = 1.6
	viewport.add_child(fill)

	for i in _weapons.weapons.size():
		var w: WeaponData = _weapons.weapons[i]
		var holder := Node3D.new()
		viewport.add_child(holder)

		var model := _instance_model(w)
		if model != null:
			holder.add_child(model)
			# Show the weapon side-on, angled slightly, the way an inventory
			# icon reads best.
			holder.rotation_degrees = Vector3(12.0, 34.0, 0.0)
			_frame_model(model, w)

			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			if image != null and i < _tiles.size():
				_tiles[i]["icon"].texture = ImageTexture.create_from_image(image)

		holder.queue_free()
		await get_tree().process_frame

	viewport.queue_free()
	refresh()


func _instance_model(w: WeaponData) -> Node3D:
	var path := w.resolve_model_path()
	if path.is_empty():
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## Scale and centre the model so it fills the icon regardless of source size.
func _frame_model(model: Node3D, w: WeaponData) -> void:
	model.rotation_degrees = w.model_rotation
	var length := WeaponData.longest_axis(model)
	if length > 0.001:
		model.scale = Vector3.ONE * (1.75 / length)
	# Re-centre on the visual bounds rather than the model's own origin.
	var meshes: Array[MeshInstance3D] = []
	_gather(model, meshes)
	if meshes.is_empty():
		return
	var total := AABB()
	var first := true
	for mi in meshes:
		var box := mi.transform * mi.get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
	model.position = -total.get_center() * model.scale.x


func _gather(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_gather(child, out)
