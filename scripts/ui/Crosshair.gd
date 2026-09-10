extends Control
class_name Crosshair
## Dynamic crosshair: the gap tracks the weapon's real spread cone, so what you
## see is what the bullets actually do. Also owns the hitmarker.

const THICKNESS := 2.0
const LENGTH := 7.0
const MIN_GAP := 3.0
const GAP_PER_DEGREE := 5.5
const HITMARKER_TIME := 0.32

var spread_degrees := 2.0
var is_aiming := false
var color := Color(0.85, 1.0, 0.92, 0.92)

var _hit_alpha := 0.0
var _hit_headshot := false
var _display_gap := MIN_GAP


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	var target_gap := MIN_GAP + spread_degrees * GAP_PER_DEGREE
	_display_gap = lerpf(_display_gap, target_gap, delta * 14.0)
	if _hit_alpha > 0.0:
		_hit_alpha = maxf(_hit_alpha - delta / HITMARKER_TIME, 0.0)
	queue_redraw()


func flash_hit(headshot: bool) -> void:
	_hit_alpha = 1.0
	_hit_headshot = headshot


func _draw() -> void:
	var c := size * 0.5

	# Centre dot, always visible so the aim point is unambiguous.
	draw_circle(c, 1.2, color)

	if not is_aiming:
		var gap := _display_gap
		var col := color
		# Four ticks: left, right, up, down.
		draw_line(c + Vector2(-gap - LENGTH, 0), c + Vector2(-gap, 0), col, THICKNESS)
		draw_line(c + Vector2(gap, 0), c + Vector2(gap + LENGTH, 0), col, THICKNESS)
		draw_line(c + Vector2(0, -gap - LENGTH), c + Vector2(0, -gap), col, THICKNESS)
		draw_line(c + Vector2(0, gap), c + Vector2(0, gap + LENGTH), col, THICKNESS)

	if _hit_alpha > 0.0:
		var hit_col := Color(1.0, 0.35, 0.3, _hit_alpha) if _hit_headshot \
				else Color(1.0, 1.0, 1.0, _hit_alpha)
		var near := 4.0
		var far := 10.0
		for dir in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(c + dir * near, c + dir * far, hit_col, 2.0)
