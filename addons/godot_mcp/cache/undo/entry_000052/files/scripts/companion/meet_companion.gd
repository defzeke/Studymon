extends Control
## Phase 1: Meet Your Baby AI - first login cutscene

@onready var dialogue: Label = $Center/Dialogue
@onready var next_btn: Button = $Center/NextButton
@onready var skip_btn: Button = $Center/SkipButton
@onready var bot_sprite: TextureRect = $Center/BotSprite

var dialogue_lines: Array[String] = [
	"Welcome! I'm your new AI companion.",
	"Right now I'm just a baby — I don't know anything yet.",
	"But with your help, I'll learn from your study materials.",
	"Feed me, pet me, play with me — that's how I grow!",
	"At Level 5, I'll be ready to turn your PDFs into gym battles.",
	"Let's start! Tap the buttons below to care for me."
]
var current_line: int = 0

func _ready() -> void:
	theme = load("res://ui/app_theme.tres") as Theme
	_load_bot_texture()
	# First login: create the companion record (mocked until Supabase lands).
	Api.mock_get_companion()
	next_btn.pressed.connect(_on_next)
	skip_btn.pressed.connect(_on_skip)
	_show_line()
	_start_idle_bob()

func _load_bot_texture() -> void:
	if ResourceLoader.exists("res://assets/sprites/bot_lv1.png"):
		bot_sprite.texture = load("res://assets/sprites/bot_lv1.png") as Texture2D

func _show_line() -> void:
	if current_line < dialogue_lines.size():
		dialogue.text = dialogue_lines[current_line]
		next_btn.text = "Next" if current_line < dialogue_lines.size() - 1 else "Enter Care Room"
	else:
		_on_skip()

func _on_next() -> void:
	current_line += 1
	_show_line()

func _on_skip() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")

## Undo-cache stub: this snapshot called _start_idle_bob() without defining it.
func _start_idle_bob() -> void:
	pass