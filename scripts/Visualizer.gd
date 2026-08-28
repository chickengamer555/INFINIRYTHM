extends Control

# UI References
@onready var audio_player = $AudioStreamPlayer
@onready var score_label = $UI/GameUI/ScoreLabel
@onready var combo_label = $UI/GameUI/ComboLabel
@onready var health_bar = $UI/GameUI/HealthBar
@onready var health_label = $UI/GameUI/HealthLabel
@onready var playback_label = $UI/GameUI/PlaybackLabel

# Layer References
@onready var background_layer = $BackgroundLayer
@onready var gameplay_layer = $GameplayLayer

# Audio analysis
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var audio_capture: AudioEffectCapture  # The capture effect itself, not an instance
var is_playing: bool = false
var current_pitch: float = 1.0  # Track current pitch for smooth transitions

func _ready():
	print("=== VISUALIZER STARTING ===")
	print("Platform: ", OS.get_name())
	print("Godot version: ", Engine.get_version_info())
	print("AudioServer bus count: ", AudioServer.bus_count)

	# CRITICAL MAC FIX: Force audio server initialization
	if OS.get_name() == "macOS":
		print("macOS DETECTED - Applying CoreAudio fixes...")
		# Force audio server to initialize by querying it
		var _bus_count = AudioServer.get_bus_count()
		var _mix_rate = AudioServer.get_mix_rate()
		print("  Mix rate: ", AudioServer.get_mix_rate())
		print("  Output latency: ", AudioServer.get_output_latency())
		# Wait for CoreAudio to be ready
		await get_tree().create_timer(0.1).timeout

	# Connect signals FIRST before resetting game state
	audio_player.finished.connect(_on_audio_finished)
	AudioManager.playlist_ended.connect(_on_playlist_ended)

	# Connect GameManager signals BEFORE reset so initial signals are received
	if GameManager:
		GameManager.score_changed.connect(_on_score_changed)
		GameManager.combo_changed.connect(_on_combo_changed)
		GameManager.health_changed.connect(_on_health_changed)

	# Reset game state AFTER connecting signals so UI gets updated
	if GameManager:
		GameManager.reset_game()

	# Setup audio bus and spectrum analyzer FIRST
	setup_audio_bus()

	# Load audio from AudioManager (but don't play yet)
	if AudioManager.has_audio():
		print("AudioManager has audio - loading...")
		var audio_stream = AudioManager.get_current_audio()
		var file_name = AudioManager.get_current_file_name()
		print("Audio stream: ", audio_stream)
		print("File name: ", file_name)
		if audio_stream:
			# CRITICAL MAC CHECK: Verify stream is valid AudioStreamMP3
			if audio_stream is AudioStreamMP3:
				print("✓ Valid AudioStreamMP3 detected")
				print("  - Data size: ", audio_stream.data.size() if audio_stream.data else 0, " bytes")
				print("  - Loop: ", audio_stream.loop)
				print("  - Length: ", audio_stream.get_length(), " seconds")
			else:
				print("⚠ WARNING: Stream is not AudioStreamMP3, type: ", typeof(audio_stream))

			audio_player.stream = audio_stream

			# NOW extract waveform after stream is loaded
			if gameplay_layer:
				gameplay_layer.set_audio_player(audio_player)
				print("Set audio player on gameplay layer")
	else:
		print("ERROR: AudioManager has no audio!")


	# Wait a frame for the audio bus to be ready, then start playing
	await get_tree().process_frame

	# CRITICAL MAC FIX: Verify audio setup before playing
	print("\n=== PRE-PLAYBACK VERIFICATION ===")
	print("AudioStreamPlayer exists: ", audio_player != null)
	print("AudioStreamPlayer bus: ", audio_player.bus if audio_player else "null")
	print("Stream loaded: ", audio_player.stream != null if audio_player else false)
	print("Spectrum analyzer: ", spectrum_analyzer != null)
	print("Audio capture: ", audio_capture != null)
	print("Bus 'Music' index: ", AudioServer.get_bus_index("Music"))
	print("Bus 'Master' index: ", AudioServer.get_bus_index("Master"))

	# MAC EMERGENCY FALLBACK: If Music bus setup failed, use Master directly
	if audio_player and AudioServer.get_bus_index(audio_player.bus) == -1:
		print("WARNING: Assigned bus '", audio_player.bus, "' doesn't exist! Falling back to Master.")
		audio_player.bus = "Master"
		# Try to get spectrum analyzer from Master bus if available
		if AudioServer.get_bus_effect_count(0) > 0:
			spectrum_analyzer = AudioServer.get_bus_effect_instance(0, 0)

	if audio_player.stream:
		print("\nStarting audio playback...")

		# MAC FIX: Set autoplay BEFORE calling play()
		audio_player.autoplay = false  # Ensure it's off so play() works
		audio_player.stream_paused = false  # Ensure not paused

		# Try to play audio
		audio_player.play()
		is_playing = true

		# Verify playback actually started
		await get_tree().create_timer(0.1).timeout
		print("Audio playing: ", audio_player.playing)
		print("Audio position: ", audio_player.get_playback_position())

		# MAC EMERGENCY: If audio didn't start, try again
		if not audio_player.playing:
			print("⚠ AUDIO FAILED TO START - RETRYING...")
			audio_player.stop()
			await get_tree().create_timer(0.05).timeout
			audio_player.play()
			await get_tree().create_timer(0.05).timeout
			print("Retry result - Audio playing: ", audio_player.playing)

		# Notify gameplay layer that song has started
		if gameplay_layer:
			gameplay_layer.start_song()
			print("Notified gameplay layer song started")

		if not spectrum_analyzer:
			print("ERROR: Spectrum analyzer is NULL!")
		else:
			print("SUCCESS: Spectrum analyzer ready")
	else:
		print("ERROR: No audio stream to play!")
	print("=== VERIFICATION COMPLETE ===\n")

func setup_audio_bus():
	print("=== AUDIO BUS SETUP START ===")
	print("AudioServer bus count: ", AudioServer.bus_count)

	# CRITICAL FOR MAC: Ensure Master bus exists first
	if AudioServer.bus_count == 0:
		print("ERROR: No Master bus found! Creating one...")
		AudioServer.add_bus(0)
		AudioServer.set_bus_name(0, "Master")

	# Create the Music bus if it doesn't exist
	var bus_index = AudioServer.get_bus_index("Music")
	print("Music bus initial index: ", bus_index)

	if bus_index == -1:
		print("Creating Music bus...")
		# Add bus after Master (index 1)
		AudioServer.add_bus(1)
		AudioServer.set_bus_name(1, "Music")
		AudioServer.set_bus_send(1, "Master")  # Send to Master
		bus_index = 1
		print("Music bus created at index: ", bus_index)

	# Clear any existing effects on the bus
	var effect_count = AudioServer.get_bus_effect_count(bus_index)
	print("Clearing ", effect_count, " existing effects...")
	for i in range(effect_count):
		AudioServer.remove_bus_effect(bus_index, 0)

	# Add spectrum analyzer effect to the Music bus
	print("Adding SpectrumAnalyzer effect...")
	var spectrum_effect = AudioEffectSpectrumAnalyzer.new()
	spectrum_effect.buffer_length = 2.0  # 2 seconds of buffer
	spectrum_effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	spectrum_effect.tap_back_pos = 0.01  # Minimal delay
	AudioServer.add_bus_effect(bus_index, spectrum_effect)
	AudioServer.set_bus_effect_enabled(bus_index, 0, true)
	print("SpectrumAnalyzer added")

	# Add AudioEffectCapture to capture real-time audio samples for waveform
	print("Adding AudioEffectCapture effect...")
	var capture_effect = AudioEffectCapture.new()
	capture_effect.buffer_length = 0.5  # 0.5 seconds buffer for waveform capture
	AudioServer.add_bus_effect(bus_index, capture_effect)
	AudioServer.set_bus_effect_enabled(bus_index, 1, true)
	print("AudioEffectCapture added")

	# CRITICAL FOR MAC: Verify bus exists before assignment
	var verify_bus = AudioServer.get_bus_index("Music")
	print("Music bus verify index: ", verify_bus)

	if verify_bus != -1:
		print("Setting audio_player.bus to Music...")
		audio_player.bus = "Music"
		print("Audio player bus set to: ", audio_player.bus)
	else:
		print("CRITICAL ERROR: Music bus not found after creation!")
		return

	# Get the spectrum analyzer instance (instances are needed for real-time analysis)
	print("Getting spectrum analyzer instance...")
	spectrum_analyzer = AudioServer.get_bus_effect_instance(bus_index, 0)
	print("Spectrum analyzer instance: ", spectrum_analyzer)

	# Get the audio capture effect (NOT instance - AudioEffectCapture works differently)
	print("Getting audio capture effect...")
	audio_capture = AudioServer.get_bus_effect(bus_index, 1)
	print("Audio capture effect: ", audio_capture)

	if spectrum_analyzer == null:
		print("ERROR: Failed to get spectrum analyzer instance")
	else:
		print("SUCCESS: Spectrum analyzer ready")

	if audio_capture == null:
		print("ERROR: Failed to get audio capture effect")
	else:
		print("SUCCESS: Audio capture ready")

	# Pass spectrum analyzer and audio capture to both layers
	if background_layer:
		print("Setting spectrum analyzer on background layer...")
		background_layer.set_spectrum_analyzer(spectrum_analyzer)
	if gameplay_layer:
		print("Setting spectrum analyzer and audio capture on gameplay layer...")
		gameplay_layer.set_spectrum_analyzer(spectrum_analyzer)
		gameplay_layer.set_audio_capture(audio_capture)

	print("=== AUDIO BUS SETUP COMPLETE ===")
	print("Final bus count: ", AudioServer.bus_count)
	for i in range(AudioServer.bus_count):
		print("  Bus ", i, ": ", AudioServer.get_bus_name(i))

func force_initial_draw():
	print("Forcing initial draw...")
	if background_layer:
		print("Background layer children: ", background_layer.get_children().size())
		for child in background_layer.get_children():
			print("  - Background child: ", child.name)
			child.queue_redraw()
	if gameplay_layer:
		print("Gameplay layer children: ", gameplay_layer.get_children().size())
		for child in gameplay_layer.get_children():
			print("  - Gameplay child: ", child.name)
			child.queue_redraw()

func _process(_delta):
	# Apply slowdown from gameplay layer
	if gameplay_layer and gameplay_layer.has_method("get_audio_slowdown_multiplier"):
		audio_player.pitch_scale = gameplay_layer.get_audio_slowdown_multiplier()
	else:
		audio_player.pitch_scale = 1.0

	# Update playback time display
	if audio_player and audio_player.stream and playback_label:
		var current_time = audio_player.get_playback_position()
		var total_time = audio_player.stream.get_length()
		playback_label.text = format_time(current_time) + " / " + format_time(total_time)

# Pause menu state
var is_paused: bool = false
@onready var pause_menu = $PauseMenu

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				toggle_pause()

# GameManager signal handlers
func _on_score_changed(new_score: int):
	score_label.text = "Score: " + GameManager.format_score(new_score)

func _on_combo_changed(combo_count: int, multiplier: float):
	# Display multiplier (e.g., "1.0x", "1.5x", "2.3x")
	combo_label.text = "%.1fx" % multiplier

	# Color based on multiplier strength
	if multiplier >= 2.0:
		combo_label.modulate = Color(1.0, 0.3, 0.3)  # Red for 2x+
	elif multiplier >= 1.5:
		combo_label.modulate = Color(1.0, 0.8, 0.0)  # Orange for 1.5x+
	elif multiplier > 1.0:
		combo_label.modulate = Color.YELLOW  # Yellow for building combo
	else:
		combo_label.modulate = Color.WHITE  # White for 1.0x

func _on_health_changed(current: int, maximum: int):
	health_bar.value = (float(current) / float(maximum)) * 100.0
	health_label.text = "Health: %d/%d" % [current, maximum]

	# Color health bar based on health - clear neon colors
	if current <= 20:
		health_bar.modulate = Color(2.5, 0.2, 0.2)  # Bright neon red (danger!)
	elif current <= 50:
		health_bar.modulate = Color(2.2, 2.0, 0.2)  # Bright yellow (warning)
	else:
		health_bar.modulate = Color(0.5, 2.2, 0.6)  # Bright green (healthy)

func _on_audio_finished():
	# Check if loop is enabled for single song
	if not AudioManager.is_playlist() and AudioManager.loop_enabled:
		# Loop single song - just replay it
		audio_player.play()
		is_playing = true

		# Reset gameplay for new loop
		if gameplay_layer:
			gameplay_layer.on_song_changed()
		return

	# If playlist, go to next track
	if AudioManager.is_playlist():
		AudioManager.next_track()

		# Check if next_track() emitted playlist_ended (handled in _on_playlist_ended)
		# If not, load and play next track
		var audio_stream = AudioManager.get_current_audio()
		if audio_stream:
			audio_player.stream = audio_stream
			audio_player.play()
			is_playing = true

			# Tell gameplay layer song changed (so it can reset)
			if gameplay_layer:
				gameplay_layer.on_song_changed()
	else:
		# Single song finished without loop - show completion screen
		is_playing = false
		if gameplay_layer:
			gameplay_layer.song_completed()

func _on_playlist_ended():
	# Playlist ended without loop - show completion screen
	is_playing = false
	if gameplay_layer:
		gameplay_layer.song_completed()

func toggle_pause():
	is_paused = !is_paused

	if is_paused:
		# Pause the entire scene tree FIRST to immediately stop all processing
		get_tree().paused = true
		# Then pause audio (after tree is paused to avoid timing issues)
		audio_player.stream_paused = true
		# Show pause menu
		if pause_menu:
			pause_menu.visible = true
	else:
		# Hide pause menu first
		if pause_menu:
			pause_menu.visible = false
		# Resume audio
		audio_player.stream_paused = false
		# Resume the scene tree LAST to avoid jump
		get_tree().paused = false

func _on_pause_resume_pressed():
	toggle_pause()

# Format seconds to MM:SS format
func format_time(seconds: float) -> String:
	var minutes = int(seconds) / 60
	var secs = int(seconds) % 60
	return "%d:%02d" % [minutes, secs]

func _on_pause_menu_pressed():
	audio_player.stop()
	is_playing = false
	is_paused = false
	# CRITICAL: Unpause the tree before changing scenes so MainMenu buttons work!
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
