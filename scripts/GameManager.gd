extends Node

# Singleton for managing game state, score, health, combos

signal score_changed(new_score)
signal combo_changed(combo_count, multiplier)
signal health_changed(current_health, max_health)
signal player_died()
signal enemy_killed(enemy_type)

# Score system
var score: int = 0
var high_score: int = 0

# Combo system - time-based multiplier
var combo_count: int = 0
var combo_timer: float = 0.0  # Tracks time survived without being hit
var combo_multiplier: float = 1.0  # Starts at 1.0x, increases 0.1x per second survived
var combo_rate: float = 0.1  # Rate of combo increase per second (can be modified by abilities)
var time_scale: float = 1.0  # Track audio time scale for combo calculation

# Health system
var max_health: int = 100
var current_health: int = 100
var is_player_alive: bool = true

# Difficulty system - point loss on damage
enum DifficultyMode { NORMAL, HARD, INSANE }
var current_difficulty: DifficultyMode = DifficultyMode.NORMAL
var point_loss_per_damage: Dictionary = {
	DifficultyMode.NORMAL: 100,
	DifficultyMode.HARD: 200,
	DifficultyMode.INSANE: 1000
}

func _ready():
	reset_game()

func _process(delta):
	# Increase combo multiplier over time survived (uses combo_rate which can be modified)
	# Scale delta by time_scale to match audio playback speed
	if is_player_alive:
		combo_timer += delta * time_scale
		combo_multiplier = 1.0 + (combo_timer * combo_rate)
		combo_changed.emit(combo_count, combo_multiplier)

func reset_game():
	score = 0
	combo_count = 0
	combo_timer = 0.0
	combo_multiplier = 1.0
	combo_rate = 0.1  # Reset to default rate
	time_scale = 1.0  # Reset time scale
	current_health = max_health
	is_player_alive = true
	score_changed.emit(score)
	combo_changed.emit(combo_count, combo_multiplier)
	health_changed.emit(current_health, max_health)

# Score functions
func add_score(base_points: int):
	var points = int(base_points * combo_multiplier)
	score += points
	if score > high_score:
		high_score = score
	score_changed.emit(score)

func get_score() -> int:
	return score

func get_high_score() -> int:
	return high_score

# Format score with abbreviations (1000000 -> 1M, 1000 -> 1K, etc.)
# Handles negative scores too!
func format_score(score_value: int) -> String:
	var is_negative = score_value < 0
	var abs_score = abs(score_value)
	var formatted = ""

	if abs_score >= 1000000:
		formatted = "%.1f" % (abs_score / 1000000.0) + "M"
	elif abs_score >= 1000:
		formatted = "%.1f" % (abs_score / 1000.0) + "K"
	else:
		formatted = str(abs_score)

	return "-" + formatted if is_negative else formatted

# Combo functions
func reset_combo():
	combo_timer = 0.0
	combo_multiplier = 1.0
	combo_changed.emit(combo_count, combo_multiplier)

# Health functions
func take_damage(amount: int):
	if not is_player_alive:
		return

	current_health = max(current_health - amount, 0)
	health_changed.emit(current_health, max_health)

	# Deduct points based on difficulty (CANNOT go below 0!)
	var points_to_lose = point_loss_per_damage[current_difficulty] * amount
	score = max(score - points_to_lose, 0)
	score_changed.emit(score)

	# Reset combo on hit
	reset_combo()

	if current_health <= 0:
		player_die()

func heal(amount: int):
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func get_health_percent() -> float:
	return float(current_health) / float(max_health)

func player_die():
	is_player_alive = false
	player_died.emit()

# Difficulty functions
func set_difficulty(difficulty: DifficultyMode):
	current_difficulty = difficulty
	print("GameManager: Difficulty set to ", difficulty)
