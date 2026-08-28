extends Node

# Singleton for managing character customization
# Stores player color and texture preferences with persistence

signal character_changed

# Character data
var character_color: Color = Color.WHITE  # Default white
var character_texture_path: String = ""  # Empty = use color only
var character_texture: Texture2D = null  # Cached texture

# Save file path
var save_file_path: String = "user://character_data.cfg"

func _ready():
	# Load character data from disk on startup
	load_character_data()

func set_character_color(color: Color):
	character_color = color
	save_character_data()
	character_changed.emit()

func get_character_color() -> Color:
	return character_color

func set_character_texture(texture_path: String):
	print("CharacterManager: Setting texture to: ", texture_path)
	character_texture_path = texture_path

	# Load the texture if path is valid
	if texture_path != "":
		character_texture = _load_and_resize_texture(texture_path)
		print("CharacterManager: Texture loaded: ", character_texture)
	else:
		character_texture = null
		print("CharacterManager: Texture cleared")

	save_character_data()
	character_changed.emit()

func get_character_texture() -> Texture2D:
	return character_texture

func get_character_texture_path() -> String:
	return character_texture_path

func reset_to_default():
	character_color = Color.WHITE
	character_texture_path = ""
	character_texture = null
	save_character_data()
	character_changed.emit()

func save_character_data():
	var config = ConfigFile.new()
	config.set_value("character", "color_r", character_color.r)
	config.set_value("character", "color_g", character_color.g)
	config.set_value("character", "color_b", character_color.b)
	config.set_value("character", "color_a", character_color.a)
	config.set_value("character", "texture_path", character_texture_path)
	var error = config.save(save_file_path)
	print("CharacterManager: Saved to ", save_file_path, " Error: ", error)
	print("  Color: ", character_color)
	print("  Texture path: ", character_texture_path)

func load_character_data():
	var config = ConfigFile.new()
	var error = config.load(save_file_path)

	if error == OK:
		var r = config.get_value("character", "color_r", 1.0)
		var g = config.get_value("character", "color_g", 1.0)
		var b = config.get_value("character", "color_b", 1.0)
		var a = config.get_value("character", "color_a", 1.0)
		character_color = Color(r, g, b, a)

		character_texture_path = config.get_value("character", "texture_path", "")

		# Load texture if path exists
		if character_texture_path != "":
			character_texture = _load_and_resize_texture(character_texture_path)
	else:
		# Use defaults if no save file
		character_color = Color.WHITE
		character_texture_path = ""
		character_texture = null

func _load_and_resize_texture(texture_path: String) -> Texture2D:
	"""Load an image from file, crop to square, resize to 256x256, and convert to perfect circle"""
	var image = Image.new()
	if image.load(texture_path) != OK:
		return null

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

	return ImageTexture.create_from_image(square_image)
