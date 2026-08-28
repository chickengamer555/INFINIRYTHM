extends Control

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

# Audio analysis
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var audio_capture: AudioEffectCapture  # The capture effect itself, not an instance

# Object pools
# No pooling needed!

# Player
var player_position: Vector2
var player_velocity: Vector2 = Vector2.ZERO  # For wall push momentum
var player_size: float = 8.0
var player_speed: float = 1.0
var player_invincible: bool = false
var invincible_timer: float = 0.0
var wall_push_friction: float = 200  # How quickly push momentum decays (lower = slides longer)
var wall_push_force: float = 1.0  # How hard walls push the player (OOMPH!)
var player_hit_flash: float = 0.0  # Red flash when hit
var player_hit_flash_duration: float = 0.2  # How long flash lasts

# Slowdown ability
var slowdown_meter: float = 100.0  # 0-100
var slowdown_max: float = 100.0
var slowdown_drain_rate: float = 20.0  # Drain per second when active (5 seconds duration)
var slowdown_recharge_rate: float = 20.0  # Recharge per second when not active
var is_slowdown_active: bool = false
var slowdown_multiplier: float = 0.3  # Slows bullets to 20% speed (very slow)
var slowdown_audio_multiplier: float = 0.5  # Slows audio to 75% speed (less dramatic)
var slowdown_can_activate: bool = true  # Can activate after cooldown
var slowdown_key_released: bool = true  # Track if space bar was released (prevents spam)
var slowdown_cooldown_delay: float =  0.5 # Cooldown delay in seconds before can activate again
var slowdown_cooldown_timer: float = 0.0  # Current cooldown timer

# PROFESSIONAL BEAT DETECTION (research-based)
var beat_cooldown: float = 0.12  # Slightly faster spawns for more bullets on screen
var time_since_last_beat: float = 0.0

# Energy history for dynamic thresholding (1 second = ~60 frames at 60fps)
var bass_history: Array[float] = []
var mid_history: Array[float] = []
var high_history: Array[float] = []
var history_size: int = 43  # 1 second of history for proper averaging

# SPECTRAL FLUX: Track previous spectrum to detect CHANGES (onsets)
var last_bass_energy: float = 0.0
var last_mid_energy: float = 0.0
var last_high_energy: float = 0.0

# ONSET DETECTION: Spectral flux values (how much spectrum changed)
var bass_flux_history: Array[float] = []
var mid_flux_history: Array[float] = []
var high_flux_history: Array[float] = []
var flux_history_size: int = 20  # Rolling window for threshold

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
var max_bar_width: float = 250.0  # Reasonable extension limit

# Dynamic range adjustment for better visualization
var magnitude_history: Array[Array] = []  # Track magnitude history per band
var adaptive_scaling: Array[float] = []  # Per-band scaling factors

# Visual effects

# Game state
var game_active: bool = true
var song_playing: bool = false  # Track if song is actually playing - starts false to prevent initial spawn
var current_delta: float = 0.0  # Current frame delta time for physics calculations

func _ready():
	# Initialize player position
	var screen_size = get_viewport_rect().size
	player_position = Vector2(screen_size.x / 2, screen_size.y * 0.8)

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

	# Initialize visualizer bar arrays
	left_bar_widths.resize(num_visualizer_bars)
	right_bar_widths.resize(num_visualizer_bars)
	left_bar_targets.resize(num_visualizer_bars)
	right_bar_targets.resize(num_visualizer_bars)
	magnitude_history.resize(num_visualizer_bars)
	adaptive_scaling.resize(num_visualizer_bars)

	for i in range(num_visualizer_bars):
		left_bar_widths[i] = 2.0
		right_bar_widths[i] = 2.0
		left_bar_targets[i] = 2.0
		right_bar_targets[i] = 2.0
		magnitude_history[i] = []
		adaptive_scaling[i] = 1.0

	# No pooling needed - direct instantiation is faster!

	# Initialize beat zones
	initialize_beat_zones()

	# Setup camera shake


	# Connect to GameManager signals
	if GameManager:
		GameManager.player_died.connect(_on_player_died)

# REMOVED: Object pooling - not needed for rhythm games!
# Godot's reference counting handles memory efficiently without pooling

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

# Removed test spawn - only audio-reactive spawning now

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
	var stereo = stream.stereo
	var mix_rate = stream.mix_rate

	song_duration = stream.get_length()

	# Calculate how many waveform samples we need
	var total_audio_samples = audio_data.size()

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

	# Update player
	update_player_input(delta)
	update_invincibility(delta)

	# Update audio-reactive systems
	if spectrum_analyzer:
		update_beat_detection(delta)
		update_waveform(delta)

	# Update ULTRA-SMOOTH emitter position every frame
	if audio_player and audio_player.playing:
		get_emitter_y_ultra_smooth(delta)

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

	# Update emitter rotation (clockwise) - slow and smooth
	emitter_rotation += delta * 0.3  # 0.3 radians per second (~17 degrees/sec)

	# Spawn flash removed for cleaner visuals

	# Update waveform periodically (not every frame!)
	waveform_update_timer -= delta
	if waveform_update_timer <= 0.0:
		waveform_update_timer = waveform_update_interval
		if waveform_layer:
			waveform_layer.queue_redraw()

	# Redraw
	enemy_spawn_zones.queue_redraw()
	bullet_container.queue_redraw()
	beat_indicators.queue_redraw()
	if frequency_indicator:
		frequency_indicator.queue_redraw()

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

	# Update slowdown cooldown timer
	if slowdown_cooldown_timer > 0:
		slowdown_cooldown_timer -= delta
		if slowdown_cooldown_timer <= 0:
			slowdown_can_activate = true

	# Slowdown ability (Space bar) - with cooldown delay!
	# Can only START activating if meter has charge AND key was released AND cooldown finished
	if Input.is_action_pressed("bullet_time") and slowdown_can_activate and slowdown_key_released and slowdown_meter > 0:
		is_slowdown_active = true
		slowdown_key_released = false  # Lock until released (prevents spam)

	# While active, drain the meter (can hold space!)
	if is_slowdown_active:
		slowdown_meter = max(0, slowdown_meter - slowdown_drain_rate * delta)

		# Force deactivate when meter hits 0 OR space released
		if slowdown_meter <= 0 or not Input.is_action_pressed("bullet_time"):
			is_slowdown_active = false
			slowdown_can_activate = false
			slowdown_cooldown_timer = slowdown_cooldown_delay  # Start cooldown

	# Recharge when not active
	if not is_slowdown_active:
		slowdown_meter = min(slowdown_max, slowdown_meter + slowdown_recharge_rate * delta)

	# Track if space bar was released (for anti-spam)
	if not Input.is_action_pressed("bullet_time"):
		slowdown_key_released = true

	# Move player with input
	if input_vector.length() > 0:
		input_vector = input_vector.normalized()
		# Apply slowdown multiplier to player speed too!
		var speed_multiplier = get_slowdown_multiplier()
		player_position += input_vector * player_speed * delta * speed_multiplier

	# Apply wall push momentum (walls push you and you keep moving!)
	player_position += player_velocity * delta

	# Apply friction to wall push velocity (gradually slow down)
	player_velocity = player_velocity.move_toward(Vector2.ZERO, wall_push_friction * delta * 100.0)

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
	# Scale time passage by audio slowdown so beats spawn at same rate as music
	var time_scale = get_audio_slowdown_multiplier()
	time_since_last_beat += delta * time_scale

	# SIMPLE 3-BAND FREQUENCY ANALYSIS (clean and responsive)

	# Get 3 main frequency bands
	var bass_energy = spectrum_analyzer.get_magnitude_for_frequency_range(20.0, 250.0).length()         # Bass: kicks, bass
	var mid_energy = spectrum_analyzer.get_magnitude_for_frequency_range(250.0, 2000.0).length()        # Mid: snares, vocals, melody
	var high_energy = spectrum_analyzer.get_magnitude_for_frequency_range(2000.0, 20000.0).length()     # High: cymbals, hi-hats

	# Store current total for compatibility
	var current_volume = bass_energy + mid_energy + high_energy

	# Track volume history
	volume_history.append(current_volume)
	if volume_history.size() > max_history_size:
		volume_history.pop_front()

	# Calculate average recent volume
	var avg_volume = 0.0
	for v in volume_history:
		avg_volume += v
	avg_volume /= max(1, volume_history.size())

	# SIMPLE 3-BAND BEAT DETECTION (clean and responsive)
	var beat_detected = false
	var beat_type = ""
	var beat_intensity = 0.0
	var dominant_frequency = ""

	# PROFESSIONAL BEAT DETECTION ALGORITHM
	# Based on industry research: dynamic variance-based thresholding

	# Update energy history (maintain 1 second of data)
	bass_history.append(bass_energy)
	if bass_history.size() > history_size:
		bass_history.pop_front()

	mid_history.append(mid_energy)
	if mid_history.size() > history_size:
		mid_history.pop_front()

	high_history.append(high_energy)
	if high_history.size() > history_size:
		high_history.pop_front()

	# Calculate averages
	var bass_avg = 0.0
	var mid_avg = 0.0
	var high_avg = 0.0

	for v in bass_history:
		bass_avg += v
	bass_avg /= max(1, bass_history.size())

	for v in mid_history:
		mid_avg += v
	mid_avg /= max(1, mid_history.size())

	for v in high_history:
		high_avg += v
	high_avg /= max(1, high_history.size())

	# SPECTRAL FLUX ONSET DETECTION
	# Calculate how much each band CHANGED (not just how loud it is)
	var bass_flux = max(0.0, bass_energy - last_bass_energy)  # Only positive changes (half-wave rectification)
	var mid_flux = max(0.0, mid_energy - last_mid_energy)
	var high_flux = max(0.0, high_energy - last_high_energy)

	# Track flux history for dynamic thresholding
	bass_flux_history.append(bass_flux)
	if bass_flux_history.size() > flux_history_size:
		bass_flux_history.pop_front()

	mid_flux_history.append(mid_flux)
	if mid_flux_history.size() > flux_history_size:
		mid_flux_history.pop_front()

	high_flux_history.append(high_flux)
	if high_flux_history.size() > flux_history_size:
		high_flux_history.pop_front()

	# Calculate flux averages (local mean)
	var bass_flux_avg = 0.0
	for f in bass_flux_history:
		bass_flux_avg += f
	bass_flux_avg /= max(1, bass_flux_history.size())

	var mid_flux_avg = 0.0
	for f in mid_flux_history:
		mid_flux_avg += f
	mid_flux_avg /= max(1, mid_flux_history.size())

	var high_flux_avg = 0.0
	for f in high_flux_history:
		high_flux_avg += f
	high_flux_avg /= max(1, high_flux_history.size())

	# ONSET DETECTION: Flux > Threshold × Average (research recommends 1.5x)
	var sensitivity = 1.4  # Recommended range: 1.3-1.6
	var spawned_any = false
	var is_rising = current_volume > last_volume

	# Detect onsets in each band independently
	var bass_onset = bass_flux > sensitivity * bass_flux_avg and bass_flux > 0.001
	var mid_onset = mid_flux > sensitivity * mid_flux_avg and mid_flux > 0.001
	var high_onset = high_flux > sensitivity * high_flux_avg and high_flux > 0.001

	# Only spawn if cooldown passed AND we detected an onset AND song is playing AND audio is actually playing
	var audio_is_playing = audio_player and audio_player.playing
	if song_playing and audio_is_playing and not is_slowdown_active and time_since_last_beat >= beat_cooldown and (bass_onset or mid_onset or high_onset):
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

	# Calculate onset density (onsets per second)
	var current_time = Time.get_ticks_msec() / 1000.0
	var cutoff_time = current_time - onset_window

	# Remove old onsets outside the window
	while onset_times.size() > 0 and onset_times[0] < cutoff_time:
		onset_times.pop_front()

	# Calculate density: number of onsets / time window
	onset_density = onset_times.size() / onset_window
	onset_density = clamp(onset_density, 0.5, 4.0)  # Reasonable range

	# NO SPEED MULTIPLIER - keep bullets at constant speed
	global_speed_multiplier = 1.0

	# ENHANCED: Trigger dramatic bullet time effects on strong audio events
	if has_node("/root/BulletTimeManager"):
		var bullet_time_manager = get_node("/root/BulletTimeManager")
		if bullet_time_manager.audio_reactive_enabled:
			# Trigger slowdown on strong bass drops (kick drums, bass drops)
			if bass_onset and bass_flux > 0.8:
				var bass_intensity = clamp((bass_flux - 0.8) / 0.2, 0.0, 1.0)  # 0.8-1.0 -> 0.0-1.0
				bullet_time_manager.trigger_audio_reactive_slowdown(bass_intensity, 1.8)

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
	var spawn_success = spawn_simple_pattern(zone, intensity)

	# Spawn flash removed for cleaner visuals

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
	return spectrum_analyzer.get_magnitude_for_frequency_range(20.0, 20000.0).length()

func is_too_close_to_player(pos: Vector2, min_distance: float = 200.0) -> bool:
	return pos.distance_to(player_position) < min_distance

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

func spawn_simple_pattern(zone: Dictionary, intensity: float) -> bool:
	# NO POOLING - Direct instantiation!
	var enemy_scene = preload("res://Enemy.tscn")

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
	var base_speed = 60.0   # Slow sections (reduced from 100)
	var max_speed = 150.0   # Fast/intense sections (reduced from 250)

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
			var bass_size = 12  # Bigger bullets (easier to see)
			var diagonal_angles = [PI/4, 3*PI/4, 5*PI/4, 7*PI/4]  # Diagonal X pattern (4 bullets)
			for base_angle in diagonal_angles:
				var enemy = enemy_scene.instantiate()
				var vel = Vector2.RIGHT.rotated(base_angle + emitter_rotation) * bass_speed  # Apply rotation
				enemy_spawn_zones.add_child(enemy)
				enemy.activate(center, vel, enemy_type, zone.color, zone.pattern, center)  # Pass emitter position
				enemy.enemy_size = bass_size  # THICC bass bullets
			return true

		Enemy.Pattern.CROSS:
			# 🟢 MID (250-2000Hz): Vocals, snares, melody - the "meat" of music
			# MEDIUM - Star pattern (8 bullets: both + and X combined), normal speed
			var mid_speed = speed * 1.0  # Normal speed
			var mid_size = 8  # Normal size
			var star_angles = [0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]  # 8-point star
			for base_angle in star_angles:
				var enemy = enemy_scene.instantiate()
				var vel = Vector2.RIGHT.rotated(base_angle + emitter_rotation) * mid_speed  # Apply rotation
				enemy_spawn_zones.add_child(enemy)
				enemy.activate(center, vel, enemy_type, zone.color, zone.pattern, center)  # Pass emitter position
				enemy.enemy_size = mid_size
			return true

		Enemy.Pattern.DIAMOND:
			# 🔵 HIGH (2000-20000Hz): Cymbals, hi-hats, sparkle - adds brightness
			# HARDEST - Full circle pattern, fast & small (high freq is less common!)
			var num_bullets = 12  # Full 360° coverage
			var high_speed = min(speed * 1.2, 200.0)  # 20% faster - sparkly and dangerous!
			var high_size = 6  # Smaller, harder to see
			for i in range(num_bullets):
				var enemy = enemy_scene.instantiate()
				var angle = (TAU / num_bullets) * i + emitter_rotation  # Apply rotation
				var vel = Vector2.RIGHT.rotated(angle) * high_speed
				enemy_spawn_zones.add_child(enemy)
				enemy.activate(center, vel, enemy_type, zone.color, zone.pattern, center)  # Pass emitter position
				enemy.enemy_size = high_size
			return true

		_:
			# Fallback: simple downward bullet
			var enemy = enemy_scene.instantiate()
			var vel = Vector2(0, speed).rotated(emitter_rotation)  # Apply rotation
			enemy_spawn_zones.add_child(enemy)
			enemy.activate(center, vel, enemy_type, zone.color, zone.pattern, center)  # Pass emitter position
			enemy.enemy_size = enemy_size
			return true

func update_enemies(delta):
	# Bullets managed by Godot's scene tree now - no pool needed!
	# Collision checking done in _process
	for enemy in enemy_spawn_zones.get_children():
		if enemy is Enemy:
			# Despawn bullets that hit the visualizer bars (award points)
			if is_hitting_visualizer(enemy.position):
				enemy.deactivate()  # Awards 1 point
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

	# IMPROVED: More generous hitbox - player_size is 8, so this gives ~5.6 pixel radius
	# This feels much better and matches what players expect visually
	var player_radius = player_size * 0.7  # More forgiving hitbox

	# Check enemy collisions (enemies ARE the bullets)
	for enemy in enemy_spawn_zones.get_children():
		if enemy is Enemy:
			# Precise distance-based collision
			var distance = player_position.distance_to(enemy.position)
			# Use full enemy size for collision - if it looks like it hit, it should hit!
			var collision_distance = player_radius + enemy.enemy_size

			if distance < collision_distance:
				on_player_hit(1)  # Each enemy/bullet does 1 damage
				enemy.queue_free()  # Remove on hit (NO points awarded)
				break  # Only one hit per frame

func on_player_hit(damage: int):
	GameManager.take_damage(damage)

	# Visual feedback
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

func on_song_changed():
	# Called when playlist advances to next song
	# Clear all bullets/enemies
	for enemy in enemy_spawn_zones.get_children():
		if enemy is Enemy:
			enemy.queue_free()

	# Reset onset detection history
	bass_flux_history.clear()
	mid_flux_history.clear()
	high_flux_history.clear()
	onset_times.clear()

	# Reset energy history
	bass_history.clear()
	mid_history.clear()
	high_history.clear()

	# Reset tracking
	last_bass_energy = 0.0
	last_mid_energy = 0.0
	last_high_energy = 0.0
	last_volume = 0.0
	onset_density = 1.0
	global_speed_multiplier = 1.0
	time_since_last_beat = 0.0

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

func get_audio_slowdown_multiplier() -> float:
	if is_slowdown_active:
		return slowdown_audio_multiplier
	else:
		return 1.0

func _on_bullet_container_draw():
	# BULLET TIME VISUAL EFFECTS
	if has_node("/root/BulletTimeManager"):
		var bullet_time_manager = get_node("/root/BulletTimeManager")
		var screen_size = get_viewport_rect().size


	# Draw player with MAXIMUM VISIBILITY
	var player_base_color = Color(1.0, 0.9, 0.3) if player_invincible else Color(0.9, 0.95, 1.0)

	# Apply red flash when hit
	if player_hit_flash > 0:
		var flash_amount = player_hit_flash
		player_base_color = Color(1.5, 0.3, 0.3)  # Bright red



func _on_beat_indicators_draw():
	if not spectrum_analyzer:
		return

	var current_vol = get_current_volume()

	# NO SCREEN FLASHES - removed for cleaner experience
	# Visual feedback now comes only from colored bullet patterns

func _on_frequency_indicator_draw():
	if not frequency_indicator or not spectrum_analyzer:
		return

	# Get current energies
	var bass_energy = spectrum_analyzer.get_magnitude_for_frequency_range(20.0, 250.0).length()
	var mid_energy = spectrum_analyzer.get_magnitude_for_frequency_range(250.0, 2000.0).length()
	var high_energy = spectrum_analyzer.get_magnitude_for_frequency_range(2000.0, 20000.0).length()

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
	# DRAW WAVEFORM FIRST (visible audio visualization!)

	# Draw synth wave boundaries (play area walls) - will be on sides
	draw_synth_boundaries()

	# PRECISE EMITTER - tiny marble with clear rotation indicator
	var screen_size = get_viewport_rect().size
	var emitter_x = screen_size.x / 2  # Always centered horizontally
	# Use sub-frame interpolated position for ultra-smooth motion
	var emitter_y = get_emitter_y_interpolated()
	var emitter_center = Vector2(emitter_x, emitter_y)

	# VISIBLE marble for debugging
	var marble_size = 10.0  # Larger so you can see it clearly

	# Bright visible color
	var marble_color = Color(0.0, 0.795, 0.795, 1.0)  # BRIGHT YELLOW for visibility

	enemy_spawn_zones.draw_circle(emitter_center, marble_size, marble_color)

	# Draw enemies with layered glow
	for enemy in enemy_spawn_zones.get_children():
		if enemy is Enemy:
			# Outer glow - very soft and subtle
			var outer_glow = Color(enemy.enemy_color.r, enemy.enemy_color.g, enemy.enemy_color.b, 0.15)
			enemy_spawn_zones.draw_circle(enemy.position, enemy.enemy_size * 2.2, outer_glow)

			# Middle glow - medium intensity
			var mid_glow = Color(enemy.enemy_color.r, enemy.enemy_color.g, enemy.enemy_color.b, 0.4)
			enemy_spawn_zones.draw_circle(enemy.position, enemy.enemy_size * 1.5, mid_glow)

			# Core - solid and bright but not HDR
			var core_color = Color(
				enemy.enemy_color.r * 1.3,
				enemy.enemy_color.g * 1.3,
				enemy.enemy_color.b * 1.3,
				1.0
			)
			enemy_spawn_zones.draw_circle(enemy.position, enemy.enemy_size, core_color)

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

	# OLD WAVEFORM CODE REMOVED - now drawn on separate WaveformLayer

	# Note: Audio timeline now drawn on bullet container for better visibility

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

	# OPTIMIZATION: Sample every 2-3 pixels instead of every pixel
	# Catmull-Rom interpolation makes this look better than per-pixel linear
	var sample_step = 2
	var num_samples = int(screen_size.x / sample_step)

	var top_points: PackedVector2Array = []
	var bottom_points: PackedVector2Array = []

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
		top_points.append(Vector2(x, center_y - y_offset))
		bottom_points.append(Vector2(x, center_y + y_offset))

	if top_points.size() < 2:
		return

	# SUBTLE waveform - less distracting
	# Subtle outer glow
	waveform_layer.draw_polyline(top_points, Color(0.3, 0.6, 0.7, 0.08), 4.0, true)
	waveform_layer.draw_polyline(bottom_points, Color(0.3, 0.6, 0.7, 0.08), 4.0, true)

	# Core line - dim and subtle
	waveform_layer.draw_polyline(top_points, Color(0.4, 0.7, 0.8, 0.4), 2.0, true)
	waveform_layer.draw_polyline(bottom_points, Color(0.4, 0.7, 0.8, 0.4), 2.0, true)

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

	# RAINBOW EQUALIZER - LEFT AND RIGHT SIDES ONLY!
	var bar_spacing = 0.5  # Minimal spacing

	# Nice smooth rainbow gradient (no time shift, just pure rainbow)
	var bar_height = (play_area.size.y - (bar_spacing * (num_visualizer_bars - 1))) / num_visualizer_bars

	# LEFT boundary (vertical bars pointing right) - ADAPTIVE SCALING!
	for i in range(num_visualizer_bars):
		# Better frequency ranges - more focused on musical content
		var freq_ranges = [
			[20.0, 80.0],       # Sub-bass (kick drums)
			[80.0, 250.0],      # Bass (bass guitar, low vocals)
			[250.0, 500.0],     # Low-mid (vocals, instruments)
			[500.0, 1000.0],    # Mid (vocals, snare)
			[1000.0, 2000.0],   # High-mid (vocals, instruments)
			[2000.0, 4000.0],   # Presence (vocals, cymbals)
			[4000.0, 8000.0]    # Brilliance (cymbals, hi-hats)
		]
		var freq_min = freq_ranges[i][0]
		var freq_max = freq_ranges[i][1]
		var magnitude = spectrum_analyzer.get_magnitude_for_frequency_range(freq_min, freq_max).length()

		# Update adaptive scaling to prevent flat walls
		update_adaptive_scaling(i, magnitude)

		# Different base sensitivities per frequency band for more variation
		var base_sensitivities = [40000.0, 45000.0, 50000.0, 55000.0, 60000.0, 35000.0, 25000.0]
		var base_sensitivity = base_sensitivities[i]
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

		# Outer glow layer - soft and wide
		var outer_glow = Color.from_hsv(hue, saturation * 0.8, brightness * 0.6, 0.15)
		enemy_spawn_zones.draw_rect(Rect2(x - 8, y, left_bar_widths[i] + 16, bar_height), outer_glow, true)

		# Middle glow layer
		var mid_glow = Color.from_hsv(hue, saturation * 0.9, brightness * 0.8, 0.4)
		enemy_spawn_zones.draw_rect(Rect2(x - 4, y, left_bar_widths[i] + 8, bar_height), mid_glow, true)

		# Main bar - NEON solid color
		enemy_spawn_zones.draw_rect(Rect2(x, y, left_bar_widths[i], bar_height), bar_color, true)

	# RIGHT boundary (vertical bars pointing left) - ADAPTIVE SCALING!
	for i in range(num_visualizer_bars):
		var freq_ranges = [
			[20.0, 80.0],       # Sub-bass (kick drums)
			[80.0, 250.0],      # Bass (bass guitar, low vocals)
			[250.0, 500.0],     # Low-mid (vocals, instruments)
			[500.0, 1000.0],    # Mid (vocals, snare)
			[1000.0, 2000.0],   # High-mid (vocals, instruments)
			[2000.0, 4000.0],   # Presence (vocals, cymbals)
			[4000.0, 8000.0]    # Brilliance (cymbals, hi-hats)
		]
		var freq_min = freq_ranges[i][0]
		var freq_max = freq_ranges[i][1]
		var magnitude = spectrum_analyzer.get_magnitude_for_frequency_range(freq_min, freq_max).length()

		# Use same adaptive scaling and base sensitivities as left side
		var base_sensitivities = [40000.0, 45000.0, 50000.0, 55000.0, 60000.0, 35000.0, 25000.0]
		var base_sensitivity = base_sensitivities[i]
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

		# Outer glow layer - soft and wide
		var outer_glow = Color.from_hsv(hue, saturation * 0.8, brightness * 0.6, 0.15)
		enemy_spawn_zones.draw_rect(Rect2(x - 8, y, right_bar_widths[i] + 16, bar_height), outer_glow, true)

		# Middle glow layer
		var mid_glow = Color.from_hsv(hue, saturation * 0.9, brightness * 0.8, 0.4)
		enemy_spawn_zones.draw_rect(Rect2(x - 4, y, right_bar_widths[i] + 8, bar_height), mid_glow, true)

		# Main bar - NEON solid color
		enemy_spawn_zones.draw_rect(Rect2(x, y, right_bar_widths[i], bar_height), bar_color, true)
