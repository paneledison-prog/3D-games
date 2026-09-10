extends Node3D
## Match bootstrap: bake navigation, wire the HUD, start the duel, and hand
## control back to the menu when the match resolves.

const MENU_SCENE := "res://scenes/main/MainMenu.tscn"

@onready var arena: Node3D = $Arena
@onready var player: PlayerController = $Player
@onready var bot: BotController = $Bot
@onready var round_manager: RoundManager = $RoundManager
@onready var hud: HUD = $HUD

var _pause_menu: Control


func _ready() -> void:
	await _bake_navigation()

	hud.bind(player, round_manager)
	round_manager.match_ended.connect(_on_match_ended)
	round_manager.begin_match()


## The arena's navmesh is baked at runtime so level geometry can be edited
## freely without anyone remembering to re-bake by hand.
func _bake_navigation() -> void:
	var region := arena.get_node_or_null("NavRegion") as NavigationRegion3D
	if region == null:
		push_warning("Main: arena has no NavRegion; the bot will steer directly.")
		return

	if region.navigation_mesh == null:
		var mesh := NavigationMesh.new()
		# Parse collision shapes, not visual meshes: reading meshes back off the
		# GPU at runtime stalls rendering.
		mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		# Every agent dimension is an exact multiple of the cell size, otherwise
		# the baker rounds them and warns.
		mesh.agent_radius = 0.5
		mesh.agent_height = 1.75
		mesh.agent_max_climb = 0.5
		mesh.cell_size = 0.25
		mesh.cell_height = 0.25
		region.navigation_mesh = mesh

	# Synchronous bake: the threaded default returns before the mesh exists.
	region.bake_navigation_mesh(false)
	# Give the navigation server a couple of frames to publish the new map.
	await get_tree().physics_frame
	await get_tree().physics_frame


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_toggle_pause()


func _toggle_pause() -> void:
	if _pause_menu != null:
		_close_pause()
		return

	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	layer.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-150, -110)
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 10)
	dim.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var resume := Button.new()
	resume.text = "RESUME"
	resume.custom_minimum_size = Vector2(300, 46)
	resume.pressed.connect(_close_pause)
	box.add_child(resume)

	var quit := Button.new()
	quit.text = "FORFEIT - BACK TO MENU"
	quit.custom_minimum_size = Vector2(300, 40)
	quit.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU_SCENE))
	box.add_child(quit)

	add_child(layer)
	_pause_menu = dim


func _close_pause() -> void:
	if _pause_menu == null:
		return
	_pause_menu.get_parent().queue_free()
	_pause_menu = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_match_ended(_player_won: bool) -> void:
	await get_tree().create_timer(1.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)
