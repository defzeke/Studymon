extends Control
## Settings, opened from the Study Room: music and sound volume, large text, then the Phase 10
## mock monetization controls + debug quota reset. Every change is saved.

@onready var premium_check: CheckBox = %PremiumCheck
@onready var quota_label: Label = %QuotaLabel
@onready var reset_btn: Button = %ResetButton
@onready var back_btn: Button = %BackButton
@onready var status_label: Label = %StatusLabel
@onready var music_slider: HSlider = %MusicSlider
@onready var sounds_slider: HSlider = %SoundsSlider
@onready var large_text_check: CheckBox = %LargeTextCheck

func _ready() -> void:
	theme = load("res://assets/theme/app_theme.tres") as Theme
	GameState.tutorial_done = true  # only reachable from home, so Back must not replay the intro
	premium_check.toggled.connect(_on_premium_toggled)
	reset_btn.pressed.connect(_on_reset_pressed)
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
	var _ms := get_node_or_null("/root/MonetizationState")
	if _ms != null:
		_ms.quota_changed.connect(_refresh)
		_ms.premium_changed.connect(_on_premium_changed)
	_refresh()

func _refresh() -> void:
	var _ms := get_node_or_null("/root/MonetizationState")
	# Null-guard: the scene also runs standalone, without autoloads.
	if _ms == null:
		return
	# Prevent signal loop when setting checked state
	var is_p: bool = _ms.is_premium
	if premium_check.button_pressed != is_p:
		premium_check.set_pressed_no_signal(is_p)
	if is_p:
		quota_label.text = "Premium: Unlimited"
	else:
		var pdf_rem: int = _ms.get_remaining("pdf")
		var grade_rem: int = _ms.get_remaining("grade")
		quota_label.text = "Free AI Uses: PDFs %d/%d | Grades %d/%d" % [pdf_rem, _ms.FREE_PDF_LIMIT, grade_rem, _ms.FREE_GRADE_LIMIT]
	premium_check.text = "Premium" if is_p else "Free Tier"
	status_label.text = "Premium enabled — no limits." if is_p else "Free tier — weekly limits active."

func _on_premium_changed(is_premium: bool) -> void:
	_refresh()
	SaveManager.save_game()

func _on_premium_toggled(toggled_on: bool) -> void:
	var _ms := get_node_or_null("/root/MonetizationState")
	if _ms == null:
		return
	_ms.set_premium(toggled_on)
	SaveManager.save_game()

func _on_reset_pressed() -> void:
	var _ms := get_node_or_null("/root/MonetizationState")
	if _ms == null:
		return
	_ms.reset_quota()
	SaveManager.save_game()
	status_label.text = "Quota reset — weekly rollover simulated."
	_refresh()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/boot/peek.tscn")
