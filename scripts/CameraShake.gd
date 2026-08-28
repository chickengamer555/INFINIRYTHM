extends Node2D
class_name CameraShake

# Trauma-based screen shake for visual feedback

@export var decay: float = 0.8
@export var max_offset: Vector2 = Vector2(10, 8)
@export var max_roll: float = 0.05

var trauma: float = 0.0
var trauma_power: int = 2
var noise: FastNoiseLite = FastNoiseLite.new()
var noise_y: int = 0

var target_node: Node2D = null
var original_position: Vector2 = Vector2.ZERO

func _ready():
	noise.seed = randi()
	noise.frequency = 4.0

func set_target(node: Node2D):
	target_node = node
	if target_node:
		original_position = target_node.position

func add_trauma(amount: float):
	trauma = min(trauma + amount, 1.0)

func _process(delta):
	if trauma > 0:
		trauma = max(trauma - decay * delta, 0)
		shake()
	elif target_node:
		# Reset to zero when no trauma
		target_node.rotation = 0
		target_node.position = original_position

func shake():
	if not target_node:
		return

	var amount = pow(trauma, trauma_power)
	noise_y += 1

	target_node.rotation = max_roll * amount * noise.get_noise_2d(noise.seed, noise_y)
	var offset_x = max_offset.x * amount * noise.get_noise_2d(noise.seed * 2, noise_y)
	var offset_y = max_offset.y * amount * noise.get_noise_2d(noise.seed * 3, noise_y)
	target_node.position = original_position + Vector2(offset_x, offset_y)
