extends Control
## Settings, opened from the Study Room: music and sound volume, and large text. Every change is
## saved.

@onready var back_btn: Button = %BackButton
@onready var music_slider: HSlider = %MusicSlider
@onready var sounds_slider: HSlider = %SoundsSlider
@onready var large_text_check: CheckBox = %LargeTextCheck

func _ready() -> void:
	theme = load("res://assets/theme/app_theme.tres") as Theme
	GameState.tutorial_done = true  # only reachable from home, so Back must not replay the intro
	back_btn.pressed.connect(_on_back)
	music_slider.set_value_no_signal(MusicManager.music_volume)
	sounds_slider.set_value_no_signal(MusicManager.sfx_volume)
	large_text_check.set_pressed_no_signal(GameState.large_text_enabled)
	music_slider.value_changed.connect(MusicManager.set_music_volume)
	sounds_slider.value_changed.connect(MusicManager.set_sfx_volume)
	music_slider.drag_ended.connect(func(_changed: bool) -> void: SaveManager.save_game())
	sounds_slider.drag_ended.connect(func(_changed: bool) -> void: SaveManager.save_game())
	large_text_check.toggled.connect(func(on: bool) -> void:
		GameState.set_large_text(on)
		SaveManager.save_game())

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/boot/peek.tscn")
