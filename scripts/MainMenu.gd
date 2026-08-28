extends Control

# References to UI elements
@onready var load_button = $VBoxContainer/LoadButton
@onready var play_button = $VBoxContainer/PlayButtonContainer/PlayButton
@onready var controls_button = $VBoxContainer/ControlsButton
@onready var character_button = $VBoxContainer/CharacterButton
@onready var exit_button = $VBoxContainer/ExitButton
@onready var status_label = $VBoxContainer/StatusLabel
@onready var file_dialog = $FileDialog
@onready var shuffle_button = $VBoxContainer/OptionsContainer/ShuffleButton
@onready var loop_button = $VBoxContainer/OptionsContainer/LoopButton
@onready var mode_button = $VBoxContainer/OptionsContainer/ModeButton
@onready var controls_popup = $ControlsPopup
@onready var left_arrow = $VBoxContainer/PlayButtonContainer/LeftArrow
@onready var right_arrow = $VBoxContainer/PlayButtonContainer/RightArrow

# Audio management
var loaded_audio_streams: Array[AudioStreamMP3] = []
var loaded_file_paths: Array[String] = []
var current_playlist_index: int = 0

# Gamemode management - use GameManager's enum
var current_difficulty: GameManager.DifficultyMode = GameManager.DifficultyMode.NORMAL

# Save file path for difficulty
var difficulty_save_path: String = "user://difficulty_settings.cfg"

func _ready():
	# Load difficulty setting from disk
	load_difficulty_setting()
	# Connect signals
	load_button.pressed.connect(_on_load_button_pressed)
	play_button.pressed.connect(_on_play_button_pressed)
	controls_button.pressed.connect(_on_controls_button_pressed)
	character_button.pressed.connect(_on_character_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	file_dialog.files_selected.connect(_on_file_dialog_files_selected)  # Multi-select!
	shuffle_button.toggled.connect(_on_shuffle_button_toggled)
	loop_button.toggled.connect(_on_loop_button_toggled)
	mode_button.pressed.connect(_on_mode_button_pressed)

	# Connect controls popup close button
	if controls_popup:
		controls_popup.get_node("Panel/VBoxContainer/CloseButton").pressed.connect(_on_controls_close_pressed)
		controls_popup.visible = false

	# Set file dialog to Windows Downloads folder
	var downloads_path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	file_dialog.current_dir = downloads_path
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES  # Enable multi-select!

	# Initial state
	play_button.disabled = true
	status_label.text = "No audio file loaded"

	# Set initial button colors (off state)
	shuffle_button.modulate = Color(0.6, 0.6, 0.6, 1)
	loop_button.modulate = Color(0.6, 0.6, 0.6, 1)

	# Hide arrows since we only have one mode now
	left_arrow.visible = false
	right_arrow.visible = false

	# Restore playlist from AudioManager if it exists (returning from CharacterCreator)
	if AudioManager.has_audio():
		loaded_audio_streams = AudioManager.playlist.duplicate()
		loaded_file_paths = AudioManager.playlist_paths.duplicate()
		current_playlist_index = AudioManager.current_index
		shuffle_button.button_pressed = AudioManager.shuffle_enabled
		loop_button.button_pressed = AudioManager.loop_enabled

		# Update UI
		if loaded_audio_streams.size() > 0:
			if loaded_audio_streams.size() == 1:
				play_button.text = "Play"
				status_label.text = "Loaded: " + loaded_file_paths[0].get_file()
			else:
				play_button.text = "Play Playlist"
				status_label.text = "Loaded: " + str(loaded_audio_streams.size()) + " songs"
			status_label.modulate = Color.GREEN
			play_button.disabled = false

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_L:
				_on_load_button_pressed()
			KEY_SPACE, KEY_ENTER:
				if not play_button.disabled:
					_on_play_button_pressed()

func _on_load_button_pressed():
	file_dialog.popup_centered()

func _on_file_dialog_files_selected(paths: PackedStringArray):
	# Clear previous playlist
	loaded_audio_streams.clear()
	loaded_file_paths.clear()
	current_playlist_index = 0

	# Load all selected files
	for path in paths:
		load_mp3_file(path)

	# Update UI based on loaded count
	if loaded_audio_streams.size() > 0:
		if loaded_audio_streams.size() == 1:
			play_button.text = "Play"
			status_label.text = "Loaded: " + loaded_file_paths[0].get_file()
		else:
			play_button.text = "Play Playlist"
			status_label.text = "Loaded: " + str(loaded_audio_streams.size()) + " songs"
		status_label.modulate = Color.GREEN
		play_button.disabled = false
	else:
		show_error("No valid MP3 files loaded!")

func load_mp3_file(file_path: String) -> bool:
	# Check if file exists
	if not FileAccess.file_exists(file_path):
		return false

	# Check file extension
	if not file_path.to_lower().ends_with(".mp3"):
		return false

	# Load the MP3 file
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return false

	# Check file size
	var file_size = file.get_length()
	if file_size > 100 * 1024 * 1024:  # 100MB limit
		file.close()
		return false

	if file_size == 0:
		file.close()
		return false

	# Read the file data
	var file_data = file.get_buffer(file_size)
	file.close()

	# Verify we got data
	if file_data.size() == 0:
		return false

	# Create AudioStreamMP3 and set the data
	var audio_stream = AudioStreamMP3.new()
	audio_stream.data = file_data

	# Verify the stream was created successfully
	if audio_stream.get_length() <= 0:
		return false

	# Add to playlist arrays
	loaded_audio_streams.append(audio_stream)
	loaded_file_paths.append(file_path)

	return true

func show_error(message: String):
	status_label.text = message
	status_label.modulate = Color.RED
	play_button.disabled = true

func _on_play_button_pressed():
	if loaded_audio_streams.size() > 0:
		# Store the playlist in AudioManager with shuffle/loop settings
		AudioManager.set_playlist(loaded_audio_streams, loaded_file_paths, 0)
		AudioManager.shuffle_enabled = shuffle_button.button_pressed
		AudioManager.loop_enabled = loop_button.button_pressed

		# Set difficulty in GameManager
		if GameManager:
			GameManager.set_difficulty(current_difficulty)

		# Switch to the appropriate visualizer scene based on difficulty
		var scene_path = "res://scenes/Visualizer.tscn"
		if current_difficulty == GameManager.DifficultyMode.HARD:
			scene_path = "res://scenes/VisualizerHard.tscn"
			print("LOADING HARD MODE: ", scene_path)
		elif current_difficulty == GameManager.DifficultyMode.INSANE:
			scene_path = "res://scenes/VisualizerInsane.tscn"
			print("LOADING INSANE MODE: ", scene_path)
		else:
			print("LOADING NORMAL MODE: ", scene_path)

		get_tree().change_scene_to_file(scene_path)
	else:
		status_label.text = "No audio loaded!"
		status_label.modulate = Color.RED

func _on_shuffle_button_toggled(toggled_on: bool):
	if toggled_on:
		shuffle_button.modulate = Color(0.5, 0.9, 1, 1)  # Bright blue when on
	else:
		shuffle_button.modulate = Color(0.6, 0.6, 0.6, 1)  # Gray when off

func _on_loop_button_toggled(toggled_on: bool):
	if toggled_on:
		loop_button.modulate = Color(0.5, 0.9, 1, 1)  # Bright blue when on
	else:
		loop_button.modulate = Color(0.6, 0.6, 0.6, 1)  # Gray when off

func _on_controls_button_pressed():
	if controls_popup:
		controls_popup.visible = true

func _on_controls_close_pressed():
	if controls_popup:
		controls_popup.visible = false

func _on_character_button_pressed():
	# Store the current playlist state in AudioManager before switching
	if loaded_audio_streams.size() > 0:
		AudioManager.set_playlist(loaded_audio_streams, loaded_file_paths, current_playlist_index)
		AudioManager.shuffle_enabled = shuffle_button.button_pressed
		AudioManager.loop_enabled = loop_button.button_pressed
	get_tree().change_scene_to_file("res://scenes/CharacterCreator.tscn")

func _on_exit_button_pressed():
	get_tree().quit()

func _on_mode_button_pressed():
	# Cycle through NORMAL -> HARD -> INSANE -> NORMAL
	if current_difficulty == GameManager.DifficultyMode.NORMAL:
		current_difficulty = GameManager.DifficultyMode.HARD
		mode_button.text = "HARD"
		mode_button.modulate = Color(1.0, 0.3, 0.3)  # Red for hard mode
	elif current_difficulty == GameManager.DifficultyMode.HARD:
		current_difficulty = GameManager.DifficultyMode.INSANE
		mode_button.text = "INSANE"
		mode_button.modulate = Color(0.6, 0.0, 0.8)  # Purple for insane mode
	else:
		current_difficulty = GameManager.DifficultyMode.NORMAL
		mode_button.text = "NORMAL"
		mode_button.modulate = Color(0.5, 0.9, 1, 1)  # Blue for normal mode

	# Save the difficulty setting
	save_difficulty_setting()

func save_difficulty_setting():
	var config = ConfigFile.new()
	config.set_value("difficulty", "mode", current_difficulty)
	var error = config.save(difficulty_save_path)
	if error == OK:
		print("MainMenu: Saved difficulty setting: ", get_difficulty_name())
	else:
		print("MainMenu: Failed to save difficulty - Error: ", error)

func load_difficulty_setting():
	var config = ConfigFile.new()
	var error = config.load(difficulty_save_path)

	if error == OK:
		# Load difficulty mode
		current_difficulty = config.get_value("difficulty", "mode", GameManager.DifficultyMode.NORMAL)
		print("MainMenu: Loaded difficulty setting: ", get_difficulty_name())
	else:
		# File doesn't exist - use default
		print("MainMenu: No difficulty save file found, using NORMAL")
		current_difficulty = GameManager.DifficultyMode.NORMAL

	# Update the mode button to reflect loaded difficulty
	update_mode_button()

func update_mode_button():
	match current_difficulty:
		GameManager.DifficultyMode.NORMAL:
			mode_button.text = "NORMAL"
			mode_button.modulate = Color(0.5, 0.9, 1, 1)  # Blue
		GameManager.DifficultyMode.HARD:
			mode_button.text = "HARD"
			mode_button.modulate = Color(1.0, 0.3, 0.3)  # Red
		GameManager.DifficultyMode.INSANE:
			mode_button.text = "INSANE"
			mode_button.modulate = Color(0.6, 0.0, 0.8)  # Purple

func get_difficulty_name() -> String:
	match current_difficulty:
		GameManager.DifficultyMode.NORMAL:
			return "NORMAL"
		GameManager.DifficultyMode.HARD:
			return "HARD"
		GameManager.DifficultyMode.INSANE:
			return "INSANE"
		_:
			return "NORMAL"
