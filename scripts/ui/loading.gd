extends Control
## Boot loading screen (replaces login now that backend/auth is skipped).
## Shows a short loading beat, then routes: save file -> care room,
## first launch -> meet-your-companion cutscene.

@onready var bot_sprite: TextureRect = $Content/BotSprite
@onready var load_bar: ProgressBar = $Content/LoadBar
@onready var tip_label: Label = $Content/TipLabel

const TIPS: Array[String] = [
	"Your AI starts out knowing nothing — you train it!",
	"Feeding your AI examples is called training data.",
	"Petting rewards good behavior — that's feedback.",
	"Playing is practice: try, fail, try again.",
]

func _ready() -> void:
	theme = load("res://ui/app_theme.tres") as Theme
	tip_label.text = TIPS[randi() % TIPS.size()]
	if ResourceLoader.exists("res://assets/sprites/bot_lv1.png"):
		bot_sprite.texture = load("res://assets/sprites/bot_lv1.png") as Texture2D
	var t := create_tween()
	t.tween_property(load_bar, "value", 100.0, 1.5).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_advance)

func _advance() -> void:
	if FileAccess.file_exists("user://studymon_save.json"):
		get_tree().change_scene_to_file("res://scenes/ui/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/companion/meet_companion.tscn")
