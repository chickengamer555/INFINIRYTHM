extends Control
class_name BackgroundVisualizer

# Background visualization components (pretty ambient effects)
@onready var particle_container = $ParticleContainer
@onready var ambient_effects = $AmbientEffects
@onready var center_circle = $CenterCircle

# Audio analysis reference
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance

# Visual elements
var particles: Array[Dictionary] = []
const MIN_FREQUENCY = 20.0
const MAX_FREQUENCY = 20000.0

func _ready():
	print("BackgroundVisualizer _ready() called")
	print("  particle_container: ", particle_container)
	print("  ambient_effects: ", ambient_effects)
	print("  center_circle: ", center_circle)

	# Initialize particles
	initialize_particles()

	print("  Initialized ", particles.size(), " particles")

	# Force initial draw
	if particle_container:
		particle_container.queue_redraw()
	if ambient_effects:
		ambient_effects.queue_redraw()
	if center_circle:
		center_circle.queue_redraw()

func set_spectrum_analyzer(analyzer: AudioEffectSpectrumAnalyzerInstance):
	spectrum_analyzer = analyzer
	print("BackgroundVisualizer: spectrum_analyzer set: ", spectrum_analyzer != null)

func initialize_particles():
	# Visible but subtle background particle system
	particles.clear()
	var screen_size = Vector2(get_viewport().size)  # Convert Vector2i to Vector2
	for i in range(25):  # PERFORMANCE: Reduced from 40 to 25 for better performance
		# Dark, rich, saturated colors
		var color_choice = randi() % 4
		var base_color: Color
		match color_choice:
			0: base_color = Color(0.15, 0.2, 0.5)   # Dark rich blue
			1: base_color = Color(0.3, 0.1, 0.4)    # Dark rich purple
			2: base_color = Color(0.1, 0.3, 0.4)    # Dark rich cyan
			_: base_color = Color(0.4, 0.1, 0.3)    # Dark rich magenta

		var particle = {
			"position": Vector2(randf() * screen_size.x, randf() * screen_size.y),
			"velocity": Vector2(randf_range(-30, 30), randf_range(-30, 30)),
			"size": randf_range(2, 7),  # Even larger range for variety
			"color": Color(base_color.r, base_color.g, base_color.b, randf_range(0.5, 0.8)),  # Rich and visible
			"base_color": base_color,  # Store base for pulsing
			"life": randf_range(1.0, 3.0),
			"max_life": randf_range(1.0, 3.0),
			"rotation": randf() * TAU,
			"rotation_speed": randf_range(-1.5, 1.5),
			"pulse_phase": randf() * TAU,
			"glow_intensity": randf_range(0.5, 0.8)  # More glow
		}
		particles.append(particle)

var _debug_counter = 0
func _process(delta):
	_debug_counter += 1
	if _debug_counter == 60:  # Print once per second (at 60fps)
		print("BackgroundVisualizer _process: spectrum_analyzer = ", spectrum_analyzer != null)
		_debug_counter = 0

	if spectrum_analyzer:
		update_background_effects(delta)

func update_background_effects(delta):
	# Get audio data for background effects
	var total_magnitude = 0.0
	var _low_freq_magnitude = 0.0

	if spectrum_analyzer:
		var magnitude = spectrum_analyzer.get_magnitude_for_frequency_range(MIN_FREQUENCY, MAX_FREQUENCY)
		total_magnitude = magnitude.length()

		var low_mag = spectrum_analyzer.get_magnitude_for_frequency_range(20, 250)
		_low_freq_magnitude = low_mag.length()
	
	# Update particles with moderate audio reaction
	for particle in particles:
		# Update rotation
		particle.rotation += particle.rotation_speed * delta
		particle.pulse_phase += delta * 2.0

		# Move particles
		particle.position += particle.velocity * delta

		# Moderate audio-reactive movement
		var audio_force = total_magnitude * 200
		particle.velocity += Vector2(
			randf_range(-audio_force, audio_force),
			randf_range(-audio_force, audio_force)
		) * delta

		# Apply damping for smooth movement
		particle.velocity *= 0.96

		# Moderate size pulsing with audio
		var base_size = particle.size
		var pulse_size = sin(particle.pulse_phase) * total_magnitude * 8
		particle.size = max(base_size + pulse_size, 1.0)

		# Dark, rich color pulsing with audio
		var base_color = particle.base_color
		var brightness = 0.8 + total_magnitude * 1.2 + sin(particle.pulse_phase) * 0.15
		brightness = clamp(brightness, 0.6, 1.1)  # Keep it dark but reactive
		particle.color = Color(
			base_color.r * brightness,
			base_color.g * brightness,
			base_color.b * brightness,
			clamp(0.5 + total_magnitude * 1.5, 0.4, 0.9)  # Rich and visible
		)
		
		# Wrap around screen
		var screen_size = Vector2(get_viewport().size)  # Convert Vector2i to Vector2
		if particle.position.x < 0:
			particle.position.x = screen_size.x
		elif particle.position.x > screen_size.x:
			particle.position.x = 0

		if particle.position.y < 0:
			particle.position.y = screen_size.y
		elif particle.position.y > screen_size.y:
			particle.position.y = 0
	
	# Trigger redraws
	if particle_container:
		particle_container.queue_redraw()
	if ambient_effects:
		ambient_effects.queue_redraw()
	if center_circle:
		center_circle.queue_redraw()

# Custom drawing functions
var _draw_debug_counter = 0
func _on_particle_container_draw():
	_draw_debug_counter += 1
	if _draw_debug_counter == 60:
		print("BackgroundVisualizer: _on_particle_container_draw called, particles: ", particles.size())
		_draw_debug_counter = 0

	# PERFORMANCE: Optimized particle drawing
	for particle in particles:
		# Single-layer particles (removed glow layer for better performance)
		var core_color = Color(
			clamp(particle.color.r * 1.2, 0.0, 1.0),
			clamp(particle.color.g * 1.2, 0.0, 1.0),
			clamp(particle.color.b * 1.2, 0.0, 1.0),
			particle.color.a * 0.7
		)
		particle_container.draw_circle(particle.position, particle.size * 1.5, core_color)

func _on_ambient_effects_draw():
	# REMOVED - No ambient effects overlay to keep background pure black
	pass

func _on_center_circle_draw():
	# Optional: Draw a subtle center circle effect if needed
	# Currently empty to keep background minimal
	pass
