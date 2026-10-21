extends Control
## Boot loading screen (replaces login now that backend/auth is skipped).
## Slow fill to 96%, pause, then a slow crawl to 100, fade to white and hand off to the peek scene.
## Tips rotate every few seconds while loading.

@onready var load_bar: ProgressBar = $Content/BarTrack/LoadBar
@onready var tip_label: Label = $Content/TipRow/TipLabel
@onready var fade: ColorRect = $Fade
@onready var logo: TextureRect = $Logo

const TIPS: Array[String] = [
	"Your AI starts out knowing nothing — you train it!",
	"Feeding your AI examples is called training data.",
	"Petting rewards good behavior — that's feedback.",
	"Playing is practice: try, fail, try again.",
]

const TIP_INTERVAL: float = 2.5
const FILL_TO_HOLD: float = 96.0
const FILL_TIME: float = 5.0
const HOLD_TIME: float = 0.6
const CRAWL_TIME: float = 2.0
const FADE_IN_TIME: float = 0.4
const FADE_OUT_TIME: float = 0.4
const LOGO_BOB: float = 12.0
const LOGO_BOB_TIME: float = 1.6
const NEXT_SCENE := "res://scenes/ui/peek.tscn"

var _tip_index: int = 0
var _tip_timer: Timer
var _tip_fade: Tween
var _done: bool = false

func _ready() -> void:
	theme = load("res://ui/app_theme.tres") as Theme
	ResourceLoader.load_threaded_request(NEXT_SCENE)
	load_bar.min_value = 0.0
	load_bar.max_value = 100.0
	load_bar.value = 0.0
	_tip_index = randi() % TIPS.size()
	tip_label.text = TIPS[_tip_index]
	if has_node("/root/MusicManager"):
		(get_node("/root/MusicManager") as Node).call("ensure_playing")
	_fade_in()
	_bob_logo()
	_start_tip_cycle()
	_start_load_sequence()

func _bob_logo() -> void:
	var rest := logo.position.y
	var t := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(logo, "position:y", rest - LOGO_BOB, LOGO_BOB_TIME)
	t.tween_property(logo, "position:y", rest, LOGO_BOB_TIME)

# Fade is white on both ends to match the splash before and the peek scene after, so neither cut shows.
func _fade_in() -> void:
	var t := create_tween()
	t.tween_property(fade, "modulate:a", 0.0, FADE_IN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_callback(fade.hide)

func _start_tip_cycle() -> void:
	_tip_timer = Timer.new()
	_tip_timer.wait_time = TIP_INTERVAL
	_tip_timer.autostart = true
	_tip_timer.timeout.connect(_next_tip)
	add_child(_tip_timer)
	_tip_timer.start()

func _next_tip() -> void:
	if _done:
		return
	_tip_index = (_tip_index + 1) % TIPS.size()
	if is_instance_valid(_tip_fade):
		_tip_fade.kill()
	_tip_fade = create_tween()
	_tip_fade.tween_property(tip_label, "modulate:a", 0.0, 0.25)
	_tip_fade.tween_callback(func() -> void: tip_label.text = TIPS[_tip_index])
	_tip_fade.tween_property(tip_label, "modulate:a", 1.0, 0.25)

func _start_load_sequence() -> void:
	var t := create_tween()
	t.tween_property(load_bar, "value", FILL_TO_HOLD, FILL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_interval(HOLD_TIME)
	t.tween_property(load_bar, "value", 100.0, CRAWL_TIME).set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(_advance)

func _advance() -> void:
	_done = true
	if is_instance_valid(_tip_timer):
		_tip_timer.stop()
	fade.show()
	var t := create_tween()
	t.tween_property(fade, "modulate:a", 1.0, FADE_OUT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished
	# Holding the threaded result keeps it in the resource cache, so the change below doesn't block.
	var _next := ResourceLoader.load_threaded_get(NEXT_SCENE)
	get_tree().change_scene_to_file(NEXT_SCENE)
