extends Node2D

enum Pattern {
	CIRCULAR, CROSS, DIAMOND
}

var velocity: Vector2 = Vector2.ZERO
var base_velocity: Vector2 = Vector2.ZERO  # Store original velocity
var health: int = 3
var max_health: int = 3
var enemy_color: Color = Color.RED
var enemy_size: float = 8.0
var enemy_type: String = "basic"
var pattern_type: Pattern = Pattern.CIRCULAR
var gameplay_layer: Node = null  # Reference to get speed multiplier

# Visual
var rotation_speed: float = 2.0
var rotation_angle: float = 0.0

# Orbital rotation around emitter
var spawn_center: Vector2 = Vector2.ZERO  # Where this bullet was spawned from
var orbital_rotation_speed: float = 0.3  # Matches emitter rotation speed (slow)

func activate(spawn_pos: Vector2, vel: Vector2, type: String, color: Color, pattern: Pattern = Pattern.CIRCULAR, emitter_pos: Vector2 = Vector2.ZERO):
	position = spawn_pos
	spawn_center = emitter_pos  # Store emitter position for orbital rotation
	base_velocity = vel  # Store original velocity
	velocity = vel
	enemy_type = type
	enemy_color = color
	pattern_type = pattern
	health = max_health
	rotation_angle = randf() * TAU
	visible = true
	set_process(true)

	# Get reference to gameplay layer for speed multiplier
	if not gameplay_layer:
		gameplay_layer = get_parent().get_parent()  # EnemySpawnZones -> GameplayLayer

func _process(delta):
	# Apply COMBINED speed multipliers for universal bullet time effects
	var final_multiplier = 1.0

	# 1. Get music-reactive speed from gameplay layer (onset density)
	if gameplay_layer and gameplay_layer.has_method("get_speed_multiplier"):
		var music_multiplier = gameplay_layer.get_speed_multiplier()
		final_multiplier *= music_multiplier

	# 2. Apply player slowdown ability
	if gameplay_layer and gameplay_layer.has_method("get_slowdown_multiplier"):
		var slowdown = gameplay_layer.get_slowdown_multiplier()
		final_multiplier *= slowdown

	# 3. Apply bullet time effects (dramatic slowdown/speedup)
	if has_node("/root/BulletTimeManager"):
		var bullet_time_manager = get_node("/root/BulletTimeManager")
		var bullet_time_multiplier = bullet_time_manager.get_bullet_speed_multiplier()
		final_multiplier *= bullet_time_multiplier

	# Apply combined multiplier to base velocity
	velocity = base_velocity * final_multiplier

	# Move bullet outward normally
	position += velocity * delta

	# ORBITAL ROTATION: Rotate position around spawn center (emitter) AFTER moving
	if spawn_center != Vector2.ZERO:
		# Get current offset from spawn center
		var offset = position - spawn_center

		# Rotate the offset vector clockwise
		var rotation_delta = orbital_rotation_speed * delta * final_multiplier
		offset = offset.rotated(rotation_delta)

		# Update position (this adds rotation on top of the linear movement)
		position = spawn_center + offset

		# Also rotate the velocity vector so it continues in the right direction
		base_velocity = base_velocity.rotated(rotation_delta)

	# Simple rotation for visual variety (also affected by bullet time for consistency)
	var visual_rotation_delta = rotation_speed * delta * final_multiplier
	rotation_angle += visual_rotation_delta
	rotation = rotation_angle

	# Check if off screen
	if is_off_screen():
		deactivate()

func take_damage(amount: int):
	health -= amount
	if health <= 0:
		die()

func die():
	# Emit signal or trigger effects before deactivating
	deactivate()

func is_off_screen() -> bool:
	var screen_rect = get_viewport_rect()
	var margin = 100
	return position.x < -margin or position.x > screen_rect.size.x + margin or \
		   position.y < -margin or position.y > screen_rect.size.y + margin

func deactivate():
	# Award point if bullet goes off screen without hitting player
	if GameManager:
		GameManager.add_score(10)
	queue_free()

func check_collision_with_player(player_pos: Vector2, player_radius: float) -> bool:
	return position.distance_to(player_pos) < (enemy_size + player_radius)
