extends Node
class_name CharacterAnimator
## Drives a character's animation state from gameplay state.
##
## If the Mixamo library has been built it crossfades real clips. If it has not
## (fresh clone, no FBX downloaded yet) it falls back to procedural lean/bob on
## the placeholder mesh, so the game is always playable and never hard-depends
## on assets that have to be fetched by hand.

signal state_changed(state: String)

enum Action { NONE, FIRE, RELOAD, HIT, DEATH }

const LIBRARY_PATH := MixamoPipeline.OUT_PATH
const LIBRARY_NAME := "mixamo"
const BLEND_TIME := 0.14

@export var animation_player_path: NodePath
## Mesh root used for procedural motion when no clips are available.
@export var placeholder_visual_path: NodePath
@export var verbose := false

var has_clips := false

var _player: AnimationPlayer
var _humanoid: ProceduralHumanoid
var _skeleton: Skeleton3D
var _visual: Node3D
var _visual_rest := Vector3.ZERO
var _state := ""
var _action: Action = Action.NONE
var _action_timer := 0.0
var _bob_phase := 0.0

# Gameplay inputs, refreshed each frame by the owning character.
var speed_ratio := 0.0
var strafe := 0.0
var forward := 0.0
var is_crouching := false
var is_airborne := false
var is_aiming := false
var is_dead := false


func _ready() -> void:
	_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_visual = get_node_or_null(placeholder_visual_path) as Node3D
	if _visual != null:
		_visual_rest = _visual.position
	_load_library()


func _load_library() -> void:
	if _player == null:
		return
	if not ResourceLoader.exists(LIBRARY_PATH):
		if verbose:
			print_rich("[color=gray]CharacterAnimator: no Mixamo library at %s "
					% LIBRARY_PATH + "- using procedural fallback.[/color]")
		return

	var lib: AnimationLibrary = load(LIBRARY_PATH)
	if lib == null or lib.get_animation_list().is_empty():
		return
	# Match the clips to whatever bone namespace this character shipped with.
	var prefix := MixamoPipeline.detect_bone_prefix(_skeleton)
	lib = MixamoPipeline.retargeted_library(lib, prefix)
	if _player.has_animation_library(LIBRARY_NAME):
		_player.remove_animation_library(LIBRARY_NAME)
	_player.add_animation_library(LIBRARY_NAME, lib)
	has_clips = true

	if verbose:
		var missing := MixamoPipeline.missing_clips(lib)
		print("CharacterAnimator: loaded %d clips%s" % [
			lib.get_animation_list().size(),
			"" if missing.is_empty() else " (missing: %s)" % ", ".join(missing)])


## Late-bind the articulated stand-in, so the procedural fallback poses a real
## skeleton instead of tilting a capsule.
func bind_humanoid(humanoid: ProceduralHumanoid) -> void:
	_humanoid = humanoid


## Late-bind the AnimationPlayer that arrived with a character model. Called by
## the controllers once CharacterRig has instanced the body.
func bind_animation_player(player: AnimationPlayer, skeleton: Skeleton3D = null) -> void:
	if player == null:
		return
	if player == _player and skeleton == _skeleton:
		return
	_player = player
	_skeleton = skeleton
	has_clips = false
	_state = ""
	_load_library()


## Called every frame by PlayerController / BotController.
func update(delta: float, p_speed_ratio: float, p_forward: float, p_strafe: float,
		p_crouching: bool, p_airborne: bool, p_aiming := false) -> void:
	speed_ratio = p_speed_ratio
	forward = p_forward
	strafe = p_strafe
	is_crouching = p_crouching
	is_airborne = p_airborne
	is_aiming = p_aiming

	if _action_timer > 0.0:
		_action_timer = maxf(_action_timer - delta, 0.0)
		if _action_timer == 0.0 and _action != Action.DEATH:
			_action = Action.NONE

	var wanted := _resolve_state()
	if wanted != _state:
		_state = wanted
		_play(wanted)
		state_changed.emit(wanted)

	if not has_clips:
		_procedural(delta)


func play_action(action: Action, duration: float) -> void:
	if is_dead and action != Action.DEATH:
		return
	_action = action
	_action_timer = duration
	# Force a re-evaluation on the next update tick.
	_state = ""


func die() -> void:
	is_dead = true
	play_action(Action.DEATH, 9999.0)


func revive() -> void:
	is_dead = false
	_action = Action.NONE
	_action_timer = 0.0
	_state = ""
	if _humanoid != null and is_instance_valid(_humanoid):
		_humanoid.revive()
	if _visual != null:
		_visual.position = _visual_rest
		_visual.rotation = Vector3.ZERO

# ------------------------------------------------------------------ internals

func _resolve_state() -> String:
	if is_dead:
		return "death_1"
	match _action:
		Action.RELOAD:
			return "reload"
		Action.FIRE:
			return "fire"
		Action.HIT:
			return "hit_react"
		_:
			pass

	if is_airborne:
		return "jump_loop"

	if speed_ratio < 0.08:
		return "crouch_idle" if is_crouching else ("aim" if is_aiming else "idle")

	if is_crouching:
		return "crouch_walk"

	if absf(strafe) > absf(forward):
		return "walk_right" if strafe > 0.0 else "walk_left"
	if forward < -0.1:
		return "walk_back"
	return "run_fwd" if speed_ratio > 0.75 else "walk_fwd"


func _play(clip: String) -> void:
	if not has_clips or _player == null:
		return
	var full := "%s/%s" % [LIBRARY_NAME, clip]
	if not _player.has_animation(full):
		# Graceful degradation: fall back through sensible substitutes.
		for alt in _fallbacks(clip):
			var alt_full := "%s/%s" % [LIBRARY_NAME, alt]
			if _player.has_animation(alt_full):
				full = alt_full
				break
		if not _player.has_animation(full):
			return
	_player.play(full, BLEND_TIME)


func _fallbacks(clip: String) -> Array[String]:
	match clip:
		"run_fwd": return ["walk_fwd", "idle"]
		"walk_back", "walk_left", "walk_right": return ["walk_fwd", "idle"]
		"crouch_walk": return ["crouch_idle", "walk_fwd", "idle"]
		"crouch_idle": return ["idle"]
		"jump_loop": return ["jump_start", "idle"]
		"aim": return ["idle"]
		"fire", "reload", "hit_react": return ["idle"]
		"death_1": return ["death_2", "hit_react", "idle"]
		_: return ["idle"]


## Lean into the direction of travel and bob while moving. Only used until the
## real clips exist, but it keeps the placeholder readable in playtests.
func _procedural(delta: float) -> void:
	# An articulated stand-in poses itself properly; only fall back to tilting
	# the whole visual when there is not even that.
	if _humanoid != null and is_instance_valid(_humanoid):
		_humanoid.update_pose(delta, speed_ratio, forward, strafe,
				is_crouching, is_airborne, is_aiming, is_dead)
		return

	if _visual == null:
		return

	if is_dead:
		_visual.rotation.z = lerp_angle(_visual.rotation.z, PI * 0.5, delta * 6.0)
		_visual.position.y = lerpf(_visual.position.y, _visual_rest.y - 0.7, delta * 6.0)
		return

	_bob_phase += delta * (6.0 + 6.0 * speed_ratio)
	var bob := sin(_bob_phase) * 0.035 * speed_ratio
	var crouch_drop := -0.35 if is_crouching else 0.0

	_visual.position.y = lerpf(_visual.position.y,
			_visual_rest.y + bob + crouch_drop, delta * 12.0)
	_visual.rotation.z = lerp_angle(_visual.rotation.z,
			deg_to_rad(-strafe * 6.0), delta * 8.0)
	_visual.rotation.x = lerp_angle(_visual.rotation.x,
			deg_to_rad(forward * 4.0), delta * 8.0)
