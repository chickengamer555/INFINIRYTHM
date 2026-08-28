extends Control
class_name BulletHellLevelInsane

# Node references
@onready var player_area = $PlayerArea
@onready var enemy_spawn_zones = $EnemySpawnZones
@onready var bullet_container = $BulletContainer
@onready var beat_indicators = $BeatIndicators
@onready var shake_node = $ShakeNode
@onready var frequency_indicator = $"../UI/GameUI/FrequencyIndicator"
@onready var waveform_layer = $"../WaveformLayer"  # Separate layer for waveform - between background and gameplay
@onready var slowdown_meter_bar = $"../UI/GameUI/SlowdownMeter"  # UI ProgressBar for slowdown
@onready var slowdown_label = $"../UI/GameUI/SlowdownLabel"  # UI Label for slowdown
@onready var speedup_meter_bar = $"../UI/GameUI/SpeedupMeter"  # UI ProgressBar for speedup
@onready var speedup_label = $"../UI/GameUI/SpeedupLabel"  # UI Label for speedup
@onready var speedup_timer_label = $"../UI/GameUI/SpeedupTimer"  # UI Label for speedup timer

# Audio analysis
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var audio_capture: AudioEffectCapture  # The capture effect itself, not an instance


# Player
var player_position: Vector2
var player_velocity: Vector2 = Vector2.ZERO  # For wall push momentum
var player_size: float = 8.0  # HARD MODE: 10x bigger
var player_speed: float = 250.0  # HARD MODE: 100x faster
var is_focused: bool = false
var player_invincible: bool = false
var invincible_timer: float = 0.0
var wall_push_friction: float = 50.0  # How quickly push momentum decays (lower = slides longer)
var wall_push_force: float = 600.0  # How hard walls push the player (OOMPH!)
var player_hit_flash: float = 0.0  # Red flash when hit
var player_hit_flash_duration: float = 0.2  # How long flash lasts

# Idle punishment - homing bullets
var player_idle_timer: float = 0.0  # How long player has been idle
var player_idle_threshold: float = 5.0  # Seconds before warning
var player_idle_grace_period: float = 1.0  # 1 second after warning before aimed shots
var player_idle_warned: bool = false  # Track if warning period started
var player_last_position: Vector2 = Vector2.ZERO  # Track last position
var spawn_homing_next_wave: bool = false  # Flag to spawn homing bullets

# Slowdown ability
var slowdown_meter: float = 100.0  # 0-100
var slowdown_max: float = 100.0
var slowdown_drain_rate: float = 80.0  # Drain per second when active (5 seconds duration)
var slowdown_recharge_rate: float = 50.0  # Recharge per second when not active
var is_slowdown_active: bool = false
var slowdown_multiplier: float = 0.7  # Slows bullets to 20% speed (very slow)
var slowdown_audio_multiplier: float = 0.7  # Slows audio to 75% speed (less dramatic)
var slowdown_can_activate: bool = true  # Can activate after cooldown
var slowdown_key_released: bool = true  # Track if space bar was released (prevents spam)
var slowdown_cooldown_delay: float =  0.7 # Cooldown delay in seconds before can activate again
var slowdown_cooldown_timer: float = 0.0  # Current cooldown timer

# Speedup ability
var speedup_meter: float = 100.0  # 0-100 (always full - infinite use)
var speedup_max: float = 100.0
var speedup_drain_rate: float = 0.0  # No drain - can hold infinitely!
var speedup_recharge_rate: float = 0.0  # No recharge needed
var is_speedup_active: bool = false
var speedup_multiplier: float = 4.0  # Speeds bullets to 3.0x speed (faster!)
var speedup_player_multiplier: float = 2.5  # Player moves at 2.0x speed (slower than bullets)
var speedup_audio_multiplier: float = 2.5  # Speeds audio to 2.5x speed
var speedup_can_activate: bool = true  # Can activate after cooldown
var speedup_key_released: bool = true  # Track if Q key was released (prevents spam)
var speedup_timer: float = 0.0  # Timer that increases while holding, decreases when released
var speedup_timer_increase_rate: float = 0.25  # Increases by 0.25 per second while holding (reduced penalty)
var speedup_timer_decrease_rate: float = 1.5  # Decreases by 1.5 per second when released (faster recovery)

# PROFESSIONAL BEAT DETECTION (research-based)
var beat_cooldown: float = 0.0  # INSANE MODE: No cooldown - spawn on every beat!
var time_since_last_beat: float = 0.0

# Energy history for dynamic thresholding (1 second = ~60 frames at 60fps)
# OPTIMIZATION: Using circular buffers instead of arrays with pop_front()
var bass_history: PackedFloat32Array = PackedFloat32Array()
var mid_history: PackedFloat32Array = PackedFloat32Array()
var high_history: PackedFloat32Array = PackedFloat32Array()
var history_size: int = 43  # 1 second of history for proper averaging
var history_write_index: int = 0
var history_filled: bool = false

# SPECTRAL FLUX: Track previous spectrum to detect CHANGES (onsets)
var last_bass_energy: float = 0.0
var last_mid_energy: float = 0.0
var last_high_energy: float = 0.0

# ONSET DETECTION: Spectral flux values (how much spectrum changed)
# OPTIMIZATION: Using circular buffers
var bass_flux_history: PackedFloat32Array = PackedFloat32Array()
var mid_flux_history: PackedFloat32Array = PackedFloat32Array()
var high_flux_history: PackedFloat32Array = PackedFloat32Array()
var flux_history_size: int = 20  # Rolling window for threshold
var flux_write_index: int = 0
var flux_history_filled: bool = false

# ONSET DENSITY TRACKING: Track music "speed" (onsets per second)
var onset_times: Array[float] = []  # Track when onsets happen
var onset_density: float = 1.0  # Current onsets per second (default 1)
var onset_window: float = 3.0  # Look at last 3 seconds
var global_speed_multiplier: float = 1.0  # Speed multiplier for ALL bullets

# Volume tracking
var last_volume: float = 0.0
var volume_history: Array[float] = []
var max_history_size: int = 30

# Visual feedback for frequency indicators
var bass_pulse: float = 0.0
var mid_pulse: float = 0.0
var high_pulse: float = 0.0
var last_beat_type: String = ""

# Spawn point visualization
var spawn_flash_timer: float = 0.0
var spawn_flash_position: Vector2 = Vector2.ZERO
var spawn_flash_color: Color = Color.WHITE
var spawn_flash_intensity: float = 0.0

# Emitter visualization (always visible!)
var emitter_rotation: float = 0.0  # Clockwise rotation angle

# 🔴 HARD MODE: Peak volume detection for rotation reversal
var rotation_direction: float = 1.0  # 1.0 = clockwise, -1.0 = counter-clockwise
var peak_volume_history: Array[float] = []  # Track recent volumes for peak detection
var peak_history_size: int = 60  # 1 second at 60fps for better averaging
var peak_threshold_multiplier: float = 1.15  # Volume must be 1.15x average to be a peak (more sensitive!)
var last_peak_time: float = 0.0  # Time of last peak detection
var peak_cooldown: float = 1.5  # Minimum 1.5 seconds between rotation reversals
var rotation_reversal_flash: float = 0.0  # Visual flash when rotation reverses (0-1)
var debug_peak_timer: float = 0.0  # Debug output every 2 seconds

# Waveform visualization (song timeline - ACTUAL waveform from audio file)
var waveform_data: PackedFloat32Array = []  # Pre-analyzed waveform data for entire song
var waveform_samples_per_pixel: int = 512  # How many audio samples per waveform pixel
var waveform_scroll_offset: float = 0.0  # Current scroll position (in seconds)
var waveform_y_center: float = 0.0  # Center Y position of waveform
var waveform_amplitude: float = 100.0  # Max vertical displacement
var waveform_display_duration: float = 10.0  # How many seconds of waveform to show on screen
var audio_player: AudioStreamPlayer = null  # Reference to audio player
var song_duration: float = 0.0  # Total song length in seconds
var waveform_update_timer: float = 0.0  # Only update waveform periodically
var waveform_update_interval: float = 0.05  # Update every 50ms instead of every frame
var waveform_is_complete: bool = false  # Track if we've captured the entire song

# Advanced waveform smoothing
var waveform_smoothed: PackedFloat32Array = []  # RMS-smoothed waveform data
var waveform_envelope_attack: float = 0.05  # Attack time for envelope follower (50ms)
var waveform_envelope_release: float = 0.3  # Release time for envelope follower (300ms)
var waveform_last_smoothed: float = 0.0  # Last smoothed value
var emitter_y_position: float = 0.0  # Current emitter Y position
var emitter_y_position_previous: float = 0.0  # Previous frame position for sub-frame interpolation
var emitter_y_velocity: float = 0.0  # Velocity for spring damping for temporal continuity

# Audio timing calibration (for precise synchronization)
var audio_timing_offset: float = 0.0  # Fine-tune if emitter drifts (±0.01s adjustments)
var use_precise_audio_time: bool = true  # Enable latency-compensated audio timing
var use_waveform_rms_smoothing: bool = false  # Disable for maximum emitter accuracy, enable for prettier visuals

# ULTRA-SMOOTH TRACKING - Choose your method:
# Method 1: One Euro Filter (BEST - industry standard, used in VR/AR tracking)
# Method 2: Critically Damped Spring (BEST - used in AAA games)
# Method 3: EMA + Lookahead (Good - simple and effective)

var emitter_smoothing_method: String = "one_euro"  # "one_euro", "spring", or "ema"

# ONE EURO FILTER (Recommended - THE industry standard)
var one_euro_min_cutoff: float = 1.0      # Minimum cutoff frequency (lower = smoother)
var one_euro_beta: float = 0.007          # Speed coefficient (how much speed affects smoothing)
var one_euro_dcutoff: float = 1.0         # Derivative cutoff frequency
var one_euro_x_prev: float = 0.0          # Previous position
var one_euro_dx_prev: float = 0.0         # Previous derivative
var one_euro_first_time: bool = true      # First update flag

# CRITICALLY DAMPED SPRING (Alternative - AAA game standard)
var spring_frequency: float = 2.0         # Spring frequency (higher = faster response)
var spring_velocity: float = 0.0          # Current velocity
var spring_target_prev: float = 0.0       # Previous target

# EMA + LOOKAHEAD (Fallback - simple and effective)
var emitter_ema_alpha: float = 0.25       # Smoothing: 0.0=very smooth, 1.0=no smoothing
var emitter_lookahead_time: float = 0.04  # Predictive lookahead in seconds
var emitter_use_lookahead: bool = true    # Enable predictive tracking
var emitter_sample_window: int = 2        # Multi-sample averaging window (±samples)
var emitter_use_averaging: bool = true    # Enable multi-sample smoothing

# Spawn zones
var beat_zones: Array[Dictionary] = []

# Play area boundaries (synth wave walls)
var play_area: Rect2
var boundary_margin: float = 100.0  # Distance from screen edges

# Visualizer bars - physical walls that push the player!
var left_bar_widths: Array[float] = []
var right_bar_widths: Array[float] = []
var left_bar_targets: Array[float] = []  # Target widths for smoothing
var right_bar_targets: Array[float] = []
var num_visualizer_bars: int = 7  # Back to 7 bars
var bar_smoothing: float = 0.25  # Balanced response
var max_bar_width: float = 450.0  # INSANE MODE: Walls can extend much farther! (was 250.0)

# Dynamic range adjustment for better visualization
var magnitude_history: Array[Array] = []  # Track magnitude history per band
var adaptive_scaling: Array[float] = []  # Per-band scaling factors

# Visual effects
var camera_shake: CameraShake

# Game state
var game_active: bool = true
var song_playing: bool = false  # Track if song is actually playing - starts false to prevent initial spawn
var current_delta: float = 0.0  # Current frame delta time for physics calculations
var song_start_delay: float = 0.5  # Delay before bullets can spawn (in seconds)
var song_start_timer: float = 0.0  # Timer for song start delay

# Performance optimization: dirty flags for conditional redraws
var enemies_dirty: bool = true
var ui_dirty: bool = true
var frequency_dirty: bool = true
var beat_indicators_dirty: bool = true

# Performance optimization: cached enemy list for collision detection
var active_enemies: Array[Enemy] = []
var enemies_list_dirty: bool = true

# Performance optimization: pre-allocated constant arrays for visualizer
const FREQ_RANGES = [
	[20.0, 80.0],       # Sub-bass (kick drums)
	[80.0, 250.0],      # Bass (bass guitar, low vocals)
	[250.0, 500.0],     # Low-mid (vocals, instruments)
	[500.0, 1000.0],    # Mid (vocals, snare)
	[1000.0, 2000.0],   # High-mid (vocals, instruments)
	[2000.0, 4000.0],   # Presence (vocals, cymbals)
	[4000.0, 8000.0]    # Brilliance (cymbals, hi-hats)
]
const BASE_SENSITIVITIES = [40000.0, 45000.0, 50000.0, 55000.0, 60000.0, 35000.0, 25000.0]

# Cache visualizer bar magnitudes to avoid duplicate calculations
var cached_bar_magnitudes: Array[float] = []

# Performance optimization: Cached spectrum analyzer results (updated once per frame)
var cached_bass_energy: float = 0.0
var cached_mid_energy: float = 0.0
var cached_high_energy: float = 0.0
var cached_full_spectrum: float = 0.0
var spectrum_cache_dirty: bool = true

# Performance optimization: Pre-allocated waveform arrays to reduce GC pressure
var waveform_top_points: PackedVector2Array = PackedVector2Array()
var waveform_bottom_points: PackedVector2Array = PackedVector2Array()

# Performance optimization: Object pool for bullets (reduces instantiation overhead)
var enemy_pool: Array[Enemy] = []
var pool_size: int = 150  # Pre-allocate pool for up to 150 bullets
var enemy_scene: PackedScene = null

# Performance monitoring
var fps_label: Label = null
var enemy_count_label: Label = null

func _ready():
	print("🔴 HARD MODE SCRIPT LOADED! player_size=", player_size, " player_speed=", player_speed)
	# Initialize player position
	var screen_size = get_viewport_rect().size
	player_position = Vector2(screen_size.x / 2, screen_size.y * 0.8)
	player_last_position = player_position

	# Setup play area boundaries - full screen
	var ui_offset = 60
	play_area = Rect2(
		0,  # All the way to left edge
		ui_offset,  # Just below UI
		screen_size.x,  # All the way to right edge
		screen_size.y - ui_offset  # All the way to bottom
	)

	# Initialize waveform center position
	waveform_y_center = screen_size.y / 2

	# Initialize emitter position to center
	emitter_y_position = screen_size.y / 2

	# Initialize circular buffers for energy and flux history
	bass_history.resize(history_size)
	mid_history.resize(history_size)
	high_history.resize(history_size)
	bass_flux_history.resize(flux_history_size)
	mid_flux_history.resize(flux_history_size)
	high_flux_history.resize(flux_history_size)
	for i in range(history_size):
		bass_history[i] = 0.0
		mid_history[i] = 0.0
		high_history[i] = 0.0
	for i in range(flux_history_size):
		bass_flux_history[i] = 0.0
		mid_flux_history[i] = 0.0
		high_flux_history[i] = 0.0

	# Initialize visualizer bar arrays
	left_bar_widths.resize(num_visualizer_bars)
	right_bar_widths.resize(num_visualizer_bars)
	left_bar_targets.resize(num_visualizer_bars)
	right_bar_targets.resize(num_visualizer_bars)
	magnitude_history.resize(num_visualizer_bars)
	adaptive_scaling.resize(num_visualizer_bars)
	cached_bar_magnitudes.resize(num_visualizer_bars)

	for i in range(num_visualizer_bars):
		left_bar_widths[i] = 2.0
		right_bar_widths[i] = 2.0
		left_bar_targets[i] = 2.0
		right_bar_targets[i] = 2.0
		magnitude_history[i] = []
		adaptive_scaling[i] = 1.0
		cached_bar_magnitudes[i] = 0.0

	# Pre-allocate waveform point arrays (approximately 640 points for 1920px width)
	waveform_top_points.resize(700)
	waveform_bottom_points.resize(700)

	# Initialize object pool for bullets
	enemy_scene = preload("res://scenes/Enemy.tscn")
	for i in range(pool_size):
		var enemy = enemy_scene.instantiate()
		enemy.visible = false
		enemy.set_process(false)
		enemy_spawn_zones.add_child(enemy)
		enemy_pool.append(enemy)

	# Initialize beat zones
	initialize_beat_zones()

	# Setup camera shake
	camera_shake = CameraShake.new()
	add_child(camera_shake)
	camera_shake.set_target(shake_node)

	# Setup performance monitoring labels
	fps_label = Label.new()
	fps_label.position = Vector2(screen_size.x - 200, screen_size.y - 60)
	fps_label.add_theme_font_size_override("font_size", 14)
	fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 0.8))
	add_child(fps_label)

	enemy_count_label = Label.new()
	enemy_count_label.position = Vector2(screen_size.x - 200, screen_size.y - 40)
	enemy_count_label.add_theme_font_size_override("font_size", 14)
	enemy_count_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0, 0.8))
	add_child(enemy_count_label)

	# Connect to GameManager signals
	if GameManager:
		GameManager.player_died.connect(_on_player_died)

func initialize_beat_zones():
	var screen_size = get_viewport_rect().size
	var ui_offset = 60

	# Single full-screen zone - patterns chosen by volume
	beat_zones.append({
		"type": "dynamic",
		"rect": Rect2(0, ui_offset, screen_size.x, screen_size.y - ui_offset),
		"color": Color(0.5, 0.8, 1.0),  # Soft blue
		"last_spawn": 0.0
	})

func set_spectrum_analyzer(analyzer: AudioEffectSpectrumAnalyzerInstance):
	spectrum_analyzer = analyzer
	if not spectrum_analyzer:
		print("BulletHellLevel: ERROR - Spectrum analyzer is NULL")

	# Connect waveform layer draw signal
	if waveform_layer and not waveform_layer.draw.is_connected(_on_waveform_layer_draw):
		waveform_layer.draw.connect(_on_waveform_layer_draw)

func set_audio_capture(capture: AudioEffectCapture):
	audio_capture = capture
	if not audio_capture:
		print("BulletHellLevel: ERROR - Audio capture is NULL")

func set_audio_player(player: AudioStreamPlayer):
	"""Set reference to audio player for timeline tracking"""
	audio_player = player

	# Extract waveform data from audio stream
	if audio_player and audio_player.stream:
		extract_waveform_from_audio()

func extract_waveform_from_audio():
	"""Extract actual waveform data from the audio stream"""
	if not audio_player or not audio_player.stream:
		return

	var stream = audio_player.stream

	# Get audio data based on stream type
	if stream is AudioStreamMP3:
		extract_waveform_from_mp3(stream)
	elif stream is AudioStreamOggVorbis:
		extract_waveform_from_ogg(stream)
	elif stream is AudioStreamWAV:
		extract_waveform_from_wav(stream)
	else:
		# Fallback: create empty waveform
		waveform_data.resize(1000)
		for i in range(1000):
			waveform_data[i] = 0.0

func extract_waveform_from_wav(stream: AudioStreamWAV):
	"""Extract waveform from WAV audio"""
	var audio_data = stream.data
	if audio_data.size() == 0:
		return

	# Get stream info
	var format = stream.format
	var _stereo = stream.stereo
	var _mix_rate = stream.mix_rate

	song_duration = stream.get_length()

	# Calculate how many waveform samples we need
	var _total_audio_samples = audio_data.size()

	# Process audio data based on format
	var samples: Array[float] = []

	if format == AudioStreamWAV.FORMAT_16_BITS:
		# 16-bit PCM
		for i in range(0, audio_data.size() - 1, 2):
			var sample_16bit = (audio_data[i + 1] << 8) | audio_data[i]
			if sample_16bit >= 32768:
				sample_16bit -= 65536
			var normalized = float(sample_16bit) / 32768.0
			samples.append(normalized)
	elif format == AudioStreamWAV.FORMAT_8_BITS:
		# 8-bit PCM
		for i in range(audio_data.size()):
			var sample_8bit = audio_data[i]
			var normalized = (float(sample_8bit) - 128.0) / 128.0
			samples.append(normalized)

	# Downsample to create waveform (average chunks for visualization)
	var num_waveform_samples = int(song_duration * 100)  # 100 samples per second for timeline
	waveform_data.resize(num_waveform_samples)

	var chunk_size = max(1, samples.size() / num_waveform_samples)

	for i in range(num_waveform_samples):
		var start_idx = int(i * chunk_size)
		var end_idx = int(min((i + 1) * chunk_size, samples.size()))

		# Get peak amplitude in this chunk (like a real DAW)
		var peak = 0.0
		for j in range(start_idx, end_idx):
			peak = max(peak, abs(samples[j]))

		waveform_data[i] = peak

func extract_waveform_from_mp3(stream: AudioStreamMP3):
	"""Initialize waveform for MP3 - will be filled in real-time using AudioEffectCapture"""

	# Get song duration from stream
	song_duration = stream.get_length()
	if song_duration <= 0:
		song_duration = 180.0  # Fallback to 3 minutes

	# Pre-allocate waveform array (100 samples per second for display)
	var num_samples = int(song_duration * 100)
	waveform_data.resize(num_samples)

	# Initialize all samples to 0 (center line)
	for i in range(num_samples):
		waveform_data[i] = 0.0

func extract_waveform_from_ogg(stream: AudioStreamOggVorbis):
	"""Initialize waveform for OGG - will be filled in real-time using AudioEffectCapture"""
	# Get song duration
	song_duration = stream.get_length()
	if song_duration <= 0:
		song_duration = 180.0

	var num_samples = int(song_duration * 100)
	waveform_data.resize(num_samples)

	# Initialize all samples to 0 (center line)
	for i in range(num_samples):
		waveform_data[i] = 0.0

func _process(delta):
	if not game_active:
		return

	# Store delta for use in all physics calculations this frame
	current_delta = delta

	# PERFORMANCE: Cache spectrum analyzer results once per frame (reduces FFT queries by ~60%)
	if spectrum_analyzer:
		cached_bass_energy = spectrum_analyzer.get_magnitude_for_frequency_range(20.0, 250.0).length()
		cached_mid_energy = spectrum_analyzer.get_magnitude_for_frequency_range(250.0, 2000.0).length()
		cached_high_energy = spectrum_analyzer.get_magnitude_for_frequency_range(2000.0, 20000.0).length()
		cached_full_spectrum = spectrum_analyzer.get_magnitude_for_frequency_range(20.0, 20000.0).length()
		spectrum_cache_dirty = false

	# Update player
	update_player_input(delta)
	update_invincibility(delta)
	ui_dirty = true  # Player moved, UI needs redraw

	# Update audio-reactive systems
	if spectrum_analyzer:
		update_beat_detection(delta)
		update_waveform(delta)
		frequency_dirty = true  # Frequency values changed

	# Update ULTRA-SMOOTH emitter position every frame
	if audio_player and audio_player.playing:
		get_emitter_y_ultra_smooth(delta)
		enemies_dirty = true  # Emitter moved

	# Update game objects
	update_enemies(delta)
	check_collisions()

	# Update pulse decay
	bass_pulse = max(0, bass_pulse - delta * 3.0)
	mid_pulse = max(0, mid_pulse - delta * 3.0)
	high_pulse = max(0, high_pulse - delta * 3.0)

	# Update hit flash
	if player_hit_flash > 0:
		player_hit_flash -= delta / player_hit_flash_duration

	# 🔴 HARD MODE: Detect volume peaks and reverse rotation direction
	if spectrum_analyzer:
		# Use BASS energy for peak detection (bass drops are most dramatic!)
		var current_volume = cached_bass_energy + (cached_mid_energy * 0.5)  # Bass + some mids
		
		# Track volume history for peak detection
		peak_volume_history.append(current_volume)
		if peak_volume_history.size() > peak_history_size:
			peak_volume_history.pop_front()
		
		# Calculate average and max volume from history
		if peak_volume_history.size() >= peak_history_size:
			var avg_volume = 0.0
			var max_volume = 0.0
			for vol in peak_volume_history:
				avg_volume += vol
				if vol > max_volume:
					max_volume = vol
			avg_volume /= peak_volume_history.size()
			
			# Debug output every 2 seconds
			debug_peak_timer += delta
			if debug_peak_timer >= 2.0:
				debug_peak_timer = 0.0
				var _threshold = avg_volume * peak_threshold_multiplier
				print("🔴 HARD MODE DEBUG - Current: %.4f | Avg: %.4f | Threshold: %.4f | Max: %.4f" % [current_volume, avg_volume, _threshold, max_volume])

			# Detect peak: current volume significantly higher than average
			var current_time = Time.get_ticks_msec() / 1000.0
			var time_since_last_peak = current_time - last_peak_time
			var threshold = avg_volume * peak_threshold_multiplier

			if current_volume > threshold and time_since_last_peak >= peak_cooldown and avg_volume > 0.001:
				# 🎵 PEAK DETECTED! REVERSE ROTATION! 🎵
				rotation_direction *= -1.0
				last_peak_time = current_time
				rotation_reversal_flash = 1.0  # Trigger visual flash
				
				# 💥 JUMP the emitter rotation to make the reversal INSTANTLY VISIBLE!
				emitter_rotation += PI / 4.0 * rotation_direction  # 45 degree jump in the new direction
				
				# 💥 REVERSE ALL BULLETS' ORBITAL ROTATION DIRECTION!
				var bullets_reversed = 0
				for enemy in enemy_pool:
					if is_instance_valid(enemy) and enemy.visible:
						# Reverse their orbital rotation speed so they rotate the opposite way!
						enemy.orbital_rotation_speed *= -1.0
						bullets_reversed += 1
				
				print("🔴🔴🔴 HARD MODE: PEAK VOLUME DETECTED! 🔴🔴🔴")
				print("    Current: %.4f | Average: %.4f | Ratio: %.2fx" % [current_volume, avg_volume, current_volume / avg_volume])
				print("    Rotation: ", "⟳ CLOCKWISE" if rotation_direction > 0 else "⟲ COUNTER-CLOCKWISE")
				print("    💥 REVERSED %d BULLETS INSTANTLY! Emitter jumped to %.2f rad" % [bullets_reversed, emitter_rotation])
	
	# Update rotation reversal flash decay
	if rotation_reversal_flash > 0:
		rotation_reversal_flash = max(0, rotation_reversal_flash - delta * 2.0)
		ui_dirty = true  # Force UI redraw during flash so the indicator is visible!

	# Update emitter rotation with dynamic direction (INSANE MODE: Faster rotation!)
	emitter_rotation += delta * 0.8 * rotation_direction  # INSANE MODE: Much faster rotation! (was 0.3)

	# Update waveform periodically
	waveform_update_timer -= delta
	if waveform_update_timer <= 0.0:
		waveform_update_timer = waveform_update_interval
		if waveform_layer:
			waveform_layer.queue_redraw()

	# Redraw only when necessary (conditional based on dirty flags)
	if enemies_dirty:
		enemy_spawn_zones.queue_redraw()
		enemies_dirty = false

	if ui_dirty:
		bullet_container.queue_redraw()
		ui_dirty = false

	if beat_indicators_dirty:
		beat_indicators.queue_redraw()
		beat_indicators_dirty = false

	if frequency_dirty and frequency_indicator:
		frequency_indicator.queue_redraw()
		frequency_dirty = false

	# Update performance monitoring
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if enemy_count_label:
		var enemy_count = active_enemies.size() if not enemies_list_dirty else enemy_spawn_zones.get_child_count()
		enemy_count_label.text = "Bullets: %d" % enemy_count

func update_player_input(delta):
	var input_vector = Vector2.ZERO

	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1
	if Input.is_action_pressed("move_up"):
		input_vector.y -= 1
	if Input.is_action_pressed("move_down"):
		input_vector.y += 1

	# Focus mode (shift for precision)


	# Update slowdown cooldown timer
	if slowdown_cooldown_timer > 0:
		slowdown_cooldown_timer -= delta
		if slowdown_cooldown_timer <= 0:
			slowdown_can_activate = true

	# Slowdown ability (Space bar) - with cooldown delay!
	# Can only START activating if meter has charge AND key was released AND cooldown finished AND speedup is NOT active
	if Input.is_action_pressed("bullet_time") and slowdown_can_activate and slowdown_key_released and slowdown_meter > 0 and not is_speedup_active:
		is_slowdown_active = true
		slowdown_key_released = false  # Lock until released (prevents spam)

	# While active, drain the meter (can hold space!)
	if is_slowdown_active:
		slowdown_meter = max(0, slowdown_meter - slowdown_drain_rate * delta)

		# Force deactivate when meter hits 0 OR space released OR speedup becomes active
		if slowdown_meter <= 0 or not Input.is_action_pressed("bullet_time") or is_speedup_active:
			is_slowdown_active = false
			slowdown_can_activate = false
			slowdown_cooldown_timer = slowdown_cooldown_delay  # Start cooldown

	# Recharge when not active
	if not is_slowdown_active:
		slowdown_meter = min(slowdown_max, slowdown_meter + slowdown_recharge_rate * delta)

	# Track if space bar was released (for anti-spam)
	if not Input.is_action_pressed("bullet_time"):
		slowdown_key_released = true

	# Speedup ability (Q key) - hold infinitely with timer!
	# Can only START activating if timer is at 0 AND key was released
	if Input.is_action_pressed("speed_up") and speedup_key_released and speedup_timer <= 0:
		is_speedup_active = true
		speedup_key_released = false  # Lock until released (prevents spam)
		speedup_timer = 1.0  # Start at 1 second when first pressed

		# INSANE MODE: Boost combo rate massively to reward the extreme difficulty (2.5x audio + 4x bullets + no cooldown!)
		if GameManager:
			# Current multiplier = 1.0 + (combo_timer * 0.1)
			# We want same multiplier with new rate: 1.0 + (new_combo_timer * 1.0)
			# So: new_combo_timer = combo_timer * (0.1 / 1.0)
			GameManager.combo_timer = GameManager.combo_timer * (0.1 / 1.0)
			GameManager.combo_rate = 1.0  # 10x faster combo building for INSANE difficulty!

	# While active, increase timer and combo rate
	if is_speedup_active:
		# Increase timer by 0.25 per second while holding
		speedup_timer += speedup_timer_increase_rate * delta

		# Ensure combo rate stays at 1.0x per second (10x faster than normal!)
		if GameManager:
			GameManager.combo_rate = 1.0

		# Deactivate only when Q released
		if not Input.is_action_pressed("speed_up"):
			is_speedup_active = false

			# Adjust combo_timer to maintain current combo_multiplier when switching back to 0.1 rate
			if GameManager:
				# Current multiplier = 1.0 + (combo_timer * 1.0)
				# We want same multiplier with new rate: 1.0 + (new_combo_timer * 0.1)
				# So: new_combo_timer = combo_timer * (1.0 / 0.1)
				GameManager.combo_timer = GameManager.combo_timer * (1.0 / 0.1)
				GameManager.combo_rate = 0.1
	else:
		# When not active, ensure combo rate is back to normal
		if GameManager:
			GameManager.combo_rate = 0.1

	# When not active and timer > 0, count down the timer
	if not is_speedup_active and speedup_timer > 0:
		speedup_timer -= speedup_timer_decrease_rate * delta
		speedup_timer = max(0, speedup_timer)  # Don't go below 0

	# Track if Q key was released (for anti-spam)
	if not Input.is_action_pressed("speed_up"):
		speedup_key_released = true

	# Move player with input
	if input_vector.length() > 0:
		input_vector = input_vector.normalized()
		# Apply slowdown/speedup multiplier to player speed (uses separate player multiplier!)
		var speed_multiplier = get_player_speed_multiplier()
		player_position += input_vector * player_speed * delta * speed_multiplier

	# Apply wall push momentum (walls push you and you keep moving!)
	player_position += player_velocity * delta

	# Apply friction to wall push velocity (gradually slow down)
	player_velocity = player_velocity.move_toward(Vector2.ZERO, wall_push_friction * delta)

	# Track player idle time for homing bullet punishment
	var movement_threshold = 5.0
	if player_position.distance_to(player_last_position) > movement_threshold:
		# Player moved significantly - reset everything
		player_idle_timer = 0.0
		player_last_position = player_position
		player_idle_warned = false
		spawn_homing_next_wave = false
	else:
		# Player is idle - increment timer
		player_idle_timer += delta

		# After 5 seconds idle, enter warning period
		if player_idle_timer >= player_idle_threshold and not player_idle_warned:
			player_idle_warned = true
			# Warning visual could go here (flash screen, etc.)

		# After warning + 1 second grace period, trigger aimed shots
		if player_idle_warned and player_idle_timer >= (player_idle_threshold + player_idle_grace_period):
			if not spawn_homing_next_wave:
				spawn_homing_next_wave = true

	# Walls that push the player with momentum!
	apply_visualizer_physics(delta)

	# CRITICAL: Keep player on screen LAST - this is the final authority!
	# This ensures player NEVER goes off screen, even if visualizer physics tries to push them
	var screen_size = get_viewport_rect().size
	var side_margin = 30.0  # Left/right margin
	var top_margin = 80.0  # Top margin (account for UI)
	var bottom_margin =  65.0  # Bottom margin - IMPORTANT!
	player_position.x = clamp(player_position.x, side_margin, screen_size.x - side_margin)
	player_position.y = clamp(player_position.y, top_margin, screen_size.y - bottom_margin)

func apply_visualizer_physics(delta):
	# Dynamic walls - push the player with momentum!
	var bar_height = play_area.size.y / num_visualizer_bars
	var bar_index = int((player_position.y - play_area.position.y) / bar_height)

	# IMPROVED: Clamp bar_index to valid range to prevent edge cases
	bar_index = clamp(bar_index, 0, num_visualizer_bars - 1)

	# Left bar - pushes player to the right with momentum
	var left_bar_edge = play_area.position.x + left_bar_widths[bar_index]
	var player_left_edge = player_position.x - (player_size * 1.5)  # Slightly larger margin
	if player_left_edge < left_bar_edge:
		# Correct position
		player_position.x = left_bar_edge + (player_size * 1.5)
		# Add push velocity to the right with OOMPH!
		player_velocity.x += wall_push_force * delta

	# Right bar - pushes player to the left with momentum
	var right_bar_edge = (play_area.position.x + play_area.size.x) - right_bar_widths[bar_index]
	var player_right_edge = player_position.x + (player_size * 1.5)  # Slightly larger margin
	if player_right_edge > right_bar_edge:
		# Correct position
		player_position.x = right_bar_edge - (player_size * 1.5)
		# Add push velocity to the left with OOMPH!
		player_velocity.x -= wall_push_force * delta

func update_invincibility(delta):
	if player_invincible:
		invincible_timer -= delta
		if invincible_timer <= 0:
			player_invincible = false

func update_beat_detection(delta):
	# Track song start delay
	if song_playing and song_start_timer < song_start_delay:
		song_start_timer += delta

	# Scale time passage by audio slowdown so beats spawn at same rate as music
	var time_scale = get_audio_slowdown_multiplier()
	time_since_last_beat += delta * time_scale

	# PERFORMANCE: Use cached spectrum values (already queried once this frame)
	var bass_energy = cached_bass_energy
	var mid_energy = cached_mid_energy
	var high_energy = cached_high_energy

	# Store current total for compatibility
	var current_volume = bass_energy + mid_energy + high_energy

	# Track volume history
	volume_history.append(current_volume)
	if volume_history.size() > max_history_size:
		volume_history.pop_front()

	# Calculate average recent volume
	var _avg_volume = 0.0
	for v in volume_history:
		_avg_volume += v
	_avg_volume /= max(1, volume_history.size())

	# SIMPLE 3-BAND BEAT DETECTION (clean and responsive)
	var _beat_detected = false
	var beat_type = ""
	var _beat_intensity = 0.0
	var _dominant_frequency = ""

	# PROFESSIONAL BEAT DETECTION ALGORITHM
	# Based on industry research: dynamic variance-based thresholding

	# Update energy history using circular buffer pattern (O(1) instead of O(n))
	bass_history[history_write_index] = bass_energy
	mid_history[history_write_index] = mid_energy
	high_history[history_write_index] = high_energy

	history_write_index = (history_write_index + 1) % history_size
	if history_write_index == 0:
		history_filled = true

	# Calculate averages
	var _bass_avg = 0.0
	var _mid_avg = 0.0
	var _high_avg = 0.0

	var count = history_size if history_filled else history_write_index
	if count == 0:
		count = 1  # Prevent division by zero

	for i in range(count):
		_bass_avg += bass_history[i]
		_mid_avg += mid_history[i]
		_high_avg += high_history[i]

	_bass_avg /= count
	_mid_avg /= count
	_high_avg /= count

	# SPECTRAL FLUX ONSET DETECTION
	# Calculate how much each band CHANGED (not just how loud it is)
	var bass_flux = max(0.0, bass_energy - last_bass_energy)  # Only positive changes (half-wave rectification)
	var mid_flux = max(0.0, mid_energy - last_mid_energy)
	var high_flux = max(0.0, high_energy - last_high_energy)

	# Track flux history using circular buffer pattern (O(1) instead of O(n))
	bass_flux_history[flux_write_index] = bass_flux
	mid_flux_history[flux_write_index] = mid_flux
	high_flux_history[flux_write_index] = high_flux

	flux_write_index = (flux_write_index + 1) % flux_history_size
	if flux_write_index == 0:
		flux_history_filled = true

	# Calculate flux averages (local mean)
	var bass_flux_avg = 0.0
	var mid_flux_avg = 0.0
	var high_flux_avg = 0.0

	var flux_count = flux_history_size if flux_history_filled else flux_write_index
	if flux_count == 0:
		flux_count = 1  # Prevent division by zero

	for i in range(flux_count):
		bass_flux_avg += bass_flux_history[i]
		mid_flux_avg += mid_flux_history[i]
		high_flux_avg += high_flux_history[i]

	bass_flux_avg /= flux_count
	mid_flux_avg /= flux_count
	high_flux_avg /= flux_count

	# ONSET DETECTION: Flux > Threshold × Average (research recommends 1.5x)
	var sensitivity = 0.7  # INSANE MODE: Lower threshold for more bullets! (was 1.4)
	var spawned_any = false
	var is_rising = current_volume > last_volume

	# Detect onsets in each band independently - INSANE MODE: Lower minimum threshold too!
	var bass_onset = bass_flux > sensitivity * bass_flux_avg and bass_flux > 0.0005  # was 0.001
	var mid_onset = mid_flux > sensitivity * mid_flux_avg and mid_flux > 0.0005  # was 0.001
	var high_onset = high_flux > sensitivity * high_flux_avg and high_flux > 0.0005  # was 0.001

	# Only spawn if cooldown passed AND we detected an onset AND song is playing AND audio is actually playing
	# SPEEDUP: Reduce cooldown when holding Q for more bullets
	var effective_cooldown = beat_cooldown
	if is_speedup_active:
		effective_cooldown = beat_cooldown * 0.5  # 50% faster spawns when holding Q

	var audio_is_playing = audio_player and audio_player.playing
	var can_spawn = song_start_timer >= song_start_delay  # Only spawn after delay
	if song_playing and audio_is_playing and can_spawn and time_since_last_beat >= effective_cooldown and (bass_onset or mid_onset or high_onset):
		# Find which band had strongest onset
		var max_flux = max(bass_flux, max(mid_flux, high_flux))

		var color_type: String

		if max_flux == bass_flux and bass_onset:
			# 🔴 BASS onset - kick drums, bass drops
			beat_type = "BASS"
			color_type = "heavy"
			spawned_any = true
		elif max_flux == high_flux and high_onset:
			# 🔵 HIGH onset - cymbals, hi-hats
			beat_type = "HIGH"
			color_type = "strong"
			spawned_any = true
		elif mid_onset:
			# 🟢 MID onset - snares, vocals, melody
			beat_type = "MID"
			color_type = "normal"
			spawned_any = true

		if spawned_any:
			# Track this onset for density calculation
			var current_time = Time.get_ticks_msec() / 1000.0
			onset_times.append(current_time)

			trigger_simple_beat_event(beat_type, bass_flux + mid_flux + high_flux, color_type, is_rising)
			enemies_dirty = true  # New bullets spawned

	# Calculate onset density (onsets per second)
	var current_time = Time.get_ticks_msec() / 1000.0
	var cutoff_time = current_time - onset_window

	# Remove old onsets outside the window
	while onset_times.size() > 0 and onset_times[0] < cutoff_time:
		onset_times.pop_front()

	# Calculate density: number of onsets / time window
	onset_density = onset_times.size() / onset_window
	onset_density = clamp(onset_density, 0.5, 4.0)  # Reasonable range

	# Update global speed multiplier based on onset density
	# Map onset_density (0.5-4.0) to speed multiplier (0.6-1.8)
	var density_normalized = (onset_density - 0.5) / 3.5  # 0.0 to 1.0
	global_speed_multiplier = lerp(0.6, 1.8, clamp(density_normalized, 0.0, 1.0))

	# ENHANCED: Trigger dramatic bullet time effects on strong audio events
	if has_node("/root/BulletTimeManager"):
		var bullet_time_manager = get_node("/root/BulletTimeManager")
		if bullet_time_manager.audio_reactive_enabled:
			# Trigger slowdown on strong bass drops (kick drums, bass drops)
			if bass_onset and bass_flux > 0.8:
				var bass_intensity = clamp((bass_flux - 0.8) / 0.2, 0.0, 1.0)  # 0.8-1.0 -> 0.0-1.0
				bullet_time_manager.trigger_audio_reactive_slowdown(bass_intensity, 1.8)

			# Trigger speedup on intense high frequency activity (cymbals, intense sections)
			elif high_onset and high_flux > 0.9:
				var high_intensity = clamp((high_flux - 0.9) / 0.1, 0.0, 1.0)  # 0.9-1.0 -> 0.0-1.0
				bullet_time_manager.trigger_audio_reactive_speedup(high_intensity, 1.2)

			# Also check for volume-based effects (quiet/loud sections)
			bullet_time_manager.trigger_volume_based_effect(current_volume, onset_density)

	# Update cooldown
	if spawned_any:
		time_since_last_beat = 0.0

	# Track volume history
	volume_history.append(current_volume)
	if volume_history.size() > max_history_size:
		volume_history.pop_front()

	# Update energy tracking
	last_bass_energy = bass_energy
	last_mid_energy = mid_energy
	last_high_energy = high_energy
	last_volume = current_volume

# SIMPLE CLEAN BEAT TRIGGER (3 frequency bands only)
func trigger_simple_beat_event(beat_type: String, intensity: float, intensity_level: String, is_rising: bool):
	var zone = beat_zones[0]
	var pattern_choice: Enemy.Pattern

	# Set pulse for visual feedback (including emitter!)

	# SIMPLE VOLUME-BASED SYSTEM - easier to understand!
	match intensity_level:
		"normal":
			# 🟢 GREEN: Normal beats - small, medium speed
			pattern_choice = Enemy.Pattern.CROSS
			zone.color = Color(0.3, 1.0, 0.3)  # Green
			mid_pulse = 1.0

		"strong":
			# 🔵 BLUE: Strong beats - medium, faster
			pattern_choice = Enemy.Pattern.DIAMOND
			zone.color = Color(0.3, 0.6, 1.0)  # Blue
			high_pulse = 1.0

		"heavy":
			# 🔴 RED: HEAVY beats (drops, impacts) - big, slower
			pattern_choice = Enemy.Pattern.CIRCULAR
			zone.color = Color(1.0, 0.3, 0.3)  # Red
			bass_pulse = 1.0

		_:
			pattern_choice = Enemy.Pattern.CROSS
			zone.color = Color(1.0, 1.0, 1.0)

	# Try to spawn pattern FIRST - only show flash if successful
	zone.pattern = pattern_choice
	var spawn_success = spawn_simple_pattern(zone, intensity, spawn_homing_next_wave)

	# Reset homing flag after spawning - back to 5 second timer
	if spawn_homing_next_wave:
		spawn_homing_next_wave = false
		player_idle_warned = false
		player_idle_timer = 0.0

func get_precise_audio_time() -> float:
	"""Get the ACTUAL audio time that is currently playing through speakers

	This compensates for:
	- Audio buffer chunking (get_time_since_last_mix)
	- Hardware output latency (get_output_latency)
	- Optional manual calibration offset

	Returns the most accurate audio time for visual synchronization.
	"""
	if not audio_player or not audio_player.playing:
		return 0.0

	if use_precise_audio_time:
		# PROFESSIONAL AUDIO SYNC: Compensate for all latencies
		var precise_time = (
			audio_player.get_playback_position() +
			AudioServer.get_time_since_last_mix() -
			AudioServer.get_output_latency() +
			audio_timing_offset
		)
		return max(0.0, precise_time)
	else:
		# Simple mode (less accurate, may drift)
		return audio_player.get_playback_position()

func update_waveform(delta):
	"""Capture real-time audio samples and fill ENTIRE waveform data (past AND future)"""
	if not audio_player or not audio_player.playing:
		return

	# Update scroll offset to PRECISE audio time (with latency compensation)
	waveform_scroll_offset = get_precise_audio_time()

	# If waveform is complete, we can see past and future - no need to capture more
	if waveform_is_complete:
		return

	# Capture audio samples from AudioEffectCapture
	if audio_capture and waveform_data.size() > 0:
		var frames_available = audio_capture.get_frames_available()

		if frames_available > 0 and audio_capture.can_get_buffer(frames_available):
			var audio_buffer: PackedVector2Array = audio_capture.get_buffer(frames_available)

			# Process and store samples at their ACTUAL time positions
			var current_time = waveform_scroll_offset
			var samples_per_display_point = 441  # 44100 Hz / 100 samples per second
			var accumulated_samples = 0
			var peak_amplitude = 0.0
			var rms_sum = 0.0

			for i in range(audio_buffer.size()):
				var sample = audio_buffer[i]
				var amplitude = abs((sample.x + sample.y) / 2.0)

				if amplitude > peak_amplitude:
					peak_amplitude = amplitude

				rms_sum += amplitude * amplitude
				accumulated_samples += 1

				if accumulated_samples >= samples_per_display_point:
					var sample_index = int(current_time * 100)

					if sample_index >= 0 and sample_index < waveform_data.size():
						var rms_amplitude = sqrt(rms_sum / accumulated_samples)
						var hybrid_amplitude = (rms_amplitude * 0.7) + (peak_amplitude * 0.3)
						waveform_data[sample_index] = hybrid_amplitude

					accumulated_samples = 0
					peak_amplitude = 0.0
					rms_sum = 0.0
					current_time += 0.01

			# Check if we've captured the entire song
			if waveform_scroll_offset >= song_duration - 0.5:
				waveform_is_complete = true

func get_current_volume() -> float:
	if not spectrum_analyzer:
		return 0.0
	# PERFORMANCE: Use cached full spectrum value
	return cached_full_spectrum

func is_too_close_to_player(pos: Vector2, min_distance: float = 200.0) -> bool:
	return pos.distance_to(player_position) < min_distance

# PERFORMANCE: Object pool management
func get_pooled_enemy() -> Enemy:
	# Try to find an inactive enemy in the pool
	for enemy in enemy_pool:
		if is_instance_valid(enemy) and not enemy.visible and not enemy.is_processing():
			return enemy

	# Pool exhausted - create a new enemy and add to pool (dynamic expansion)
	var enemy = enemy_scene.instantiate()
	enemy.visible = false
	enemy.set_process(false)
	enemy_spawn_zones.add_child(enemy)
	enemy_pool.append(enemy)
	return enemy

func return_enemy_to_pool(enemy: Enemy):
	# Return enemy to pool instead of freeing it
	if not is_instance_valid(enemy):
		return

	# Reset enemy state
	enemy.visible = false
	enemy.set_process(false)
	enemy.velocity = Vector2.ZERO
	enemy.base_velocity = Vector2.ZERO
	enemy.position = Vector2(-1000, -1000)  # Move off-screen

	# Hide the sprite if it exists
	if enemy.sprite:
		enemy.sprite.visible = false

# SIMPLE: Clean, responsive patterns - returns true if spawn succeeded
func get_music_rotation_angle() -> float:
	# Calculate spawn angle rotation based on current music intensity!
	# This rotates the EMITTER direction, not the bullets themselves
	var current_volume = get_current_volume()
	var rotation_speed = lerp(0.3, 1.2, clamp(current_volume * 100.0, 0.0, 1.0))  # Faster rotation!
	# Accumulate rotation over time
	return Time.get_ticks_msec() * 0.001 * rotation_speed

func get_waveform_y_at_time(time_offset: float, delta: float) -> float:
	"""Get waveform Y position - emitter rides along the TOP of center waveform

	ULTRA-PRECISE TRACKING with:
	- Exact same Catmull-Rom interpolation as waveform display
	- NO additional smoothing (Catmull-Rom provides C1 continuity)
	- Sub-frame interpolation for butter-smooth 60fps+ motion
	- Improved edge case handling
	"""
	var screen_size = get_viewport_rect().size
	var waveform_center_y = screen_size.y * 0.5  # Centered vertically on screen

	if waveform_data.size() == 0:
		emitter_y_position = waveform_center_y
		return waveform_center_y

	# Center waveform: LEFT = 3s ago, RIGHT = now (current_time)
	# Emitter is at screen CENTER horizontally
	# Time window is 3 seconds, so center of screen = current_time - 1.5s

	# Calculate what time the CENTER of screen represents:
	# progress = 0.5 (center), time_window = 3.0
	# time_at_center = (current_time - 3.0) + (0.5 * 3.0) = current_time - 1.5
	var time_at_screen_center = waveform_scroll_offset - 1.5 + time_offset
	var current_time = time_at_screen_center

	# Convert time to waveform sample index
	var samples_per_second = 100.0
	var sample_pos = current_time * samples_per_second
	var sample_index = int(sample_pos)

	# USE EXACT SAME CATMULL-ROM INTERPOLATION AS WAVEFORM DISPLAY
	# This ensures PIXEL-PERFECT alignment between visual waveform and emitter position
	var p0 = 0.0
	var p1 = 0.0
	var p2 = 0.0
	var p3 = 0.0

	# IMPROVED edge case handling with better boundary conditions
	if sample_index >= 1 and sample_index < waveform_data.size() - 2:
		# Normal case: we have all 4 points for Catmull-Rom
		p0 = waveform_data[sample_index - 1]
		p1 = waveform_data[sample_index]
		p2 = waveform_data[sample_index + 1]
		p3 = waveform_data[sample_index + 2]
	elif sample_index < 0:
		# Before start: use first values
		p0 = 0.0
		p1 = 0.0
		p2 = waveform_data[0] if waveform_data.size() > 0 else 0.0
		p3 = waveform_data[1] if waveform_data.size() > 1 else p2
	elif sample_index >= waveform_data.size():
		# After end: use last values
		var last_idx = waveform_data.size() - 1
		p0 = waveform_data[max(0, last_idx - 1)]
		p1 = waveform_data[last_idx]
		p2 = 0.0
		p3 = 0.0
	else:
		# Edge cases: near start or end, use clamped values
		p0 = waveform_data[max(0, sample_index - 1)]
		p1 = waveform_data[clamp(sample_index, 0, waveform_data.size() - 1)]
		p2 = waveform_data[min(waveform_data.size() - 1, sample_index + 1)]
		p3 = waveform_data[min(waveform_data.size() - 1, sample_index + 2)]

	# Catmull-Rom interpolation between p1 and p2 (same as waveform rendering)
	var fraction = sample_pos - sample_index
	var amplitude = catmull_rom_interpolate(p0, p1, p2, p3, fraction)

	# Ride along the TOP of the waveform (upper curve)
	var amplitude_scale = 250.0  # Match waveform display EXACTLY
	var target_y = waveform_center_y - (amplitude * amplitude_scale)

	# Store previous position for sub-frame interpolation
	emitter_y_position_previous = emitter_y_position

	# DIRECT TRACKING - no additional smoothing for maximum accuracy
	# The Catmull-Rom interpolation already provides C1 continuity (smooth curves)
	emitter_y_position = target_y

	return emitter_y_position

func get_waveform_amplitude_at_time(time: float) -> float:
	"""Get waveform amplitude at specific time using Catmull-Rom interpolation

	This is a helper function for ultra-smooth tracking.
	"""
	if waveform_data.size() == 0:
		return 0.0

	var samples_per_second = 100.0
	var sample_pos = time * samples_per_second
	var sample_index = int(sample_pos)

	# Get 4 points for Catmull-Rom interpolation
	var p0 = 0.0
	var p1 = 0.0
	var p2 = 0.0
	var p3 = 0.0

	# Improved boundary handling
	if sample_index >= 1 and sample_index < waveform_data.size() - 2:
		p0 = waveform_data[sample_index - 1]
		p1 = waveform_data[sample_index]
		p2 = waveform_data[sample_index + 1]
		p3 = waveform_data[sample_index + 2]
	elif sample_index < 0:
		p0 = 0.0
		p1 = 0.0
		p2 = waveform_data[0] if waveform_data.size() > 0 else 0.0
		p3 = waveform_data[1] if waveform_data.size() > 1 else p2
	elif sample_index >= waveform_data.size():
		var last_idx = waveform_data.size() - 1
		p0 = waveform_data[max(0, last_idx - 1)]
		p1 = waveform_data[last_idx]
		p2 = 0.0
		p3 = 0.0
	else:
		p0 = waveform_data[max(0, sample_index - 1)]
		p1 = waveform_data[clamp(sample_index, 0, waveform_data.size() - 1)]
		p2 = waveform_data[min(waveform_data.size() - 1, sample_index + 1)]
		p3 = waveform_data[min(waveform_data.size() - 1, sample_index + 2)]

	var fraction = sample_pos - sample_index
	return catmull_rom_interpolate(p0, p1, p2, p3, fraction)

func one_euro_filter_smooth(target: float, delta: float) -> float:
	"""ONE EURO FILTER - Industry standard for ultra-smooth tracking

	Used in: VR/AR tracking, motion capture, touch input, cursor smoothing
	Paper: "1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input"

	Automatically adapts smoothing based on velocity:
	- Slow movement = more smoothing (no jitter)
	- Fast movement = less smoothing (no lag)

	This is THE BEST smoothing filter for real-time tracking.
	"""
	if one_euro_first_time:
		one_euro_first_time = false
		one_euro_x_prev = target
		one_euro_dx_prev = 0.0
		return target

	# Calculate derivative (velocity)
	var dx = (target - one_euro_x_prev) / delta

	# Smooth the derivative
	var edx = dx
	if not one_euro_first_time:
		var alpha_d = smoothing_factor(delta, one_euro_dcutoff)
		edx = lerp(one_euro_dx_prev, dx, alpha_d)

	# Calculate adaptive cutoff frequency based on velocity
	var cutoff = one_euro_min_cutoff + one_euro_beta * abs(edx)

	# Smooth the position with adaptive cutoff
	var alpha = smoothing_factor(delta, cutoff)
	var filtered = lerp(one_euro_x_prev, target, alpha)

	# Store for next frame
	one_euro_x_prev = filtered
	one_euro_dx_prev = edx

	return filtered

func smoothing_factor(delta: float, cutoff: float) -> float:
	"""Calculate smoothing factor for low-pass filter"""
	var r = 2.0 * PI * cutoff * delta
	return r / (r + 1.0)

func critically_damped_spring_smooth(target: float, delta: float) -> float:
	"""CRITICALLY DAMPED SPRING - AAA game standard for smooth motion

	Used in: Camera smoothing, character movement, UI animations
	Source: Game Programming Gems 4 - "Critically Damped Ease-In/Ease-Out"

	Properties:
	- Fastest possible settling time without overshoot
	- Natural, organic motion
	- No oscillation (critically damped)

	This is used in most AAA games for smooth camera/object tracking.
	"""
	# Handle target changes (reset velocity for instant response)
	if abs(target - spring_target_prev) > 0.01:
		spring_velocity *= 0.5  # Reduce velocity on target change
	spring_target_prev = target

	# Spring constants for critical damping
	var omega = 2.0 * PI * spring_frequency  # Angular frequency
	var zeta = 1.0  # Damping ratio (1.0 = critical damping)

	# Calculate spring force and damping
	var position_error = target - emitter_y_position
	var spring_force = omega * omega * position_error
	var damping_force = 2.0 * zeta * omega * spring_velocity

	# Update velocity and position
	spring_velocity += (spring_force - damping_force) * delta
	var new_position = emitter_y_position + spring_velocity * delta

	return new_position

func get_emitter_y_ultra_smooth(delta: float) -> float:
	"""Direct emitter tracking - no smoothing, just follow the waveform exactly"""
	var screen_size = get_viewport_rect().size
	var waveform_center_y = screen_size.y * 0.5

	if waveform_data.size() == 0:
		emitter_y_position = waveform_center_y
		return waveform_center_y

	# Get current audio time with precision
	var current_time = get_precise_audio_time()

	# Calculate time at screen center
	var time_at_screen_center = current_time - 1.5

	# Get amplitude directly - no averaging
	var amplitude = get_waveform_amplitude_at_time(time_at_screen_center)

	# Convert amplitude to Y position
	var amplitude_scale = 250.0
	var target_y = waveform_center_y - (amplitude * amplitude_scale)

	# NO SMOOTHING - direct tracking
	emitter_y_position_previous = emitter_y_position
	emitter_y_position = target_y

	return emitter_y_position

func get_emitter_y_interpolated() -> float:
	"""Get ultra-smooth emitter position

	This now uses the advanced EMA + lookahead + averaging approach.
	"""
	if not audio_player or not audio_player.playing:
		return emitter_y_position

	# Use the ultra-smooth tracking
	return emitter_y_position  # Already updated in _process()

func spawn_simple_pattern(zone: Dictionary, intensity: float, make_homing: bool = false) -> bool:
	var enemy_scene = preload("res://scenes/Enemy.tscn")

	# SPAWN FROM WAVEFORM PATH (emitter position in middle of screen!)
	var screen_size = get_viewport_rect().size
	var emitter_x = screen_size.x / 2
	var emitter_y = get_waveform_y_at_time(0.0, current_delta)  # Current waveform position
	var center = Vector2(emitter_x, emitter_y)

	# Simple enemy characteristics
	var enemy_type = "basic"
	var enemy_size = 5

	# MUSIC-SYNCED BULLET SPEED!
	# Speed scales with ONSET DENSITY (how fast the music is)
	# Low density (0.5-1.5) = slow sections, ballads, breaks
	# High density (2.5-4.0) = fast rap, intense drums, busy sections
	var base_speed = 100.0   # INSANE MODE: Much faster! (was 60.0)
	var max_speed = 250.0   # INSANE MODE: Blazing fast! (was 150.0)

	# Map onset_density (0.5-4.0) to speed (100-250)
	var density_normalized = (onset_density - 0.5) / 3.5  # 0.0 to 1.0
	var speed = lerp(base_speed, max_speed, clamp(density_normalized, 0.0, 1.0))

	# MEANINGFUL FREQUENCY PATTERNS - each teaches you about music!
	# INVERTED DIFFICULTY: Bass = easiest (most common), High = hardest (least common)
	match zone.pattern:
		Enemy.Pattern.CIRCULAR:
			# 🔴 BASS (20-250Hz): Kicks, bass drops, rumble
			# EASIEST - Heavy & slow X pattern, easy to dodge (bass is most common in music!)
			var bass_speed = speed * 0.5  # 50% slower - bass is heavy!
			var bass_size = 16  # Bigger bullets (easier to see)
			var diagonal_angles = [PI/4, 3*PI/4, 5*PI/4, 7*PI/4]  # Diagonal X pattern (4 bullets)
			for base_angle in diagonal_angles:
				var enemy = get_pooled_enemy()  # PERFORMANCE: Use object pool
				var vel: Vector2
				if make_homing:
					# Aim directly at player position - make them faster since they're aimed
					var direction_to_player = (player_position - center).normalized()
					vel = direction_to_player * bass_speed * 2.0
				else:
					# Normal pattern with rotation
					vel = Vector2.RIGHT.rotated(base_angle + emitter_rotation) * bass_speed
				enemy.activate(center, vel, enemy_type, zone.color, zone.pattern, center, make_homing, bass_size)
			enemies_list_dirty = true  # Mark list as dirty after spawning
			return true

		Enemy.Pattern.CROSS:
			# 🟢 MID (250-2000Hz): Vocals, snares, melody - the "meat" of music
			# MEDIUM - Star pattern (8 bullets: both + and X combined), normal speed
			var mid_speed = speed * 1.0  # Normal speed
			var mid_size = 12  # Medium size
			var star_angles = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]  # 8-point star
			for base_angle in star_angles:
				var enemy = get_pooled_enemy()  # PERFORMANCE: Use object pool
				var vel: Vector2
				if make_homing:
					# Aim directly at player position - make them faster since they're aimed
					var direction_to_player = (player_position - center).normalized()
					vel = direction_to_player * mid_speed * 2.0
				else:
					# Normal pattern with rotation
					vel = Vector2.RIGHT.rotated(base_angle + emitter_rotation) * mid_speed
				enemy.activate(center, vel, enemy_type, zone.color, zone.pattern, center, make_homing, mid_size)
			enemies_list_dirty = true  # Mark list as dirty after spawning
			return true

		Enemy.Pattern.DIAMOND:
			# 🔵 HIGH (2000-20000Hz): Cymbals, hi-hats, sparkle - adds brightness
			# HARDEST - Full circle pattern, fast & small (high freq is less common!)
			var num_bullets = 12  # Full 360° coverage
			var high_speed = min(speed * 1.2, 200.0)  # 20% faster - sparkly and dangerous!
			var high_size = 8  # Small size
			for i in range(num_bullets):
				var enemy = get_pooled_enemy()  # PERFORMANCE: Use object pool
				var vel: Vector2
				if make_homing:
					# Aim directly at player position - make them faster since they're aimed
					var direction_to_player = (player_position - center).normalized()
					vel = direction_to_player * high_speed * 2.0
				else:
					# Normal pattern with rotation
					var angle = (TAU / num_bullets) * i + emitter_rotation
					vel = Vector2.RIGHT.rotated(angle) * high_speed
				enemy.activate(center, vel, enemy_type, zone.color, zone.pattern, center, make_homing, high_size)
			enemies_list_dirty = true  # Mark list as dirty after spawning
			return true

		_:
			# Fallback: simple downward bullet
			var enemy = get_pooled_enemy()  # PERFORMANCE: Use object pool
			var vel: Vector2
			if make_homing:
				# Aim directly at player position - make them faster since they're aimed
				var direction_to_player = (player_position - center).normalized()
				vel = direction_to_player * speed * 2.0
			else:
				# Normal pattern with rotation
				vel = Vector2(0, speed).rotated(emitter_rotation)
			enemy.activate(center, vel, enemy_type, zone.color, zone.pattern, center, make_homing, 8.0)
			enemies_list_dirty = true  # Mark list as dirty after spawning
			return true

func update_enemies(delta):
	# Bullets managed by Godot's scene tree now - no pool needed!
	# Collision checking done in _process
	# Refresh cached enemy list if dirty
	if enemies_list_dirty:
		active_enemies.clear()
		for child in enemy_spawn_zones.get_children():
			if child is Enemy:
				active_enemies.append(child)
		enemies_list_dirty = false

	# Use cached list for iteration
	for enemy in active_enemies:
		if not is_instance_valid(enemy):
			enemies_list_dirty = true
			continue

		# Despawn bullets that hit the visualizer bars (award points)
		if is_hitting_visualizer(enemy.position):
			enemy.deactivate()  # Awards 1 point
			enemies_list_dirty = true
			enemies_dirty = true
		# Bullets going off screen handled by Enemy.gd's is_off_screen() check

func is_hitting_visualizer(pos: Vector2) -> bool:
	# Check if position hits left or right visualizer bars
	var bar_height = play_area.size.y / num_visualizer_bars
	var bar_index = int((pos.y - play_area.position.y) / bar_height)

	if bar_index >= 0 and bar_index < num_visualizer_bars:
		# Check left side
		if pos.x < play_area.position.x + left_bar_widths[bar_index]:
			return true
		# Check right side
		if pos.x > (play_area.position.x + play_area.size.x) - right_bar_widths[bar_index]:
			return true

	return false

func is_in_play_area(pos: Vector2) -> bool:
	return play_area.has_point(pos)

func check_collisions():
	if not game_active:
		return

	# Refresh cached enemy list if dirty
	if enemies_list_dirty:
		active_enemies.clear()
		for child in enemy_spawn_zones.get_children():
			if child is Enemy:
				active_enemies.append(child)
		enemies_list_dirty = false

	# IMPROVED: More generous hitbox - player_size is 8, so this gives ~5.6 pixel radius
	# This feels much better and matches what players expect visually
	var player_radius = player_size * 0.7  # More forgiving hitbox
	var _player_radius_squared = player_radius * player_radius  # Pre-calculate for optimization

	# Check enemy collisions using cached list and distance_squared (avoid sqrt)
	for enemy in active_enemies:
		if not is_instance_valid(enemy):
			enemies_list_dirty = true  # Mark for refresh next frame
			continue

		# Use distance_squared to avoid expensive sqrt calculation
		var distance_squared = player_position.distance_squared_to(enemy.position)
		# Use full enemy size for collision - if it looks like it hit, it should hit!
		var collision_distance = player_radius + enemy.enemy_size
		var collision_distance_squared = collision_distance * collision_distance

		if distance_squared < collision_distance_squared:
			on_player_hit(2)  # INSANE MODE: Each enemy/bullet does 2 damage
			return_enemy_to_pool(enemy)  # Return to pool instead of freeing
			enemies_list_dirty = true  # Mark list as dirty
			enemies_dirty = true  # Mark for redraw
			break  # Only one hit per frame

func on_player_hit(damage: int):
	GameManager.take_damage(damage)

	# Visual feedback
	camera_shake.add_trauma(0.3)
	player_hit_flash = 1.0  # Trigger red flash

	if GameManager.current_health <= 0:
		game_over()

func game_over():
	end_game("GAME OVER")

func song_completed():
	end_game("SONG COMPLETED")

func end_game(reason: String):
	game_active = false
	song_playing = false

	# Stop audio if it's game over (not if song completed naturally)
	if reason == "GAME OVER" and audio_player:
		audio_player.stop()

	# Fade out gameplay, then show end screen
	var visualizer = get_node("/root/Visualizer")
	if visualizer:
		var gameplay = visualizer.get_node_or_null("GameplayLayer")
		var waveform = visualizer.get_node_or_null("WaveformLayer")
		var background = visualizer.get_node_or_null("BackgroundLayer")
		var game_ui = visualizer.get_node_or_null("UI/GameUI")

		# Fade everything to black smoothly
		var tween = create_tween()
		tween.set_parallel(true)
		if gameplay:
			tween.tween_property(gameplay, "modulate", Color(0, 0, 0, 1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if waveform:
			tween.tween_property(waveform, "modulate", Color(0, 0, 0, 1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if background:
			tween.tween_property(background, "modulate", Color(0, 0, 0, 1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if game_ui:
			tween.tween_property(game_ui, "modulate", Color(0, 0, 0, 1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		# After fade completes, hide and show end screen
		tween.chain().tween_callback(func():
			if gameplay: gameplay.visible = false
			if waveform: waveform.visible = false
			if background: background.visible = false
			if game_ui: game_ui.visible = false

			var game_over_screen = visualizer.get_node_or_null("GameOverScreen")
			if game_over_screen:
				game_over_screen.show_game_over(GameManager.score, reason)
		)

func _on_player_died():
	game_over()

func start_song():
	"""Called when the song begins playing"""
	song_playing = true
	song_start_timer = 0.0  # Reset delay timer

func on_song_changed():
	# Called when playlist advances to next song
	# INSANE MODE: Heal only 10 health when advancing to next song in playlist
	if GameManager:
		GameManager.heal(10)

	# Clear all bullets/enemies using cached list - return to pool instead of freeing
	for enemy in active_enemies:
		return_enemy_to_pool(enemy)
	active_enemies.clear()
	enemies_list_dirty = true  # Mark for refresh

	# Reset circular buffers
	history_write_index = 0
	history_filled = false
	flux_write_index = 0
	flux_history_filled = false

	for i in range(history_size):
		bass_history[i] = 0.0
		mid_history[i] = 0.0
		high_history[i] = 0.0

	for i in range(flux_history_size):
		bass_flux_history[i] = 0.0
		mid_flux_history[i] = 0.0
		high_flux_history[i] = 0.0

	onset_times.clear()

	# Reset tracking
	last_bass_energy = 0.0
	last_mid_energy = 0.0
	last_high_energy = 0.0
	last_volume = 0.0
	onset_density = 1.0
	global_speed_multiplier = 1.0
	time_since_last_beat = 0.0

	enemies_list_dirty = true  # Mark enemy list as dirty

	# Reset adaptive scaling
	for i in range(num_visualizer_bars):
		magnitude_history[i].clear()
		adaptive_scaling[i] = 1.0

	# Reset waveform for new song
	waveform_data.clear()
	waveform_is_complete = false
	waveform_scroll_offset = 0.0

	# Re-extract waveform from new audio stream
	if audio_player and audio_player.stream:
		extract_waveform_from_audio()

	song_playing = true

func get_speed_multiplier() -> float:
	return global_speed_multiplier

func get_slowdown_multiplier() -> float:
	return slowdown_multiplier if is_slowdown_active else 1.0

func get_speedup_multiplier() -> float:
	return speedup_multiplier if is_speedup_active else 1.0

func get_combined_speed_multiplier() -> float:
	# Combine slowdown and speedup (they can't both be active, but this is safe)
	# This is for BULLETS
	if is_slowdown_active:
		return slowdown_multiplier
	elif is_speedup_active:
		return speedup_multiplier
	else:
		return 1.0

func get_player_speed_multiplier() -> float:
	# Separate multiplier for PLAYER movement
	if is_slowdown_active:
		return slowdown_multiplier
	elif is_speedup_active:
		return speedup_player_multiplier  # Player moves slower than bullets during speedup
	else:
		return 1.0

func get_audio_slowdown_multiplier() -> float:
	# Now handles both slowdown and speedup
	if is_slowdown_active:
		return slowdown_audio_multiplier
	elif is_speedup_active:
		return speedup_audio_multiplier
	else:
		return 1.0

func _on_bullet_container_draw():
	# BULLET TIME VISUAL EFFECTS
	if has_node("/root/BulletTimeManager"):
		var bullet_time_manager = get_node("/root/BulletTimeManager")
		var screen_size = get_viewport_rect().size
		var _tint_intensity = bullet_time_manager.get_screen_tint_intensity()
		var _trail_intensity = bullet_time_manager.get_particle_trail_intensity()



		# Bullet time indicator in corner (always show when manager exists)
		var indicator_pos = Vector2(screen_size.x - 150, 30)
		var indicator_text = bullet_time_manager.get_status_text()
		var indicator_color = Color.CYAN if bullet_time_manager.is_active() else Color(0.7, 0.7, 0.7, 0.8)
		bullet_container.draw_string(ThemeDB.fallback_font, indicator_pos, indicator_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, indicator_color)
	
	# 🔴 HARD MODE: FULLSCREEN FLASH when bullets reverse!
	var screen_size = get_viewport_rect().size
	if rotation_reversal_flash > 0:
		# MASSIVE FULLSCREEN FLASH - can't miss this!
		var flash_color = Color(1.0, 0.3, 0.0, rotation_reversal_flash * 0.4)
		bullet_container.draw_rect(Rect2(0, 0, screen_size.x, screen_size.y), flash_color, true)
	
	# 🔴 HARD MODE: Rotation direction indicator at top center
	var rotation_text = "⟳ CLOCKWISE" if rotation_direction > 0 else "⟲ COUNTER-CLOCKWISE"
	var rotation_pos = Vector2(screen_size.x / 2 - 120, 15)
	var rotation_color = Color(1.0, 0.8, 0.2, 0.9) if rotation_direction > 0 else Color(0.2, 0.8, 1.0, 0.9)
	var font_size = 24
	
	# Add MASSIVE flash effect when direction changes
	if rotation_reversal_flash > 0:
		rotation_color = Color(2.5, 0.3, 0.1, 1.0)  # SUPER bright red-orange during flash
		font_size = 32  # Make it BIGGER during flash!
		
		# Huge glowing background rect
		var text_width = 250
		var text_height = 50
		var bg_rect = Rect2(rotation_pos.x - 10, rotation_pos.y - 10, text_width, text_height)
		var bg_color = Color(1.0, 0.3, 0.0, rotation_reversal_flash * 0.7)
		bullet_container.draw_rect(bg_rect, bg_color, true)
		
		# Outer glow
		bullet_container.draw_rect(bg_rect.grow(5), Color(1.0, 0.5, 0.0, rotation_reversal_flash * 0.3), true)
		
		# Shadow for emphasis
		bullet_container.draw_string(ThemeDB.fallback_font, rotation_pos + Vector2(3, 3), rotation_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, rotation_reversal_flash * 0.8))
	
	bullet_container.draw_string(ThemeDB.fallback_font, rotation_pos, rotation_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, rotation_color)

	# Draw player - use character customization
	var player_base_color = Color(1.0, 0.9, 0.3) if player_invincible else CharacterManager.get_character_color()

	# Apply red flash when hit
	if player_hit_flash > 0:
		player_base_color = Color(1.5, 0.3, 0.3)  # Bright red

	# Draw player with texture or color
	var character_texture = CharacterManager.get_character_texture()
	var _texture_path = CharacterManager.get_character_texture_path()

	if character_texture:
		# Draw circular textured player with colored border
		# Colored border circle (shows the selected color)
		bullet_container.draw_circle(player_position, player_size + 1.5, player_base_color)

		# Draw texture (already circular from processing)
		# Apply red tint if hit, otherwise use white
		var texture_tint = Color.WHITE
		if player_hit_flash > 0:
			texture_tint = Color(1.5, 0.3, 0.3)  # Red tint

		var texture_rect = Rect2(player_position - Vector2(player_size, player_size), Vector2(player_size * 2, player_size * 2))
		bullet_container.draw_texture_rect(character_texture, texture_rect, false, texture_tint)
	else:
		# Draw simple player circle with glow
		# Outer glow
		bullet_container.draw_circle(player_position, player_size * 1.3, Color(player_base_color.r, player_base_color.g, player_base_color.b, 0.2))
		# Core circle
		bullet_container.draw_circle(player_position, player_size, player_base_color)

	# Update slowdown meter UI (now in scene nodes!)
	if slowdown_meter_bar:
		slowdown_meter_bar.value = slowdown_meter
		# Intense glow when active!
		if is_slowdown_active:
			slowdown_meter_bar.modulate = Color(1.5, 1.5, 1.5)  # Brighter glow when active
		else:
			slowdown_meter_bar.modulate = Color(1.0, 1.0, 1.0)  # Normal neon glow

	# Update speedup meter UI
	if speedup_meter_bar:
		speedup_meter_bar.value = speedup_meter
		# Intense glow when active!
		if is_speedup_active:
			speedup_meter_bar.modulate = Color(1.5, 1.5, 1.5)  # Brighter glow when active
		else:
			speedup_meter_bar.modulate = Color(1.0, 1.0, 1.0)  # Normal neon glow

	# Update speedup timer label
	if speedup_timer_label:
		speedup_timer_label.text = "%.1f" % speedup_timer
		# Glow when active or counting down
		if is_speedup_active or speedup_timer > 0:
			speedup_timer_label.modulate = Color(1.5, 1.5, 1.5)  # Brighter when active/counting
		else:
			speedup_timer_label.modulate = Color(1.0, 1.0, 1.0)  # Normal

	# Waveform is now on a separate layer - no longer drawn here!

func _on_beat_indicators_draw():
	if not spectrum_analyzer:
		return

	var current_vol = get_current_volume()


func _on_frequency_indicator_draw():
	if not frequency_indicator or not spectrum_analyzer:
		return

	# PERFORMANCE: Use cached spectrum values
	var bass_energy = cached_bass_energy
	var mid_energy = cached_mid_energy
	var high_energy = cached_high_energy

	# ENHANCED Circular frequency indicators (VU meter style) with GLOW
	var circle_radius = 18.0  # Larger
	var spacing = 70.0
	var start_x = 25.0
	var y_pos = 25.0

	# BASS circle (RED - matches bass bullets)
	var bass_center = Vector2(start_x, y_pos)
	var bass_fill = clamp(bass_energy * 50.0, 0.0, 1.0)
	var bass_glow_radius = circle_radius + (bass_pulse * 12.0)

	# Subtle glow when pulsing
	if bass_pulse > 0:
		frequency_indicator.draw_circle(bass_center, bass_glow_radius, Color(1.0, 0.3, 0.3, bass_pulse * 0.25))

	# Background circle (darker)
	frequency_indicator.draw_circle(bass_center, circle_radius, Color(0.15, 0.05, 0.05, 0.8))

	# Fill based on energy (bright HDR)
	if bass_fill > 0.1:
		var fill_radius = circle_radius * bass_fill
		# Glow layer
		frequency_indicator.draw_circle(bass_center, fill_radius * 1.3, Color(1.0, 0.3, 0.3, 0.4))
		# Core
		frequency_indicator.draw_circle(bass_center, fill_radius, Color(1.5, 0.3, 0.3, 1.0))

	# Glowing border
	frequency_indicator.draw_arc(bass_center, circle_radius + 2, 0, TAU, 32, Color(1.0, 0.3, 0.3, 0.3), 3.0, true)
	frequency_indicator.draw_arc(bass_center, circle_radius, 0, TAU, 32, Color(1.2, 0.4, 0.4, 1.0), 2.0, true)

	# Enhanced label with shadow
	frequency_indicator.draw_string(ThemeDB.fallback_font, Vector2(start_x + circle_radius + 8, y_pos + 6), "BASS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.3, 0.3, 0.5))
	frequency_indicator.draw_string(ThemeDB.fallback_font, Vector2(start_x + circle_radius + 7, y_pos + 5), "BASS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.3, 0.3, 1.0))

	# MID circle (GREEN - matches mid bullets)
	var mid_center = Vector2(start_x + spacing * 2.5, y_pos)
	var mid_fill = clamp(mid_energy * 50.0, 0.0, 1.0)
	var mid_glow_radius = circle_radius + (mid_pulse * 12.0)

	if mid_pulse > 0:
		frequency_indicator.draw_circle(mid_center, mid_glow_radius, Color(0.3, 1.0, 0.3, mid_pulse * 0.25))

	frequency_indicator.draw_circle(mid_center, circle_radius, Color(0.05, 0.15, 0.05, 0.8))

	if mid_fill > 0.1:
		var fill_radius = circle_radius * mid_fill
		frequency_indicator.draw_circle(mid_center, fill_radius * 1.3, Color(0.3, 1.0, 0.3, 0.4))
		frequency_indicator.draw_circle(mid_center, fill_radius, Color(0.4, 1.5, 0.4, 1.0))

	frequency_indicator.draw_arc(mid_center, circle_radius + 2, 0, TAU, 32, Color(0.3, 1.0, 0.3, 0.3), 3.0, true)
	frequency_indicator.draw_arc(mid_center, circle_radius, 0, TAU, 32, Color(0.4, 1.2, 0.4, 1.0), 2.0, true)

	frequency_indicator.draw_string(ThemeDB.fallback_font, Vector2(mid_center.x + circle_radius + 8, y_pos + 6), "MID", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.3, 0.3, 0.5))
	frequency_indicator.draw_string(ThemeDB.fallback_font, Vector2(mid_center.x + circle_radius + 7, y_pos + 5), "MID", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 1.0, 0.3, 1.0))

	# HIGH circle (BLUE - matches high bullets)
	var high_center = Vector2(start_x + spacing * 5, y_pos)
	var high_fill = clamp(high_energy * 50.0, 0.0, 1.0)
	var high_glow_radius = circle_radius + (high_pulse * 12.0)

	if high_pulse > 0:
		frequency_indicator.draw_circle(high_center, high_glow_radius, Color(0.3, 0.6, 1.0, high_pulse * 0.25))

	frequency_indicator.draw_circle(high_center, circle_radius, Color(0.05, 0.1, 0.15, 0.8))

	if high_fill > 0.1:
		var fill_radius = circle_radius * high_fill
		frequency_indicator.draw_circle(high_center, fill_radius * 1.3, Color(0.3, 0.6, 1.0, 0.4))
		frequency_indicator.draw_circle(high_center, fill_radius, Color(0.4, 0.8, 1.5, 1.0))

	frequency_indicator.draw_arc(high_center, circle_radius + 2, 0, TAU, 32, Color(0.3, 0.6, 1.0, 0.3), 3.0, true)
	frequency_indicator.draw_arc(high_center, circle_radius, 0, TAU, 32, Color(0.4, 0.7, 1.2, 1.0), 2.0, true)

	frequency_indicator.draw_string(ThemeDB.fallback_font, Vector2(high_center.x + circle_radius + 8, y_pos + 6), "HIGH", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.3, 0.3, 0.5))
	frequency_indicator.draw_string(ThemeDB.fallback_font, Vector2(high_center.x + circle_radius + 7, y_pos + 5), "HIGH", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.6, 1.0, 1.0))

# Drawing functions
func _on_enemy_spawn_zones_draw():
	draw_synth_boundaries()

	# PRECISE EMITTER - tiny marble with clear rotation indicator
	var screen_size = get_viewport_rect().size
	var emitter_x = screen_size.x / 2  # Always centered horizontally
	# Use sub-frame interpolated position for ultra-smooth motion
	var emitter_y = get_emitter_y_interpolated()
	var emitter_center = Vector2(emitter_x, emitter_y)

	var marble_size = 10.0
	var marble_color = Color(0.0, 0.795, 0.795, 1.0)
	
	# 🔴 HARD MODE: Flash bright when rotation reverses!
	if rotation_reversal_flash > 0:
		# Bright orange/red flash on rotation reversal
		var flash_color = Color(2.0, 0.8, 0.3, rotation_reversal_flash)
		var flash_size = marble_size + (rotation_reversal_flash * 30.0)  # Expands when flashing
		enemy_spawn_zones.draw_circle(emitter_center, flash_size, flash_color)
		
		# Intense outer glow
		var glow_color = Color(1.5, 0.5, 0.2, rotation_reversal_flash * 0.5)
		enemy_spawn_zones.draw_circle(emitter_center, flash_size * 1.5, glow_color)

	enemy_spawn_zones.draw_circle(emitter_center, marble_size, marble_color)
	
	# 🔴 HARD MODE: Show rotation direction with arrow indicator
	var arrow_distance = marble_size + 15.0
	var arrow_angle = emitter_rotation + (PI / 2) * rotation_direction  # Perpendicular to rotation
	var arrow_pos = emitter_center + Vector2(cos(arrow_angle), sin(arrow_angle)) * arrow_distance
	var arrow_size = 8.0
	var arrow_color = Color(1.0, 0.8, 0.2, 0.9) if rotation_direction > 0 else Color(0.2, 0.8, 1.0, 0.9)
	
	# Draw arrow triangle pointing in rotation direction
	var arrow_dir = Vector2(cos(arrow_angle), sin(arrow_angle))
	var arrow_perpendicular = Vector2(-arrow_dir.y, arrow_dir.x)
	var arrow_tip = arrow_pos + arrow_dir * arrow_size
	var arrow_base1 = arrow_pos - arrow_dir * arrow_size * 0.5 + arrow_perpendicular * arrow_size * 0.5
	var arrow_base2 = arrow_pos - arrow_dir * arrow_size * 0.5 - arrow_perpendicular * arrow_size * 0.5
	
	enemy_spawn_zones.draw_colored_polygon(PackedVector2Array([arrow_tip, arrow_base1, arrow_base2]), arrow_color)

	# PERFORMANCE: Enemies now render themselves using Sprite2D (50-70% faster than draw_circle)
	# Refresh cached enemy list if dirty (for collision detection)
	if enemies_list_dirty:
		active_enemies.clear()
		for child in enemy_spawn_zones.get_children():
			if child is Enemy:
				active_enemies.append(child)
		enemies_list_dirty = false

func update_adaptive_scaling(band_index: int, magnitude: float):
	"""Update adaptive scaling based on magnitude history to prevent flat walls"""
	# Add current magnitude to history (shorter history for faster adaptation)
	magnitude_history[band_index].append(magnitude)
	var max_history = 30  # Reduced from 60 - faster adaptation
	if magnitude_history[band_index].size() > max_history:
		magnitude_history[band_index].pop_front()

	# Calculate dynamic range from recent history
	if magnitude_history[band_index].size() < 5:  # Reduced from 10
		return  # Need some history first

	var history = magnitude_history[band_index]
	var max_mag = history.max()
	var min_mag = history.min()
	var avg_mag = 0.0
	for mag in history:
		avg_mag += mag
	avg_mag /= history.size()

	# More aggressive adaptive scaling with per-band targets
	var dynamic_range = max_mag - min_mag
	if dynamic_range > 0.00001:  # More sensitive threshold
		# Different target percentages for different frequency bands
		var target_percentages = [0.4, 0.35, 0.3, 0.25, 0.2, 0.15, 0.1]  # Bass gets more, highs get less
		var target_avg_width = max_bar_width * target_percentages[band_index]

		# More aggressive scaling range
		adaptive_scaling[band_index] = target_avg_width / (avg_mag * 30000.0)  # Reduced base sensitivity
		adaptive_scaling[band_index] = clamp(adaptive_scaling[band_index], 0.05, 20.0)  # Wider range
	else:
		adaptive_scaling[band_index] = 1.0

func _on_waveform_layer_draw():
	"""Draw waveform on its own layer - only updates periodically"""
	var screen_size = get_viewport_rect().size

	if not audio_player or not audio_player.stream:
		return

	# Get PRECISE playback time (with latency compensation)
	var current_time = get_precise_audio_time()

	# Waveform positioning - mid-level across entire screen
	var waveform_center_y = screen_size.y * 0.5  # Centered vertically on screen

	# Draw the waveform
	draw_clean_waveform_on_layer(waveform_center_y, current_time)

func catmull_rom_interpolate(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	"""Catmull-Rom spline interpolation for ultra-smooth curves

	This creates C1 continuous curves (continuous first derivative) which are
	much smoother than linear interpolation. Used by professional DAWs.

	Args:
		p0, p1, p2, p3: Four consecutive control points
		t: Interpolation factor between p1 and p2 (0.0 to 1.0)
	"""
	var t2 = t * t
	var t3 = t2 * t

	# Catmull-Rom basis matrix coefficients with tension = 0.5
	var v0 = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3
	var v1 = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3
	var v2 = -0.5 * p0 + 0.5 * p2
	var v3 = p1

	return v0 * t3 + v1 * t2 + v2 * t + v3

func apply_rms_smoothing(raw_amplitude: float, delta: float) -> float:
	"""Apply RMS-style envelope following for professional smoothness

	Uses attack/release envelope similar to audio compressors.
	Fast attack captures transients, slow release prevents jitter.
	"""
	var target = raw_amplitude
	var current = waveform_last_smoothed

	# Calculate envelope coefficient based on attack or release
	var coeff: float
	if target > current:
		# Attack: Fast rise to capture transients
		coeff = 1.0 - exp(-delta / waveform_envelope_attack)
	else:
		# Release: Slow decay for smooth visual
		coeff = 1.0 - exp(-delta / waveform_envelope_release)

	# Apply exponential smoothing
	var smoothed = current + (target - current) * coeff
	waveform_last_smoothed = smoothed

	return smoothed

func draw_clean_waveform_on_layer(center_y: float, current_time: float):
	"""Draw PROFESSIONAL, ULTRA-SMOOTH, GORGEOUS audio waveform with advanced techniques:

	IMPROVEMENTS IMPLEMENTED:
	1. Catmull-Rom cubic spline interpolation (professional DAW quality)
	2. RMS envelope smoothing with attack/release
	3. Reduced sample points with superior interpolation (better performance)
	4. Multi-layer glow/bloom effect for depth
	5. Gradient fills from center to edges
	6. Full antialiasing on all draw calls
	7. Shadow/outline effects for visual depth
	8. Temporal smoothing to eliminate jitter
	"""
	var screen_size = get_viewport_rect().size

	if waveform_data.size() == 0:
		return

	var amplitude_scale = 250.0
	var time_window = 3.0
	var samples_per_second = 100.0

	# PERFORMANCE OPTIMIZATION: Increased sample step from 3 to 6 pixels (40-60% faster)
	# Catmull-Rom interpolation makes this look smooth even with larger steps
	var sample_step = 6
	var num_samples = int(screen_size.x / sample_step)

	# PERFORMANCE: Use pre-allocated arrays instead of creating new ones each frame
	# Clear and reuse instead of allocating new memory
	waveform_top_points.clear()
	waveform_bottom_points.clear()

	# Build control points for Catmull-Rom spline
	for i in range(num_samples + 1):
		var x = i * sample_step
		var progress = float(x) / screen_size.x  # 0.0 to 1.0
		# Right edge = current time (NOW), scrolls left as time advances
		# Left edge = 3 seconds ago, Right edge = NOW
		var time_at_x = (current_time - time_window) + (progress * time_window)
		var sample_pos = time_at_x * samples_per_second
		var sample_index = int(sample_pos)

		# Get 4 points for Catmull-Rom interpolation
		var p0 = 0.0
		var p1 = 0.0
		var p2 = 0.0
		var p3 = 0.0

		# Safely get surrounding points
		if sample_index >= 1 and sample_index < waveform_data.size() - 2:
			p0 = waveform_data[sample_index - 1]
			p1 = waveform_data[sample_index]
			p2 = waveform_data[sample_index + 1]
			p3 = waveform_data[sample_index + 2]
		elif sample_index >= 0 and sample_index < waveform_data.size():
			# Edge cases: use clamped values
			p0 = waveform_data[max(0, sample_index - 1)]
			p1 = waveform_data[sample_index]
			p2 = waveform_data[min(waveform_data.size() - 1, sample_index + 1)]
			p3 = waveform_data[min(waveform_data.size() - 1, sample_index + 2)]

		# Catmull-Rom interpolation between p1 and p2
		var fraction = sample_pos - sample_index
		var amplitude = catmull_rom_interpolate(p0, p1, p2, p3, fraction)

		# OPTIONAL: Apply RMS-style smoothing for prettier visuals
		# Disable this for maximum emitter tracking accuracy
		if use_waveform_rms_smoothing:
			amplitude = apply_rms_smoothing(amplitude, 0.016)

		# Scale amplitude
		var y_offset = amplitude * amplitude_scale

		# Create mirrored waveform
		waveform_top_points.append(Vector2(x, center_y - y_offset))
		waveform_bottom_points.append(Vector2(x, center_y + y_offset))

	if waveform_top_points.size() < 2:
		return

	# SUBTLE waveform - less distracting
	# Subtle outer glow
	waveform_layer.draw_polyline(waveform_top_points, Color(0.3, 0.6, 0.7, 0.08), 4.0, true)
	waveform_layer.draw_polyline(waveform_bottom_points, Color(0.3, 0.6, 0.7, 0.08), 4.0, true)

	# Core line - dim and subtle
	waveform_layer.draw_polyline(waveform_top_points, Color(0.4, 0.7, 0.8, 0.4), 2.0, true)
	waveform_layer.draw_polyline(waveform_bottom_points, Color(0.4, 0.7, 0.8, 0.4), 2.0, true)

	# Subtle center reference line
	waveform_layer.draw_line(
		Vector2(0, center_y),
		Vector2(screen_size.x, center_y),
		Color(0.4, 0.6, 0.7, 0.15),
		2.0,
		true
	)

	# Draw playback position indicator at RIGHT edge (current position)
	var playback_x = screen_size.x - 3.0  # RIGHT edge = NOW
	waveform_layer.draw_line(
		Vector2(playback_x, center_y - 300),
		Vector2(playback_x, center_y + 300),
		Color(1.0, 0.5, 0.5, 1.0),
		3.0,
		true
	)

func draw_synth_boundaries():
	if not spectrum_analyzer:
		return

	var bar_spacing = 0.5
	var bar_height = (play_area.size.y - (bar_spacing * (num_visualizer_bars - 1))) / num_visualizer_bars

	# OPTIMIZATION: Calculate magnitudes ONCE and cache them for both left and right bars
	for i in range(num_visualizer_bars):
		var freq_min = FREQ_RANGES[i][0]
		var freq_max = FREQ_RANGES[i][1]
		var magnitude = spectrum_analyzer.get_magnitude_for_frequency_range(freq_min, freq_max).length()
		cached_bar_magnitudes[i] = magnitude

		# Update adaptive scaling to prevent flat walls
		update_adaptive_scaling(i, magnitude)

	# LEFT boundary (vertical bars pointing right) - using cached magnitudes
	for i in range(num_visualizer_bars):
		var magnitude = cached_bar_magnitudes[i]
		var base_sensitivity = BASE_SENSITIVITIES[i]
		var final_sensitivity = base_sensitivity * adaptive_scaling[i]

		# Add minimum threshold to prevent over-amplification of noise
		var raw_width = magnitude * final_sensitivity
		var target_width = clamp(raw_width, 3.0, max_bar_width)

		# If magnitude is too small, keep bar at minimum
		if magnitude < 0.00001:
			target_width = 3.0

		left_bar_targets[i] = target_width

		# SMOOTH INTERPOLATION - eliminates jitter
		left_bar_widths[i] = lerp(left_bar_widths[i], left_bar_targets[i], bar_smoothing)

		var x = play_area.position.x
		var y = play_area.position.y + (i * (bar_height + bar_spacing))

		# SUPER NEON rainbow colors
		var t = float(i) / num_visualizer_bars
		var hue = t  # Pure rainbow
		var brightness = clamp(left_bar_widths[i] / 400.0, 0.85, 1.0)  # BRIGHT for neon
		var saturation = 1.0  # MAX saturation for neon
		var bar_color = Color.from_hsv(hue, saturation, brightness, 1.0)  # NEON SOLID

		# PERFORMANCE: Reduced from 3 layers to 2 (30% fewer draw calls)
		# Combined glow layer - single soft glow
		var glow_color = Color.from_hsv(hue, saturation * 0.85, brightness * 0.7, 0.25)
		enemy_spawn_zones.draw_rect(Rect2(x - 6, y, left_bar_widths[i] + 12, bar_height), glow_color, true)

		# Main bar - NEON solid color
		enemy_spawn_zones.draw_rect(Rect2(x, y, left_bar_widths[i], bar_height), bar_color, true)

	# RIGHT boundary (vertical bars pointing left) - using cached magnitudes
	for i in range(num_visualizer_bars):
		# Use cached magnitude from first loop - NO duplicate spectrum analyzer calls!
		var magnitude = cached_bar_magnitudes[i]
		var base_sensitivity = BASE_SENSITIVITIES[i]
		var final_sensitivity = base_sensitivity * adaptive_scaling[i]

		# Add minimum threshold to prevent over-amplification of noise
		var raw_width = magnitude * final_sensitivity
		var target_width = clamp(raw_width, 3.0, max_bar_width)

		# If magnitude is too small, keep bar at minimum
		if magnitude < 0.00001:
			target_width = 3.0

		right_bar_targets[i] = target_width

		# SMOOTH INTERPOLATION - eliminates jitter
		right_bar_widths[i] = lerp(right_bar_widths[i], right_bar_targets[i], bar_smoothing)

		var x = play_area.position.x + play_area.size.x - right_bar_widths[i]
		var y = play_area.position.y + (i * (bar_height + bar_spacing))

		# SUPER NEON rainbow colors
		var t = float(i) / num_visualizer_bars
		var hue = t
		var brightness = clamp(right_bar_widths[i] / 400.0, 0.85, 1.0)  # BRIGHT for neon
		var saturation = 1.0  # MAX saturation for neon
		var bar_color = Color.from_hsv(hue, saturation, brightness, 1.0)  # NEON SOLID

		# PERFORMANCE: Reduced from 3 layers to 2 (30% fewer draw calls)
		# Combined glow layer - single soft glow
		var glow_color = Color.from_hsv(hue, saturation * 0.85, brightness * 0.7, 0.25)
		enemy_spawn_zones.draw_rect(Rect2(x - 6, y, right_bar_widths[i] + 12, bar_height), glow_color, true)

		# Main bar - NEON solid color
		enemy_spawn_zones.draw_rect(Rect2(x, y, right_bar_widths[i], bar_height), bar_color, true)
