extends Control
## Pre-match screen: pick difficulty and a primary weapon, then drop in.
## Built in code for the same reason as the HUD - one file, nothing to desync.

const GAME_SCENE := "res://scenes/main/Main.tscn"
const ACCENT := Color(0.35, 0.95, 0.75)

const PRIMARIES := [
	["ar_falcon", "FALCON AR", "Balanced 620 rpm rifle. Forgiving at every range."],
	["smg_viper", "VIPER SMG", "900 rpm shredder. Own the close corners."],
	["shotgun_breaker", "BREAKER 12G", "Nine pellets. Lethal inside six metres."],
	["sniper_specter", "SPECTER BOLT", "One shot, one round. Punishes a still target."],
]

var _difficulty := GameState.Difficulty.VETERAN
var _primary := 0
var _character := 0

var _difficulty_label: Label
var _weapon_label: Label
var _weapon_desc: Label
var _char_label: Label
var _char_desc: Label
var _char_status: Label
var _characters: Array[CharacterProfile] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_characters = CharacterRig.all_profiles()
	# Start on whatever the player picked last.
	for i in _characters.size():
		if _characters[i].id == GameState.player_character:
			_character = i
			break
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.055, 0.07, 0.09)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.position = Vector2(-260, -320)
	root.custom_minimum_size = Vector2(520, 0)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	root.add_child(_label("LONE WOLF", 66, ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(_label("1 v 1  ·  FIRST TO %d ROUNDS" % GameState.ROUNDS_TO_WIN,
			15, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(_spacer(26))

	# --- difficulty -------------------------------------------------------
	root.add_child(_label("OPPONENT", 13, Color(1, 1, 1, 0.4)))
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	root.add_child(diff_row)
	for i in 3:
		var b := _button(["ROOKIE", "VETERAN", "ELITE"][i])
		b.custom_minimum_size = Vector2(168, 42)
		b.pressed.connect(_on_difficulty.bind(i))
		diff_row.add_child(b)
	_difficulty_label = _label("", 13, ACCENT)
	root.add_child(_difficulty_label)
	root.add_child(_spacer(18))

	# --- character --------------------------------------------------------
	root.add_child(_label("CHARACTER", 13, Color(1, 1, 1, 0.4)))
	var char_row := HBoxContainer.new()
	char_row.add_theme_constant_override("separation", 8)
	root.add_child(char_row)

	var char_prev := _button("<")
	char_prev.custom_minimum_size = Vector2(52, 46)
	char_prev.pressed.connect(_cycle_character.bind(-1))
	char_row.add_child(char_prev)

	_char_label = _label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_char_label.custom_minimum_size = Vector2(400, 46)
	_char_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	char_row.add_child(_char_label)

	var char_next := _button(">")
	char_next.custom_minimum_size = Vector2(52, 46)
	char_next.pressed.connect(_cycle_character.bind(1))
	char_row.add_child(char_next)

	_char_desc = _label("", 13, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	_char_desc.custom_minimum_size = Vector2(520, 22)
	root.add_child(_char_desc)

	# Tells you at a glance whether the Mixamo download actually landed.
	_char_status = _label("", 12, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
	_char_status.custom_minimum_size = Vector2(520, 18)
	root.add_child(_char_status)
	root.add_child(_spacer(18))

	# --- primary weapon ---------------------------------------------------
	root.add_child(_label("PRIMARY", 13, Color(1, 1, 1, 0.4)))
	var wep_row := HBoxContainer.new()
	wep_row.add_theme_constant_override("separation", 8)
	root.add_child(wep_row)

	var prev := _button("<")
	prev.custom_minimum_size = Vector2(52, 46)
	prev.pressed.connect(_cycle_weapon.bind(-1))
	wep_row.add_child(prev)

	_weapon_label = _label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_weapon_label.custom_minimum_size = Vector2(400, 46)
	_weapon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wep_row.add_child(_weapon_label)

	var next := _button(">")
	next.custom_minimum_size = Vector2(52, 46)
	next.pressed.connect(_cycle_weapon.bind(1))
	wep_row.add_child(next)

	_weapon_desc = _label("", 13, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	_weapon_desc.custom_minimum_size = Vector2(520, 22)
	root.add_child(_weapon_desc)
	root.add_child(_label("Secondary: Talon .45 (press 2)", 12, Color(1, 1, 1, 0.28),
			HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(_spacer(26))

	# --- actions ----------------------------------------------------------
	var play := _button("DEPLOY")
	play.custom_minimum_size = Vector2(520, 58)
	play.add_theme_font_size_override("font_size", 22)
	play.pressed.connect(_on_play)
	root.add_child(play)

	var quit := _button("QUIT")
	quit.custom_minimum_size = Vector2(520, 38)
	quit.pressed.connect(_on_quit)
	root.add_child(quit)

	root.add_child(_spacer(18))
	root.add_child(_label(
			"WASD move  ·  SHIFT sprint  ·  CTRL crouch  ·  RMB aim  ·  R reload  ·  Q swap",
			12, Color(1, 1, 1, 0.25), HORIZONTAL_ALIGNMENT_CENTER))


func _refresh() -> void:
	_difficulty_label.text = {
		GameState.Difficulty.ROOKIE: "Slow to react, sprays wide.",
		GameState.Difficulty.VETERAN: "Reads angles, trades evenly.",
		GameState.Difficulty.ELITE: "Fast reactions, tight bursts, strafes hard.",
	}[_difficulty]
	_weapon_label.text = PRIMARIES[_primary][1]
	_weapon_desc.text = PRIMARIES[_primary][2]

	if _characters.is_empty():
		_char_label.text = "DEFAULT"
		_char_desc.text = "No character profiles found."
		_char_status.text = ""
		return

	var profile := _characters[_character]
	_char_label.text = profile.display_name.to_upper()
	_char_label.add_theme_color_override("font_color", profile.accent_color)
	_char_desc.text = profile.description

	if profile.has_model():
		_char_status.text = "model loaded"
		_char_status.add_theme_color_override("font_color", ACCENT)
	else:
		_char_status.text = "placeholder - drop %s into assets/mixamo/characters/" \
				% profile.model_path.get_file()
		_char_status.add_theme_color_override("font_color", Color(1, 0.75, 0.35, 0.75))


func _cycle_character(step: int) -> void:
	if _characters.is_empty():
		return
	AudioManager.play_2d("ui_click", -8.0)
	_character = wrapi(_character + step, 0, _characters.size())
	_refresh()


func _on_difficulty(index: int) -> void:
	AudioManager.play_2d("ui_click", -8.0)
	_difficulty = index as GameState.Difficulty
	_refresh()


func _cycle_weapon(step: int) -> void:
	AudioManager.play_2d("ui_click", -8.0)
	_primary = wrapi(_primary + step, 0, PRIMARIES.size())
	_refresh()


func _on_play() -> void:
	AudioManager.play_2d("ui_click", -4.0)
	GameState.difficulty = _difficulty
	var kit: Array[String] = [PRIMARIES[_primary][0], "pistol_talon",
			"knife_bayonet", "grenade_frag"]
	GameState.player_loadout = kit.duplicate()
	# The bot mirrors the player's primary so every duel is a fair mirror match.
	GameState.bot_loadout = kit.duplicate()

	if not _characters.is_empty():
		GameState.player_character = _characters[_character].id
		# Give the opponent a different body so the two are easy to tell apart
		# mid-fight. Every model is height-normalised, so this is purely visual.
		var opponent := (_character + 1) % _characters.size()
		GameState.bot_character = _characters[opponent].id
	GameState.reset_match()
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit() -> void:
	get_tree().quit()

# -------------------------------------------------------------------- helpers

func _label(text: String, size_px: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.mouse_entered.connect(func(): AudioManager.play_2d("ui_hover", -16.0))

	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {
			"normal": Color(1, 1, 1, 0.06),
			"hover": Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18),
			"pressed": Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.32),
		}[state]
		sb.corner_radius_top_left = 3
		sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_left = 3
		sb.corner_radius_bottom_right = 3
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		b.add_theme_stylebox_override(state, sb)
	return b


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
