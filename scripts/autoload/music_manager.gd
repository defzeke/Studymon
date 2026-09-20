extends Node
## Persistent background music. Autoloaded, so the track started on the
## loading screen keeps playing across scene changes (loading -> gameplay).

const MAIN_ROOM_TRACK: AudioStream = preload("res://assets/audio/main room.mp3")

var _player: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _sfx_chain_id := 0

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MainRoomPlayer"
	add_child(_player)
	_player.stream = MAIN_ROOM_TRACK
	if _player.stream is AudioStreamMP3:
		(_player.stream as AudioStreamMP3).loop = true
	_player.volume_db = -6.0
	_player.play()
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "SfxPlayer"
	add_child(_sfx)

func ensure_playing() -> void:
	if is_instance_valid(_player) and not _player.playing:
		_player.play()

func stop_music() -> void:
	if is_instance_valid(_player):
		_player.stop()

func set_volume_db(value: float) -> void:
	if is_instance_valid(_player):
		_player.volume_db = value

func play_sfx(stream: AudioStream) -> void:
	_sfx_chain_id += 1
	if not is_instance_valid(_sfx) or stream == null:
		return
	_sfx.stream = stream
	_sfx.play()

func play_sfx_chain(streams: Array) -> void:
	_sfx_chain_id += 1
	var my_id := _sfx_chain_id
	for s in streams:
		if my_id != _sfx_chain_id:
			return
		var st := s as AudioStream
		if st == null or not is_instance_valid(_sfx):
			return
		_sfx.stream = st
		_sfx.play()
		await _sfx.finished
