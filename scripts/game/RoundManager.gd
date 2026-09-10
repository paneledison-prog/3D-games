extends Node
class_name RoundManager
## Runs the Lone Wolf duel: warmup countdown, live round, round end, repeat
## until someone reaches GameState.ROUNDS_TO_WIN.

signal phase_changed(phase: String)
signal countdown(seconds_left: int)
signal round_started(round_number: int)
signal round_ended(player_won: bool, player_score: int, bot_score: int)
signal match_ended(player_won: bool)
signal announce(text: String, duration: float)

enum Phase { IDLE, WARMUP, LIVE, ROUND_END, MATCH_END }

const ROUND_END_DELAY := 3.0
const MATCH_END_DELAY := 5.0

var phase: Phase = Phase.IDLE
var time_left := 0.0

var _player: PlayerController
var _bot: BotController
var _spawns: Array[Node3D] = []
var _timer := 0.0
var _last_beep := -1
var _round_winner_is_player := false


func _ready() -> void:
	set_process(false)


func begin_match() -> void:
	_player = _first_in_group(&"player") as PlayerController
	_bot = _first_in_group(&"bot") as BotController

	_spawns.clear()
	for node in get_tree().get_nodes_in_group(&"spawn_point"):
		if node is Node3D:
			_spawns.append(node as Node3D)

	if _player == null or _bot == null:
		push_error("RoundManager: player or bot missing from the scene.")
		return
	if _spawns.size() < 2:
		push_warning("RoundManager: fewer than 2 spawn points; using origin offsets.")

	if not _player.died.is_connected(_on_player_died):
		_player.died.connect(_on_player_died)
	if not _bot.died.is_connected(_on_bot_died):
		_bot.died.connect(_on_bot_died)

	GameState.reset_match()
	set_process(true)
	_start_round()


func _process(delta: float) -> void:
	_timer -= delta

	match phase:
		Phase.WARMUP:
			var whole := int(ceil(_timer))
			if whole != _last_beep and whole > 0:
				_last_beep = whole
				countdown.emit(whole)
				AudioManager.play_2d("countdown_beep", -6.0)
			if _timer <= 0.0:
				_go_live()

		Phase.LIVE:
			time_left = maxf(time_left - delta, 0.0)
			if time_left <= 0.0:
				# Timeout: whoever has more health takes the round.
				_finish_round(_player.health.current >= _bot.health.current, true)

		Phase.ROUND_END:
			if _timer <= 0.0:
				if GameState.match_over:
					_end_match()
				else:
					_start_round()

		Phase.MATCH_END:
			if _timer <= 0.0:
				set_process(false)
				match_ended.emit(GameState.player_score > GameState.bot_score)

		_:
			pass

# ----------------------------------------------------------------- transitions

func _start_round() -> void:
	GameState.round_number += 1
	_round_winner_is_player = false

	var pair := _pick_spawn_pair()
	_player.respawn(pair[0])
	_bot.respawn(pair[1])

	_player.set_input_enabled(false)
	_bot.set_input_enabled(false)

	phase = Phase.WARMUP
	_timer = GameState.WARMUP_TIME
	_last_beep = -1
	time_left = GameState.ROUND_TIME

	phase_changed.emit("warmup")
	round_started.emit(GameState.round_number)
	announce.emit("ROUND %d" % GameState.round_number, 1.6)


func _go_live() -> void:
	phase = Phase.LIVE
	_player.set_input_enabled(true)
	_bot.set_input_enabled(true)
	AudioManager.play_2d("countdown_go", -3.0)
	phase_changed.emit("live")
	announce.emit("FIGHT", 1.0)


func _finish_round(player_won: bool, by_timeout := false) -> void:
	if phase != Phase.LIVE:
		return

	phase = Phase.ROUND_END
	_round_winner_is_player = player_won
	_player.set_input_enabled(false)
	_bot.set_input_enabled(false)

	GameState.award_round(player_won)
	AudioManager.play_2d("round_win" if player_won else "round_lose", -5.0)

	var text := ""
	if by_timeout:
		text = "TIME - %s WINS" % ("YOU" if player_won else "OPPONENT")
	else:
		text = "ROUND WON" if player_won else "ROUND LOST"

	_timer = ROUND_END_DELAY
	phase_changed.emit("round_end")
	round_ended.emit(player_won, GameState.player_score, GameState.bot_score)
	announce.emit(text, ROUND_END_DELAY - 0.4)


func _end_match() -> void:
	phase = Phase.MATCH_END
	_timer = MATCH_END_DELAY
	var won := GameState.player_score > GameState.bot_score
	AudioManager.play_2d("match_win" if won else "match_lose", -3.0)
	phase_changed.emit("match_end")
	announce.emit("VICTORY" if won else "DEFEAT", MATCH_END_DELAY - 0.5)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# --------------------------------------------------------------------- events

func _on_player_died(_attacker: Node) -> void:
	_finish_round(false)


func _on_bot_died(_attacker: Node) -> void:
	_finish_round(true)

# -------------------------------------------------------------------- helpers

## Two spawn points, as far apart as the arena allows.
func _pick_spawn_pair() -> Array[Transform3D]:
	if _spawns.size() >= 2:
		var a := _spawns[randi() % _spawns.size()]
		var b := a
		var best := -1.0
		for candidate in _spawns:
			var d := candidate.global_position.distance_to(a.global_position)
			if d > best:
				best = d
				b = candidate
		var ta := a.global_transform
		var tb := b.global_transform
		# Face each spawn roughly toward the middle of the arena.
		return [_looking_at_center(ta), _looking_at_center(tb)]

	return [
		Transform3D(Basis.IDENTITY, Vector3(-12.0, 1.2, 0.0)),
		Transform3D(Basis.IDENTITY, Vector3(12.0, 1.2, 0.0)),
	]


func _looking_at_center(t: Transform3D) -> Transform3D:
	var to_center := Vector3(0.0, t.origin.y, 0.0) - t.origin
	to_center.y = 0.0
	if to_center.length_squared() < 0.01:
		return t
	var yaw := atan2(-to_center.x, -to_center.z)
	return Transform3D(Basis(Vector3.UP, yaw), t.origin)


func _first_in_group(group: StringName) -> Node:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null
