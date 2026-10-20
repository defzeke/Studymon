extends Control
## White splash intro before the loading screen.

const SHEET: Texture2D = preload("res://assets/sprites/kuizmon_splash.png")
const FRAME_SIZE := Vector2i(480, 264)
const COLUMNS: int = 6
const FRAME_COUNT: int = 60
const FRAME_TIME: float = 0.03
const HOLD_TIME: float = 0.5
const FADE_TIME: float = 0.25
const NEXT_SCENE := "res://scenes/ui/loading.tscn"

@onready var logo: TextureRect = $Logo

var _frames: Array[AtlasTexture] = []
var _elapsed: float = 0.0
var _frame: int = 0
var _done: bool = false

func _ready() -> void:
	ResourceLoader.load_threaded_request(NEXT_SCENE)
	for i in FRAME_COUNT:
		var frame := AtlasTexture.new()
		frame.atlas = SHEET
		frame.region = Rect2(
			(i % COLUMNS) * FRAME_SIZE.x,
			int(i / float(COLUMNS)) * FRAME_SIZE.y,
			FRAME_SIZE.x,
			FRAME_SIZE.y
		)
		frame.filter_clip = true
		_frames.append(frame)
	logo.texture = _frames[0]

func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	var index := mini(int(_elapsed / FRAME_TIME), FRAME_COUNT - 1)
	if index != _frame:
		_frame = index
		logo.texture = _frames[index]
	if _elapsed >= FRAME_COUNT * FRAME_TIME + HOLD_TIME:
		_finish()

func _finish() -> void:
	_done = true
	var tween := create_tween()
	tween.tween_property(logo, "modulate:a", 0.0, FADE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	# Holding the threaded result keeps it in the resource cache, so the change below doesn't block.
	var _next := ResourceLoader.load_threaded_get(NEXT_SCENE)
	get_tree().change_scene_to_file(NEXT_SCENE)
