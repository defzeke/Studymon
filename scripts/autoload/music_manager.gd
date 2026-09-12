extends Node
## Persistent background music. Autoloaded, so the track started on the
## loading screen keeps playing across scene changes (loading -> gameplay).

const MAIN_ROOM_TRACK: AudioStream = preload("res://assets/audio/main room.mp3")

var _player: AudioStreamPlayer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MainRoomPlayer"
	add_child(_player)
	_player.stream = MAIN_ROOM_TRACK
	if _player.stream is AudioStreamMP3:
		(_player.stream as AudioStreamMP3).loop = true
	_player.volume_db = -6.0
	_player.play()

func ensure_playing() -> void:
	if is_instance_valid(_player) and not _player.playing:
		_player.play()

func stop_music() -> void:
	if is_instance_valid(_player):
		_player.stop()

func set_volume_db(value: float) -> void:
	if is_instance_valid(_player):
		_player.volume_db = value
