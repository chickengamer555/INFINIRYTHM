extends Node2D
class_name Enemy

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

# Homing behavior
var is_homing: bool = false
var homing_strength: float = 10.0  # How aggressively bullet homes in (higher = faster turning)

# Visual
var rotation_speed: float = 2.0
var rotation_angle: float = 0.0

# Orbital rotation around emitter
var spawn_center: Vector2 = Vector2.ZERO  # Where this bullet was spawned from
var orbital_rotation_speed: float = 0.3  # Matches emitter rotation speed (slow)

# Track if this enemy has been activated (to prevent pooled enemies from awarding points)
var has_been_activated: bool = false

# PERFORMANCE: Sprite-based rendering (50-70% faster than draw_circle)
var sprite: Sprite2D = null
static var bullet_texture: ImageTexture = null  # Shared texture for all bullets

func _ready():
	# Create shared bullet texture once (all bullets use the same texture)
	if bullet_texture == null:
		bullet_texture = create_bullet_texture()

	# Create sprite for this bullet
	sprite = Sprite2D.new()
	sprite.texture = bullet_texture
	sprite.centered = true
	add_child(sprite)

func create_bullet_texture() -> ImageTexture:
	# Create a 64x64 circle texture with NEON glow and thick border
	var size = 64
	var center = size / 2.0
	var base_radius = 10.0  # Base radius for the core
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)

	for y in range(size):
		for x in range(size):
			var dx = x - center
			var dy = y - center
			var dist = sqrt(dx*dx + dy*dy)

			var final_color = Color(0, 0, 0, 0)

			# Layer 3: Outer glow (2.5x size) - stronger neon glow
			var outer_radius = base_radius * 2.5
			if dist <= outer_radius:
				var factor = 1.0 - (dist / outer_radius)
				var alpha = pow(factor, 2.0) * 0.3  # Brighter outer glow
				final_color = Color(1, 1, 1, alpha)

			# Layer 2: Mid glow (1.6x size) - stronger intensity
			var mid_radius = base_radius * 1.6
			if dist <= mid_radius:
				var factor = 1.0 - (dist / mid_radius)
				var alpha = pow(factor, 1.2) * 0.6  # Brighter mid glow
				final_color = Color(1, 1, 1, alpha)

			# Layer 1.5: Thick border (1.15x size) - bright neon outline
			var border_outer = base_radius * 1.15
			var border_inner = base_radius * 0.85
			if dist <= border_outer and dist >= border_inner:
				# Sharp bright border
				final_color = Color(1.5, 1.5, 1.5, 1.0)  # Super bright border

			# Layer 1: Core (0.85x size) - solid and very bright
			if dist <= border_inner:
				var factor = 1.0 - (dist / border_inner)
				var alpha = pow(factor, 0.3) * 1.0
				# Very bright neon core
				final_color = Color(1.8, 1.8, 1.8, alpha)

			img.set_pixel(x, y, final_color)

	return ImageTexture.create_from_image(img)

func activate(spawn_pos: Vector2, vel: Vector2, type: String, color: Color, pattern: Pattern = Pattern.CIRCULAR, emitter_pos: Vector2 = Vector2.ZERO, homing: bool = false, size: float = 8.0):
	position = spawn_pos
	spawn_center = emitter_pos  # Store emitter position for orbital rotation
	base_velocity = vel  # Store original velocity
	velocity = vel
	enemy_type = type
	enemy_color = color
	enemy_size = size  # Set size from parameter
	pattern_type = pattern
	health = max_health
	rotation_angle = randf() * TAU
	is_homing = homing
	visible = true
	set_process(true)
	has_been_activated = true  # Mark as activated so deactivate() will award points

	# Update sprite appearance
	if sprite:
		sprite.visible = true
		sprite.modulate = color
		# Scale sprite to match enemy_size
		# Texture has base_radius of 10, scaled to 2.2x = 22 pixels total diameter
		# We want the core (base_radius) to match enemy_size
		var texture_base_radius = 10.0
		var scale_factor = enemy_size / texture_base_radius
		sprite.scale = Vector2(scale_factor, scale_factor)

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
	# Skip orbital rotation if homing (just track player instead)
	if spawn_center != Vector2.ZERO and not is_homing:
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
	# Only award points if this enemy was actually activated (not a pooled enemy that was never used)
	if has_been_activated and GameManager:
		GameManager.add_score(10)

	# Reset activation flag for next use
	has_been_activated = false

	# PERFORMANCE: Return to pool instead of freeing (object pooling)
	if gameplay_layer and gameplay_layer.has_method("return_enemy_to_pool"):
		gameplay_layer.return_enemy_to_pool(self)
	else:
		queue_free()  # Fallback if pooling not available

func check_collision_with_player(player_pos: Vector2, player_radius: float) -> bool:
	return position.distance_to(player_pos) < (enemy_size + player_radius)
