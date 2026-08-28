extends Control

# Character Creator UI
# Allows players to customize their character with color and texture

@onready var color_picker = $Panel/VBoxContainer/ColorPickerContainer/ColorPickerButton
@onready var texture_button = $Panel/VBoxContainer/TextureContainer/TextureButton
@onready var texture_status_label = $Panel/VBoxContainer/TextureContainer/TextureStatusLabel
@onready var file_dialog = $FileDialog
@onready var preview_canvas = $Panel/VBoxContainer/PreviewContainer/PreviewCanvas
@onready var back_button = $Panel/VBoxContainer/ButtonContainer/BackButton
@onready var apply_button = $Panel/VBoxContainer/ButtonContainer/ApplyButton
@onready var reset_button = $Panel/VBoxContainer/ButtonContainer/ResetButton

var current_color: Color = Color.WHITE
var current_texture_path: String = ""
var current_texture: Texture2D = null

func _ready():
	# Load current character settings
	current_color = CharacterManager.get_character_color()
	current_texture_path = CharacterManager.get_character_texture_path()
	current_texture = CharacterManager.get_character_texture()

	# Setup color picker
	color_picker.color = current_color
	color_picker.color_changed.connect(_on_color_changed)

	# Customize the color picker to look clean
	_customize_color_picker()

	# Setup texture button
	texture_button.pressed.connect(_on_texture_button_pressed)

	# Setup file dialog
	file_dialog.file_selected.connect(_on_texture_file_selected)
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png ; PNG Images", "*.jpg ; JPG Images", "*.jpeg ; JPEG Images"])

	# Set file dialog to Downloads folder
	var downloads_path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	file_dialog.current_dir = downloads_path

	# Setup buttons
	back_button.pressed.connect(_on_back_pressed)
	apply_button.pressed.connect(_on_apply_pressed)
	reset_button.pressed.connect(_on_reset_pressed)

	# Setup preview canvas drawing
	preview_canvas.draw.connect(_on_preview_canvas_draw)

	# Update texture status label
	_update_texture_status()

func _customize_color_picker():
	"""Make the color picker look clean and beautiful"""
	# Get the actual ColorPicker popup
	var picker = color_picker.get_picker()

	# Hide all the ugly modes and sliders - keep only the wheel
	picker.color_mode = ColorPicker.MODE_HSV
	picker.picker_shape = ColorPicker.SHAPE_VHS_CIRCLE
	picker.can_add_swatches = false
	picker.sampler_visible = false
	picker.color_modes_visible = false
	picker.sliders_visible = false
	picker.hex_visible = false
	picker.presets_visible = false

	# Get the popup window and make it full black background
	var popup = color_picker.get_popup()

	# Create a full black background style
	var black_bg = StyleBoxFlat.new()
	black_bg.bg_color = Color(0, 0, 0, 1)  # Full black, no transparency

	# Apply to the popup panel
	popup.add_theme_stylebox_override("panel", black_bg)

func _on_color_changed(color: Color):
	current_color = color
	preview_canvas.queue_redraw()

func _on_texture_button_pressed():
	file_dialog.popup_centered_ratio(0.7)

func _on_texture_file_selected(path: String):
	# Try to load it as a file
	var image = Image.new()
	var load_error = image.load(path)

	if load_error == OK:
		# Crop image to square from center (this ensures perfect circle)
		var original_width = image.get_width()
		var original_height = image.get_height()
		var crop_size = min(original_width, original_height)

		# Calculate crop position (center of image)
		var crop_x = (original_width - crop_size) / 2.0
		var crop_y = (original_height - crop_size) / 2.0

		# Create square cropped image
		var square_image = image.get_region(Rect2i(crop_x, crop_y, crop_size, crop_size))

		# Resize to 256x256 for performance
		var max_size = 256
		if square_image.get_width() > max_size:
			square_image.resize(max_size, max_size, Image.INTERPOLATE_LANCZOS)

		# Ensure RGBA8 format for transparency
		if square_image.get_format() != Image.FORMAT_RGBA8:
			square_image.convert(Image.FORMAT_RGBA8)

		# Create smooth circular mask with anti-aliasing
		var size = square_image.get_width()
		var center = size / 2.0
		var radius = size / 2.0 - 0.5

		for x in range(size):
			for y in range(size):
				var dx = x - center + 0.5
				var dy = y - center + 0.5
				var distance = sqrt(dx * dx + dy * dy)

				var pixel = square_image.get_pixel(x, y)
				if distance > radius + 1.0:
					# Fully transparent outside
					pixel.a = 0.0
				elif distance > radius:
					# Smooth fade at edge
					pixel.a *= (1.0 - (distance - radius))

				square_image.set_pixel(x, y, pixel)

		current_texture = ImageTexture.create_from_image(square_image)
		current_texture_path = path
		print("Texture loaded and converted to perfect circle: ", path)
		_update_texture_status()
		preview_canvas.queue_redraw()
	else:
		print("Failed to load image: ", path, " Error code: ", load_error)
		texture_status_label.text = "Failed to load image!"
		texture_status_label.modulate = Color.RED

func _update_texture_status():
	if current_texture_path == "":
		texture_status_label.text = "No texture selected"
		texture_status_label.modulate = Color(0.7, 0.95, 1, 1)
	else:
		var filename = current_texture_path.get_file()
		texture_status_label.text = "Selected: " + filename
		texture_status_label.modulate = Color(0.5, 0.9, 1, 1)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_apply_pressed():
	print("Apply pressed!")
	print("Current color: ", current_color)
	print("Current texture path: ", current_texture_path)
	print("Current texture: ", current_texture)
	CharacterManager.set_character_color(current_color)
	CharacterManager.set_character_texture(current_texture_path)
	print("Character data saved!")
	# Don't exit, just save the changes

func _on_reset_pressed():
	current_color = Color.WHITE
	current_texture_path = ""
	current_texture = null
	color_picker.color = current_color
	_update_texture_status()
	preview_canvas.queue_redraw()

func _on_preview_canvas_draw():
	# Draw preview of character on the canvas
	var canvas_size = preview_canvas.size
	var center = canvas_size / 2
	var player_size = 50.0

	# Draw background
	preview_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), Color(0.05, 0.05, 0.15, 1.0))

	# Draw border
	preview_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), Color(0.4, 0.75, 1, 0.9), false, 3.0)

	if current_texture:
		# Draw circular texture with colored border
		# Outer colored border (shows the selected color)
		preview_canvas.draw_circle(center, player_size + 3.0, current_color)

		# Draw texture (already circular from processing)
		var texture_rect = Rect2(center - Vector2(player_size, player_size), Vector2(player_size * 2, player_size * 2))
		preview_canvas.draw_texture_rect(current_texture, texture_rect, false, Color.WHITE)
	else:
		# Draw color circle with glow
		# Outer glow
		preview_canvas.draw_circle(center, player_size * 1.4, Color(current_color.r, current_color.g, current_color.b, 0.2))
		# Middle glow
		preview_canvas.draw_circle(center, player_size * 1.2, Color(current_color.r, current_color.g, current_color.b, 0.4))
		# Core circle
		preview_canvas.draw_circle(center, player_size, current_color)

