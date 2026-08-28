extends Node

# Singleton for managing universal bullet time effects
# Provides dramatic, synchronized slowdown/speedup for all bullets

signal bullet_time_changed(multiplier: float, is_active: bool)
signal bullet_time_started()
signal bullet_time_ended()

# Core bullet time state
var is_bullet_time_active: bool = false
var bullet_time_multiplier: float = 1.0
var target_multiplier: float = 1.0
var transition_speed: float = 8.0  # How fast to transition between speeds

# Manual bullet time controls
var manual_bullet_time_enabled: bool = false
var bullet_time_duration: float = 2.0  # How long manual bullet time lasts
var bullet_time_timer: float = 0.0
var bullet_time_cooldown: float = 5.0  # Cooldown between uses
var bullet_time_cooldown_timer: float = 0.0

# Audio-reactive bullet time
var audio_reactive_enabled: bool = true
var bass_threshold: float = 0.8  # Trigger slowdown on strong bass
var high_threshold: float = 0.9  # Trigger speedup on strong highs
var audio_effect_duration: float = 1.5
var audio_effect_cooldown: float = 3.0  # Cooldown between audio-reactive effects
var audio_effect_cooldown_timer: float = 0.0

# Speed multiplier ranges
var slowdown_multiplier: float = 0.3  # 30% speed (dramatic slowdown)
var speedup_multiplier: float = 2.0   # 200% speed (dramatic speedup)
var normal_multiplier: float = 1.0

# Visual feedback state
var screen_tint_intensity: float = 0.0
var particle_trail_intensity: float = 0.0

func _ready():
	print("BulletTimeManager initialized")
	print("  SPACE = Manual bullet time")
	print("  Audio-reactive effects enabled")

func _process(delta):
	# Update manual bullet time
	update_manual_bullet_time(delta)

	# Update cooldowns
	if bullet_time_cooldown_timer > 0:
		bullet_time_cooldown_timer -= delta

	if audio_effect_cooldown_timer > 0:
		audio_effect_cooldown_timer -= delta
	
	# Smooth transition to target multiplier
	if abs(bullet_time_multiplier - target_multiplier) > 0.01:
		bullet_time_multiplier = lerp(bullet_time_multiplier, target_multiplier, transition_speed * delta)
		bullet_time_changed.emit(bullet_time_multiplier, is_bullet_time_active)
	else:
		bullet_time_multiplier = target_multiplier
	
	# Update visual feedback intensities
	update_visual_feedback(delta)
	
	# Handle input
	handle_input()

func handle_input():
	# Manual bullet time disabled - only audio-reactive effects
	pass

func can_use_bullet_time() -> bool:
	return bullet_time_cooldown_timer <= 0 and not is_bullet_time_active

func activate_manual_bullet_time():
	"""Activate player-controlled bullet time slowdown"""
	if not can_use_bullet_time():
		return
	
	print("🕐 BULLET TIME ACTIVATED!")
	is_bullet_time_active = true
	manual_bullet_time_enabled = true
	bullet_time_timer = bullet_time_duration
	bullet_time_cooldown_timer = bullet_time_cooldown
	
	set_target_multiplier(slowdown_multiplier)
	bullet_time_started.emit()

func update_manual_bullet_time(delta):
	# Update any active bullet time effect (manual or audio-reactive)
	if is_bullet_time_active and bullet_time_timer > 0:
		bullet_time_timer -= delta

		if bullet_time_timer <= 0:
			deactivate_bullet_time()

func deactivate_bullet_time():
	"""Return to normal speed"""
	if not is_bullet_time_active:
		return
	
	print("🕐 Bullet time ended")
	is_bullet_time_active = false
	manual_bullet_time_enabled = false
	
	set_target_multiplier(normal_multiplier)
	bullet_time_ended.emit()

func set_target_multiplier(multiplier: float):
	"""Set the target speed multiplier with smooth transition"""
	target_multiplier = multiplier

	# Update visual feedback based on multiplier
	if multiplier < normal_multiplier:
		# Slowdown effect - subtle screen tint
		screen_tint_intensity = (1.0 - multiplier) * 0.5  # More subtle tint
		particle_trail_intensity = 0.0
	else:
		# Normal or speedup - no visual effects, just bullet speed
		screen_tint_intensity = 0.0
		particle_trail_intensity = 0.0

func trigger_audio_reactive_slowdown(intensity: float, duration: float = -1):
	"""Trigger slowdown based on audio analysis (bass drops, etc.)"""
	if not audio_reactive_enabled:
		return

	# Don't override manual bullet time
	if manual_bullet_time_enabled:
		return

	# Check cooldown - don't trigger if we're still in cooldown
	if audio_effect_cooldown_timer > 0:
		return

	var effect_duration = duration if duration > 0 else audio_effect_duration
	var slowdown_amount = lerp(0.7, 0.3, intensity)  # 70% to 30% speed (more dramatic)

	print("🎵 Audio-reactive slowdown: ", slowdown_amount, "x for ", effect_duration, "s (intensity: ", intensity, ")")

	# Start effect and set cooldown
	is_bullet_time_active = true
	bullet_time_timer = effect_duration
	audio_effect_cooldown_timer = audio_effect_cooldown  # Set cooldown
	manual_bullet_time_enabled = false  # This is audio-driven

	set_target_multiplier(slowdown_amount)
	bullet_time_started.emit()

func trigger_audio_reactive_speedup(_intensity: float, _duration: float = -1):
	"""Speedup disabled - does nothing"""
	pass

func update_visual_feedback(delta):
	"""Update visual feedback intensities with smooth decay"""
	var decay_speed = 4.0  # Faster decay for cleaner look

	if not is_bullet_time_active:
		screen_tint_intensity = max(0.0, screen_tint_intensity - decay_speed * delta)
		particle_trail_intensity = 0.0  # Always 0 since we don't use trails

func get_bullet_speed_multiplier() -> float:
	"""Get the current bullet speed multiplier for all bullets"""
	return bullet_time_multiplier

func get_screen_tint_intensity() -> float:
	"""Get current screen tint intensity for visual effects"""
	return screen_tint_intensity

func get_particle_trail_intensity() -> float:
	"""Get current particle trail intensity for visual effects"""
	return particle_trail_intensity

func is_active() -> bool:
	"""Check if any bullet time effect is currently active"""
	return is_bullet_time_active

func get_cooldown_progress() -> float:
	"""Get bullet time cooldown progress (0.0 = ready, 1.0 = full cooldown)"""
	if bullet_time_cooldown_timer <= 0:
		return 0.0
	return bullet_time_cooldown_timer / bullet_time_cooldown

func trigger_volume_based_effect(volume: float, onset_density: float):
	"""Trigger effects based on overall volume and music density"""
	if not audio_reactive_enabled or manual_bullet_time_enabled:
		return

	# Very quiet sections (< 0.1) -> slight slowdown for dramatic effect
	if volume < 0.1 and onset_density < 1.0:
		var quiet_intensity = (0.1 - volume) / 0.1  # 0.0 to 1.0
		if quiet_intensity > 0.5:  # Only on very quiet parts
			trigger_audio_reactive_slowdown(quiet_intensity * 0.5, 2.0)

func get_status_text() -> String:
	"""Get current bullet time status for UI display"""
	if not is_bullet_time_active:
		return "Audio-Reactive"

	var time_left = int(bullet_time_timer + 1)
	return "SLOWDOWN " + str(time_left) + "s"

# Debug functions
func force_slowdown(multiplier: float = 0.5, duration: float = 3.0):
	"""Debug function to force bullet time"""
	is_bullet_time_active = true
	bullet_time_timer = duration
	set_target_multiplier(multiplier)
	bullet_time_started.emit()

func force_speedup(multiplier: float = 1.5, duration: float = 2.0):
	"""Debug function to force speedup"""
	is_bullet_time_active = true
	bullet_time_timer = duration
	set_target_multiplier(multiplier)
	bullet_time_started.emit()
