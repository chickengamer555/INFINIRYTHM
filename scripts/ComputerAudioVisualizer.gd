extends Control

# This script captures computer audio from the default microphone/input device
# To capture system audio, you need to configure your system to route audio output to input
# (e.g., Stereo Mix on Windows, or virtual audio cables)

# UI References
@onready var score_label = $UI/GameUI/ScoreLabel
@onready var combo_label = $UI/GameUI/ComboLabel
@onready var health_bar = $UI/GameUI/HealthBar
@onready var health_label = $UI/GameUI/HealthLabel
@onready var playback_label = $UI/GameUI/PlaybackLabel

# Layer References
@onready var background_layer = $BackgroundLayer
@onready var gameplay_layer = $GameplayLayer

# Audio capture
var audio_input: AudioStreamMicrophone
var audio_player: AudioStreamPlayer
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var audio_capture: AudioEffectCapture
var is_playing: bool = false

func _ready():
	# CRITICAL: Enable audio input for microphone capture
	# This is disabled globally to fix Mac audio issues in main game
	ProjectSettings.set_setting("audio/driver/enable_input", true)
	print("Audio input enabled for microphone capture")

	# Connect GameManager signals BEFORE reset so initial signals are received
	if GameManager:
		GameManager.score_changed.connect(_on_score_changed)
		GameManager.combo_changed.connect(_on_combo_changed)
		GameManager.health_changed.connect(_on_health_changed)

	# Reset game state AFTER connecting signals so UI gets updated
	if GameManager:
		GameManager.reset_game()

	# Setup audio capture from microphone/system audio
	setup_audio_capture()

	# Wait a frame for everything to be ready
	await get_tree().process_frame

	# Start capturing
	if audio_player:
		audio_player.play()
		is_playing = true

		# Notify gameplay layer that capture has started
		if gameplay_layer:
			gameplay_layer.start_song()
			print("Computer audio capture started!")

func setup_audio_capture():
	# Create AudioStreamPlayer if not exists
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)

	# Create microphone stream to capture system audio
	audio_input = AudioStreamMicrophone.new()
	audio_player.stream = audio_input

	# Create the Capture bus if it doesn't exist
	var bus_index = AudioServer.get_bus_index("Capture")
	if bus_index == -1:
		bus_index = AudioServer.bus_count
		AudioServer.add_bus(bus_index)
		AudioServer.set_bus_name(bus_index, "Capture")

	# Clear any existing effects on the bus
	var effect_count = AudioServer.get_bus_effect_count(bus_index)
	for i in range(effect_count):
		AudioServer.remove_bus_effect(bus_index, 0)

	# Add spectrum analyzer effect
	var spectrum_effect = AudioEffectSpectrumAnalyzer.new()
	spectrum_effect.buffer_length = 2.0
	spectrum_effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	spectrum_effect.tap_back_pos = 0.01
	AudioServer.add_bus_effect(bus_index, spectrum_effect)
	AudioServer.set_bus_effect_enabled(bus_index, 0, true)

	# Add AudioEffectCapture for waveform
	var capture_effect = AudioEffectCapture.new()
	capture_effect.buffer_length = 0.5
	AudioServer.add_bus_effect(bus_index, capture_effect)
	AudioServer.set_bus_effect_enabled(bus_index, 1, true)

	# Route audio player to Capture bus
	audio_player.bus = "Capture"

	# Get effect instances
	spectrum_analyzer = AudioServer.get_bus_effect_instance(bus_index, 0)
	audio_capture = AudioServer.get_bus_effect(bus_index, 1)

	if spectrum_analyzer == null:
		print("ERROR: Failed to get spectrum analyzer instance")
	if audio_capture == null:
		print("ERROR: Failed to get audio capture effect")

	# Pass to layers
	if background_layer:
		background_layer.set_spectrum_analyzer(spectrum_analyzer)
	if gameplay_layer:
		gameplay_layer.set_spectrum_analyzer(spectrum_analyzer)
		gameplay_layer.set_audio_capture(audio_capture)
		gameplay_layer.set_audio_player(audio_player)

	print("Computer audio capture initialized!")
	print("Available audio input devices:")
	var devices = AudioServer.get_input_device_list()
	for i in range(devices.size()):
		print("  [", i, "] ", devices[i])
	print("Current device: ", AudioServer.input_device)

	# Try to find and use Stereo Mix or other loopback devices
	var found_device = false
	for device in devices:
		if "Stereo Mix" in device or "Wave Out" in device or "What U Hear" in device or "Loopback" in device or "WASAPI" in device:
			print("\n✓ Found system audio device: ", device)
			# Note: Due to Godot bug #75603, device switching may not work on Windows
			# User must set this as default device in Windows Sound settings
			var old_device = AudioServer.input_device
			AudioServer.input_device = device
			print("Attempted to switch from '", old_device, "' to '", device, "'")
			print("Current device is now: ", AudioServer.input_device)
			found_device = true
			break

	if not found_device:
		print("\n⚠ WARNING: No system audio loopback device found!")
		print("Currently using: ", AudioServer.input_device)
		print("This will only capture physical microphone audio.\n")

	print("\n=== SETUP INSTRUCTIONS ===")
	print("To capture audio from YouTube/Spotify/etc, you MUST enable Stereo Mix:")
	print("")
	print("1. Right-click speaker icon in Windows taskbar")
	print("2. Click 'Sounds' → 'Recording' tab")
	print("3. Right-click in empty space → Check BOTH:")
	print("   • 'Show Disabled Devices'")
	print("   • 'Show Disconnected Devices'")
	print("4. Look for 'Stereo Mix' or 'Wave Out Mix' or 'What U Hear'")
	print("5. If found: Right-click → Enable")
	print("6. Right-click again → 'Set as Default Device'")
	print("7. Click OK and RESTART THIS GAME")
	print("")
	print("IF STEREO MIX IS NOT AVAILABLE:")
	print("• Your sound card may not support it")
	print("• Try updating your audio drivers")
	print("• Some laptops/PCs don't have this feature")
	print("")
	print("Current status: ", "READY - Stereo Mix detected!" if found_device else "NOT READY - Using microphone only")
	print("==========================\n")

func _process(delta):
	# NOTE: pitch_scale causes stuttering with AudioStreamMicrophone (Godot bug #99930)
	# Bullet time slowdown is handled visually in gameplay layer only
	# Audio capture continues at normal speed for better sync
	audio_player.pitch_scale = 1.0

	# Update playback time display (elapsed time only for microphone input)
	if audio_player and playback_label:
		var _current_time = audio_player.get_playback_position()
		playback_label.text = format_time(_current_time)

# Pause menu state
var is_paused: bool = false
@onready var pause_menu = $PauseMenu

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			toggle_pause()

func toggle_pause():
	is_paused = !is_paused
	if is_paused:
		pause_menu.visible = true
		get_tree().paused = true
		if audio_player:
			audio_player.stream_paused = true
	else:
		pause_menu.visible = false
		get_tree().paused = false
		if audio_player:
			audio_player.stream_paused = false

func _on_pause_resume_pressed():
	toggle_pause()

func _on_pause_menu_pressed():
	if audio_player:
		audio_player.stop()
	is_paused = false
	# CRITICAL: Unpause the tree before changing scenes so MainMenu buttons work!
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_score_changed(score: int):
	if score_label:
		score_label.text = "SCORE: " + GameManager.format_score(score)

func _on_combo_changed(_combo_count: int, multiplier: float):
	if combo_label:
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
	if health_bar:
		health_bar.value = current
	if health_label:
		health_label.text = str(current) + " HP"

	# Check for game over
	if current <= 0:
		game_over()

func game_over():
	print("GAME OVER!")
	if audio_player:
		audio_player.stop()
	get_tree().paused = true
	$GameOverScreen.show_game_over(GameManager.score, "GAME OVER")

# Format seconds to MM:SS format
func format_time(seconds: float) -> String:
	var minutes = int(seconds) / 60
	var secs = int(seconds) % 60
	return "%d:%02d" % [minutes, secs]
