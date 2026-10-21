extends Node
## Persistent background music. Autoloaded; the player survives scene changes and swaps tracks.

const MAIN_ROOM_TRACK: AudioStream = preload("res://assets/audio/main room.mp3")
const LOADING_TRACK: AudioStream = preload("res://assets/audio/loading.mp3")
const LOADING_OFFSET := 1.0
const LOADING_FADE := 1.0
# The track's mix level at full music volume (-6 dB).
const MUSIC_LEVEL := 0.5

## Settings sliders, 0..1; saved by SaveManager.
var music_volume := 1.0
var sfx_volume := 1.0

var _player: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _music_fade: Tween
var _sfx_chain_id := 0

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	add_child(_player)
	_play_track(MAIN_ROOM_TRACK)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "SfxPlayer"
	add_child(_sfx)

func play_loading() -> void:
	_play_track(LOADING_TRACK, LOADING_OFFSET, LOADING_FADE)

func play_main_room() -> void:
	_play_track(MAIN_ROOM_TRACK)

func _play_track(track: AudioStream, from_position := 0.0, fade_in := 0.0) -> void:
	if not is_instance_valid(_player):
		return
	if _player.stream == track and _player.playing:
		return
	_kill_music_fade()
	_player.stream = track
	if _player.stream is AudioStreamMP3:
		(_player.stream as AudioStreamMP3).loop = true
	var target := MUSIC_LEVEL * music_volume
	if fade_in > 0.0:
		_player.volume_linear = 0.0
	else:
		_player.volume_linear = target
	_player.play(from_position)
	if fade_in > 0.0:
		_music_fade = create_tween()
		_music_fade.tween_property(_player, "volume_linear", target, fade_in)

func _kill_music_fade() -> void:
	if _music_fade and _music_fade.is_valid():
		_music_fade.kill()
	_music_fade = null

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	if is_instance_valid(_player):
		_kill_music_fade()
		_player.volume_linear = MUSIC_LEVEL * music_volume

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	if is_instance_valid(_sfx):
		_sfx.volume_linear = sfx_volume

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
