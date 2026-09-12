extends Control
## Boot loading screen (replaces login now that backend/auth is skipped).
## Slow fill to 96%, pause, then a slow crawl to 100 before routing:
## save file -> care room, first launch -> meet-your-companion cutscene.
## Tips rotate every few seconds while loading.

@onready var load_bar: ProgressBar = $Content/LoadBar
@onready var tip_label: Label = $Content/TipLabel

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

var _tip_index: int = 0
var _tip_timer: Timer
var _done: bool = false

func _ready() -> void:
	theme = load("res://ui/app_theme.tres") as Theme
	load_bar.min_value = 0.0
	load_bar.max_value = 100.0
	load_bar.value = 0.0
	_tip_index = randi() % TIPS.size()
	tip_label.text = TIPS[_tip_index]
	if has_node("/root/MusicManager"):
		(get_node("/root/MusicManager") as Node).call("ensure_playing")
	_start_tip_cycle()
	_start_load_sequence()

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
	var fade := create_tween()
	fade.tween_property(tip_label, "modulate:a", 0.0, 0.25)
	fade.tween_callback(func() -> void: tip_label.text = TIPS[_tip_index])
	fade.tween_property(tip_label, "modulate:a", 1.0, 0.25)

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
	if FileAccess.file_exists("user://studymon_save.json"):
		get_tree().change_scene_to_file("res://scenes/ui/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/companion/meet_companion.tscn")
