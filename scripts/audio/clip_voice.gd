extends Node
## Gives a glb model its sounds the way its artifact page does: each sound is synthesised in code
## (synth.gd), and each animation clip fires its cues as the playhead passes them (a looping clip
## fires them again every loop). Subclasses list the cues and build the sounds.
## Sounds are built once per run on a worker thread and shared by every instance; one asked for
## before the worker reaches it is built on the spot. Contract: docs/ui-and-assets.md §2 Model sounds.

const Synth := preload("res://scripts/audio/synth.gd")
const VOICES := 8

## The model's player (it lives inside the glb, so the owner hands it over).
var anim: AnimationPlayer
## Set by the subclass: clip -> [[seconds, sound, volume]], every sound name, and the gain baked
## into every sound (the artifacts leaned on a master gain and compressor).
var cues := {}
var sounds: Array[String] = []
var gain := 1.0

# "script path:sound" -> AudioStreamWAV, shared across instances and scene changes.
static var _cache := {}
static var _lock := Mutex.new()

var _prefix := ""
var _task := -1
var _abort := false
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _clip := ""
var _last := 0.0

## Subclasses add the parts of `sound` into `m`.
func _build(_sound: String, _m: Synth.Mix) -> void:
	pass

func _ready() -> void:
	_prefix = get_script().resource_path + ":"
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_task = WorkerThreadPool.add_task(_build_all, false, "clip_voice")

# Leaving the scene stops the worker after the sound it is on.
func _exit_tree() -> void:
	_abort = true
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

## Plays one sound at `volume` (0..1) times the Sounds slider.
func play(sound: String, volume := 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _stream(sound)
	p.volume_linear = volume * MusicManager.sfx_volume
	p.play()

func _process(_delta: float) -> void:
	if anim == null:
		return
	var clip := anim.current_animation
	if clip == "":
		return
	var now := anim.current_animation_position
	if clip != _clip:
		_clip = clip
		_last = -0.001
	var prev := _last
	_last = now
	if now == prev or not cues.has(clip):
		return
	var wrapped := now < prev
	for cue: Array in cues[clip]:
		var t: float = cue[0]
		if (t > prev or t <= now) if wrapped else (t > prev and t <= now):
			play(cue[1], cue[2])

func _stream(sound: String) -> AudioStreamWAV:
	_lock.lock()
	var s: AudioStreamWAV = _cache.get(_prefix + sound)
	_lock.unlock()
	if s == null:
		s = _make(sound)
	return s

func _make(sound: String) -> AudioStreamWAV:
	var m := Synth.Mix.new()
	_build(sound, m)
	var s := m.to_stream(gain)
	_lock.lock()
	_cache[_prefix + sound] = s
	_lock.unlock()
	return s

func _build_all() -> void:
	for sound in sounds:
		if _abort:
			return
		_lock.lock()
		var done := _cache.has(_prefix + sound)
		_lock.unlock()
		if not done:
			_make(sound)
