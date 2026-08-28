extends Node

# Singleton for managing audio data across scenes
var playlist: Array[AudioStreamMP3] = []
var playlist_paths: Array[String] = []
var current_index: int = 0

# Shuffle/Loop settings
var shuffle_enabled: bool = false
var loop_enabled: bool = false
var played_indices: Array[int] = []  # Track which songs have been played in shuffle mode

signal audio_loaded(stream: AudioStreamMP3, file_path: String)
signal playlist_changed(index: int, total: int)
signal playlist_ended()  # Emitted when playlist ends (no loop)

func set_playlist(streams: Array[AudioStreamMP3], paths: Array[String], start_index: int = 0):
	playlist = streams
	playlist_paths = paths
	current_index = start_index
	played_indices.clear()
	played_indices.append(current_index)  # Mark first song as played

	if playlist.size() > 0:
		print("AudioManager: Loaded playlist with ", playlist.size(), " songs")
		print("AudioManager: Shuffle=%s, Loop=%s" % [shuffle_enabled, loop_enabled])
		playlist_changed.emit(current_index, playlist.size())
		audio_loaded.emit(playlist[current_index], playlist_paths[current_index])

func next_track():
	if playlist.size() == 0:
		return

	if shuffle_enabled:
		# Shuffle mode: pick random unplayed song
		if played_indices.size() >= playlist.size():
			# All songs played
			if loop_enabled:
				# Restart shuffle - clear played list (except current song to avoid immediate repeat)
				var last_played = current_index
				played_indices.clear()
				played_indices.append(last_played)  # Don't replay the song we just finished
			else:
				# Playlist ended
				playlist_ended.emit()
				return

		# Pick random unplayed index
		var available_indices: Array[int] = []
		for i in range(playlist.size()):
			if not played_indices.has(i):
				available_indices.append(i)

		if available_indices.size() > 0:
			current_index = available_indices[randi() % available_indices.size()]
			played_indices.append(current_index)
			print("AudioManager: Shuffle picked song #%d (available: %s, played: %s)" % [current_index, available_indices, played_indices])
		else:
			# No available indices - shouldn't happen, but handle it
			playlist_ended.emit()
			return
	else:
		# Sequential mode
		current_index = current_index + 1

		if current_index >= playlist.size():
			# Reached end of playlist
			if loop_enabled:
				# Loop back to start
				current_index = 0
			else:
				# Playlist ended
				playlist_ended.emit()
				return

	playlist_changed.emit(current_index, playlist.size())
	audio_loaded.emit(playlist[current_index], playlist_paths[current_index])

func previous_track():
	if playlist.size() == 0:
		return

	current_index = (current_index - 1 + playlist.size()) % playlist.size()
	playlist_changed.emit(current_index, playlist.size())
	audio_loaded.emit(playlist[current_index], playlist_paths[current_index])

func get_current_audio() -> AudioStreamMP3:
	if playlist.size() > 0 and current_index < playlist.size():
		return playlist[current_index]
	return null

func get_current_file_path() -> String:
	if playlist_paths.size() > 0 and current_index < playlist_paths.size():
		return playlist_paths[current_index]
	return ""

func get_current_file_name() -> String:
	var path = get_current_file_path()
	return path.get_file() if path != "" else ""

func has_audio() -> bool:
	return playlist.size() > 0

func is_playlist() -> bool:
	return playlist.size() > 1
