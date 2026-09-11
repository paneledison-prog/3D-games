extends Node
## Autoload. Holds match configuration and the running Lone Wolf scoreline.
##
## Lone Wolf is a 1v1 duel: short rounds in a small arena, first player to
## ROUNDS_TO_WIN round wins takes the match.

signal score_changed(player_score: int, bot_score: int)
signal match_finished(player_won: bool)

enum Difficulty { ROOKIE, VETERAN, ELITE }

const ROUNDS_TO_WIN := 5
const ROUND_TIME := 90.0
const WARMUP_TIME := 3.0

var player_score := 0
var bot_score := 0
var round_number := 0
var difficulty: Difficulty = Difficulty.VETERAN
var match_over := false

## Loadout chosen in the menu, referenced by weapon id.
## Four slots: primary, sidearm, knife, grenade.
var player_loadout: Array[String] = [
	"ar_falcon", "pistol_talon", "knife_bayonet", "grenade_frag"]
var bot_loadout: Array[String] = [
	"ar_falcon", "pistol_talon", "knife_bayonet", "grenade_frag"]

## Character chosen in the menu, referenced by CharacterProfile id. Every model
## is auto-fitted to the same 1.8m height, so this is cosmetic only - no
## silhouette is a competitive advantage.
var player_character := "swat_guy"
var bot_character := "alien_soldier"

var mouse_sensitivity := 0.0022
var invert_y := false


func reset_match() -> void:
	player_score = 0
	bot_score = 0
	round_number = 0
	match_over = false
	score_changed.emit(player_score, bot_score)


func award_round(to_player: bool) -> void:
	if match_over:
		return
	if to_player:
		player_score += 1
	else:
		bot_score += 1
	score_changed.emit(player_score, bot_score)

	if player_score >= ROUNDS_TO_WIN or bot_score >= ROUNDS_TO_WIN:
		match_over = true
		match_finished.emit(player_score > bot_score)


## Per-difficulty bot tuning, consumed by BotController.
func bot_profile() -> Dictionary:
	match difficulty:
		Difficulty.ROOKIE:
			return {
				"reaction_time": 0.55,
				"aim_error": 4.5,
				"aim_speed": 4.0,
				"burst_len": 4,
				"strafe_chance": 0.25,
				"accuracy_recovery": 0.5,
			}
		Difficulty.ELITE:
			return {
				"reaction_time": 0.14,
				"aim_error": 1.1,
				"aim_speed": 11.0,
				"burst_len": 9,
				"strafe_chance": 0.8,
				"accuracy_recovery": 1.6,
			}
		_:
			return {
				"reaction_time": 0.30,
				"aim_error": 2.4,
				"aim_speed": 7.0,
				"burst_len": 6,
				"strafe_chance": 0.5,
				"accuracy_recovery": 1.0,
			}


func difficulty_name() -> String:
	return ["ROOKIE", "VETERAN", "ELITE"][int(difficulty)]
