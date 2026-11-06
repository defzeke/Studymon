extends Node
## Persistent background music. Autoloaded; the player survives scene changes and swaps tracks.

# Studymon's own loops (composed in code, see docs/ui-and-assets.md §4): each WAV is written so its
# end flows into its start, and is looped here at runtime.
const MAIN_ROOM_TRACK: AudioStream = preload("res://assets/audio/music/home_room.wav")
const LOADING_TRACK: AudioStream = preload("res://assets/audio/music/loading.wav")
const OVERWORLD_TRACK: AudioStream = preload("res://assets/audio/music/overworld.wav")
const BATTLE_TRACK: AudioStream = preload("res://assets/audio/music/battle.wav")
const LOADING_OFFSET := 1.0
const LOADING_FADE := 2.0
# Reviewing: these traditional tunes, shuffled and quieter. Loaded when picked, not at boot.
const FOCUS_TUNES: Array[String] = [
	"res://assets/audio/music/focus_twinkle.wav",
	"res://assets/audio/music/focus_london_bridge.wav",
	"res://assets/audio/music/focus_mary_lamb.wav",
	"res://assets/audio/music/focus_frere_jacques.wav",
]
const FOCUS_LEVEL := 0.3
# Swapping to the home loop or the region map's route theme: the old track fades out while the new
# one fades in over this long.
const CROSSFADE := 2.5
const MUTE_FADE := 0.5
# The track's mix level at full music volume (-6 dB).
const MUSIC_LEVEL := 0.5

## Settings sliders, 0..1; saved by SaveManager.
var music_volume := 1.0
var sfx_volume := 1.0
## Saved: whether the map and battles play music. Home keeps its own.
var adventure_music := true

var _player: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _music_fade: Tween
var _level := MUSIC_LEVEL
var _focus_tune := ""
# The map's or a battle's track while on one of those screens, even if muted, so unmuting can resume it.
var _adventure_track: AudioStream
var _sfx_chain_id := 0

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	add_child(_player)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "SfxPlayer"
	add_child(_sfx)

func play_loading() -> void:
	_adventure_track = null
	_end_focus()
	_play_track(LOADING_TRACK, LOADING_OFFSET, LOADING_FADE)

func play_main_room() -> void:
	_adventure_track = null
	_end_focus()
	_play_track(MAIN_ROOM_TRACK, 0.0, CROSSFADE, true)

## The region map's route theme.
func play_overworld() -> void:
	_play_adventure(OVERWORLD_TRACK)

func play_battle() -> void:
	_play_adventure(BATTLE_TRACK)

func _play_adventure(track: AudioStream) -> void:
	_adventure_track = track
	_end_focus()
	if adventure_music:
		_play_track(track, 0.0, CROSSFADE, true)
	else:
		_fade_out()

## Mutes or restores the map's and battles' music, at once if one of them is on screen.
func set_adventure_music(on: bool) -> void:
	adventure_music = on
	if _adventure_track != null:
		_play_adventure(_adventure_track)

# The current track fades away on its own player, leaving an empty one ready for the next.
func _fade_out() -> void:
	if not _player.playing:
		return
	_kill_music_fade()
	var old := _player
	old.name = "MusicFadingOut"
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	add_child(_player)
	var out := create_tween()
	out.tween_property(old, "volume_linear", 0.0, MUTE_FADE)
	out.tween_callback(old.queue_free)

## Review music: the current track fades into a random lullaby at the lower level, and when a tune
## ends another takes over, until any other track is asked for.
func play_focus() -> void:
	if _focus_tune != "":
		return
	_adventure_track = null
	_level = FOCUS_LEVEL
	_next_focus_tune(CROSSFADE)

func _next_focus_tune(fade_in: float) -> void:
	var others := FOCUS_TUNES.filter(func(path: String) -> bool: return path != _focus_tune)
	_focus_tune = others.pick_random()
	_play_track(load(_focus_tune), 0.0, fade_in, fade_in > 0.0, false)
	_player.finished.connect(_on_focus_tune_finished, CONNECT_ONE_SHOT)

func _on_focus_tune_finished() -> void:
	if _focus_tune != "":
		_next_focus_tune(0.0)

func _end_focus() -> void:
	_focus_tune = ""
	_level = MUSIC_LEVEL

## With `crossfade`, a track already playing fades out over `fade_in` on its own player (freed
## after) while the new one fades in.
func _play_track(track: AudioStream, from_position := 0.0, fade_in := 0.0, crossfade := false, loop := true) -> void:
	if not is_instance_valid(_player):
		return
	if _player.stream == track and _player.playing:
		return
	_kill_music_fade()
	if crossfade and fade_in > 0.0 and _player.playing:
		var old := _player
		old.name = "MusicFadingOut"
		_player = AudioStreamPlayer.new()
		_player.name = "MusicPlayer"
		add_child(_player)
		var out := create_tween()
		out.tween_property(old, "volume_linear", 0.0, fade_in)
		out.tween_callback(old.queue_free)
	_player.stream = track
	if _player.stream is AudioStreamWAV:
		var wav := _player.stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
	var target := _level * music_volume
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
		_player.volume_linear = _level * music_volume

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

## Plays on its own throwaway player, so effects overlap instead of cutting each other off.
func play_sfx_layered(stream: AudioStream, pitch := 1.0, gain := 1.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_linear = sfx_volume * gain
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

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
