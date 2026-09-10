extends Node
class_name Health
## Reusable health component. Both the player and the bot own one.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, attacker: Node, is_headshot: bool)
signal died(attacker: Node)

@export var max_health: float = 100.0
@export var armor: float = 0.0
## Fraction of incoming damage armor absorbs while it lasts.
@export var armor_absorb: float = 0.5

var current: float = 100.0
var is_dead := false


func _ready() -> void:
	reset()


func reset() -> void:
	current = max_health
	is_dead = false
	health_changed.emit(current, max_health)


func take_damage(amount: float, attacker: Node = null, is_headshot := false) -> void:
	if is_dead or amount <= 0.0:
		return

	var to_health := amount
	if armor > 0.0:
		var absorbed: float = minf(armor, amount * armor_absorb)
		armor -= absorbed
		to_health -= absorbed

	current = maxf(current - to_health, 0.0)
	health_changed.emit(current, max_health)
	damaged.emit(amount, attacker, is_headshot)

	if current <= 0.0:
		is_dead = true
		died.emit(attacker)


func heal(amount: float) -> void:
	if is_dead:
		return
	current = minf(current + amount, max_health)
	health_changed.emit(current, max_health)


func fraction() -> float:
	return current / maxf(max_health, 0.001)
