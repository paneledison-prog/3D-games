extends CanvasLayer
class_name HUD
## Combat HUD. Built entirely in code so there is no fragile .tscn to keep in
## sync with the script.

const ACCENT := Color(0.35, 0.95, 0.75)
const DANGER := Color(0.95, 0.28, 0.28)
const DIM := Color(1, 1, 1, 0.55)

var crosshair: Crosshair
var _score_label: Label
var _round_label: Label
var _timer_label: Label
var _health_bar: ProgressBar
var _armor_bar: ProgressBar
var _health_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _reload_label: Label
var _announce_label: Label
var _vignette: ColorRect
var _state_label: Label

var _player: PlayerController
var _round_manager: RoundManager
var _announce_timer := 0.0
var _vignette_alpha := 0.0


func _ready() -> void:
	layer = 10
	_build()


func bind(player: PlayerController, manager: RoundManager) -> void:
	_player = player
	_round_manager = manager

	player.health.health_changed.connect(_on_health_changed)
	player.health.damaged.connect(_on_damaged)
	player.weapons.ammo_changed.connect(_on_ammo_changed)
	player.weapons.weapon_changed.connect(_on_weapon_changed)
	player.weapons.hit_confirmed.connect(_on_hit_confirmed)
	player.weapons.reload_started.connect(_on_reload_started)
	player.weapons.reload_finished.connect(_on_reload_finished)

	manager.announce.connect(show_announcement)
	manager.countdown.connect(_on_countdown)
	manager.phase_changed.connect(_on_phase_changed)

	GameState.score_changed.connect(_on_score_changed)
	_on_score_changed(GameState.player_score, GameState.bot_score)
	_on_health_changed(player.health.current, player.health.max_health)

	var w := player.weapons.current()
	if w != null:
		_on_weapon_changed(w, 0)
		_on_ammo_changed(player.weapons.mag(), player.weapons.reserve())


func _process(delta: float) -> void:
	if _player != null and is_instance_valid(_player):
		crosshair.spread_degrees = _player.weapons.base_spread()
		crosshair.is_aiming = _player.weapons.is_aiming
		_armor_bar.value = _player.health.armor

	if _round_manager != null and _round_manager.phase == RoundManager.Phase.LIVE:
		var t: float = _round_manager.time_left
		_timer_label.text = "%d:%02d" % [floori(t / 60.0), int(t) % 60]
		_timer_label.modulate = DANGER if t < 15.0 else Color.WHITE

	if _announce_timer > 0.0:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_label.text = ""

	if _vignette_alpha > 0.0:
		_vignette_alpha = maxf(_vignette_alpha - delta * 1.8, 0.0)
		_vignette.color = Color(DANGER.r, DANGER.g, DANGER.b, _vignette_alpha * 0.35)

# ----------------------------------------------------------------------- build

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(DANGER.r, DANGER.g, DANGER.b, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vignette)

	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(crosshair)

	# --- top centre: score, round, timer --------------------------------
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-140, 18)
	top.custom_minimum_size = Vector2(280, 0)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	_score_label = _make_label("0  -  0", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_score_label)

	var sub := HBoxContainer.new()
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_theme_constant_override("separation", 14)
	top.add_child(sub)
	_round_label = _make_label("ROUND 1", 14, DIM)
	_timer_label = _make_label("1:30", 14, Color.WHITE)
	sub.add_child(_round_label)
	sub.add_child(_timer_label)

	_state_label = _make_label("FIRST TO %d" % GameState.ROUNDS_TO_WIN, 11,
			Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_state_label)

	# --- centre: announcements -------------------------------------------
	_announce_label = _make_label("", 54, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_announce_label.set_anchors_preset(Control.PRESET_CENTER)
	_announce_label.position = Vector2(-400, -170)
	_announce_label.custom_minimum_size = Vector2(800, 70)
	root.add_child(_announce_label)

	# --- bottom left: health + armor -------------------------------------
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.position = Vector2(36, -110)
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)

	_health_label = _make_label("100", 30, Color.WHITE)
	left.add_child(_health_label)

	_health_bar = _make_bar(100.0, ACCENT, 14)
	left.add_child(_health_bar)

	_armor_bar = _make_bar(50.0, Color(0.45, 0.72, 1.0), 6)
	left.add_child(_armor_bar)

	# --- bottom right: ammo ----------------------------------------------
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.position = Vector2(-300, -110)
	right.custom_minimum_size = Vector2(264, 0)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(right)

	_weapon_label = _make_label("FALCON AR", 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_weapon_label)

	_ammo_label = _make_label("30 / 120", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_ammo_label)

	_reload_label = _make_label("", 15, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_reload_label)


func _make_label(text: String, size_px: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_bar(maximum: float, color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = maximum
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(260, height)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)

	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.corner_radius_top_left = 2
	fg.corner_radius_top_right = 2
	fg.corner_radius_bottom_left = 2
	fg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fg)
	return bar

# ---------------------------------------------------------------------- events

func show_announcement(text: String, duration: float) -> void:
	_announce_label.text = text
	_announce_timer = duration


func _on_countdown(seconds_left: int) -> void:
	_announce_label.text = str(seconds_left)
	_announce_timer = 1.0


func _on_phase_changed(phase: String) -> void:
	match phase:
		"warmup":
			_state_label.text = "GET READY"
		"live":
			_state_label.text = "FIRST TO %d" % GameState.ROUNDS_TO_WIN
		"round_end":
			_state_label.text = ""
		"match_end":
			_state_label.text = ""


func _on_score_changed(player_score: int, bot_score: int) -> void:
	_score_label.text = "%d  -  %d" % [player_score, bot_score]
	_round_label.text = "ROUND %d" % maxi(GameState.round_number, 1)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = str(int(ceil(current)))
	_health_label.modulate = DANGER if current <= 30.0 else Color.WHITE


func _on_damaged(_amount: float, _attacker: Node, _headshot: bool) -> void:
	_vignette_alpha = 1.0


func _on_ammo_changed(mag: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [mag, reserve]
	_ammo_label.modulate = DANGER if mag == 0 else (
			Color(1.0, 0.8, 0.35) if mag <= 5 else Color.WHITE)


func _on_weapon_changed(weapon: WeaponData, _slot: int) -> void:
	_weapon_label.text = weapon.display_name.to_upper()


func _on_hit_confirmed(headshot: bool) -> void:
	crosshair.flash_hit(headshot)


func _on_reload_started(_duration: float) -> void:
	_reload_label.text = "RELOADING"


func _on_reload_finished() -> void:
	_reload_label.text = ""
