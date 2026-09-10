extends Node
## Autoload. Pooled playback for the procedurally generated SFX set.
##
## Sounds live in res://assets/audio/sfx/<name>.wav and are addressed by their
## bare filename, e.g. AudioManager.play_3d("wpn_rifle_fire", muzzle_position).

const SFX_DIR := "res://assets/audio/sfx"
const POOL_2D := 12
const POOL_3D := 24

var sfx_volume := 1.0
var _cache: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next_2d := 0
var _next_3d := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Master"
		p.max_distance = 60.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool_3d.append(p)


func _get_stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var path := "%s/%s.wav" % [SFX_DIR, sound]
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: missing sound '%s' (%s)" % [sound, path])
		_cache[sound] = null
		return null
	var stream: AudioStream = load(path)
	_cache[sound] = stream
	return stream


## Non-positional playback: UI, hitmarkers, the local player's own weapon.
func play_2d(sound: String, volume_db := 0.0, pitch_variation := 0.0) -> void:
	var stream := _get_stream(sound)
	if stream == null:
		return
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = stream
	p.volume_db = volume_db + linear_to_db(maxf(sfx_volume, 0.0001))
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()


## Positional playback: gunfire, footsteps and impacts out in the arena.
func play_3d(sound: String, position: Vector3, volume_db := 0.0,
		pitch_variation := 0.0, max_distance := 60.0) -> void:
	var stream := _get_stream(sound)
	if stream == null:
		return
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stream = stream
	p.global_position = position
	p.max_distance = max_distance
	p.volume_db = volume_db + linear_to_db(maxf(sfx_volume, 0.0001))
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()


func play_footstep(position: Vector3, volume_db := -6.0) -> void:
	play_3d("footstep_%d" % (randi() % 3 + 1), position, volume_db, 0.08, 25.0)


func play_impact(surface: String, position: Vector3) -> void:
	var sound := "impact_concrete"
	match surface:
		"metal":
			sound = "impact_metal"
		"flesh":
			sound = "impact_flesh"
	play_3d(sound, position, -3.0, 0.12, 40.0)
