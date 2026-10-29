extends Control
## Settings, opened from the Study Room: music and sound volume, large text, and privacy & data (the
## AI consent, the policy links, exporting / importing / deleting the save). Every change is saved.

const ConfirmModal := preload("res://scripts/ui/widgets/confirm_modal.gd")
## The hosted policy pages; both stores need them reachable in the app. Set before exporting.
const PRIVACY_URL := ""
const TERMS_URL := ""
const SUPPORT_URL := ""

@onready var back_btn: Button = %BackButton
@onready var music_slider: HSlider = %MusicSlider
@onready var sounds_slider: HSlider = %SoundsSlider
@onready var large_text_check: CheckBox = %LargeTextCheck
@onready var consent_check: CheckBox = %ConsentCheck
@onready var consent_note: Label = %ConsentNote

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
	consent_note.text = GameState.AI_CONSENT_TEXT
	consent_check.set_pressed_no_signal(GameState.ai_consent)
	consent_check.toggled.connect(func(on: bool) -> void:
		GameState.ai_consent = on
		SaveManager.save_game())
	for pair: Array in [[%PrivacyButton, PRIVACY_URL], [%TermsButton, TERMS_URL], [%SupportButton, SUPPORT_URL]]:
		(pair[0] as Button).disabled = pair[1] == ""
		(pair[0] as Button).pressed.connect(OS.shell_open.bind(pair[1]))
	if not OS.is_debug_build() and "" in [PRIVACY_URL, TERMS_URL, SUPPORT_URL]:
		push_error("Settings: set PRIVACY_URL, TERMS_URL and SUPPORT_URL before a store release.")
	%DeleteDataButton.pressed.connect(func() -> void:
		ConfirmModal.open(self, "Delete my data?", "This erases Kuiz, your worlds, questions and progress from this device. It cannot be undone.", "Delete", _delete_all, true))
	ConfirmModal.tint_danger(%DeleteDataButton)
	%ExportButton.pressed.connect(func() -> void:
		%ExportDialog.current_file = "studymon_save_%s.json" % Time.get_date_string_from_system()
		%ExportDialog.popup_centered(Vector2i(640, 760)))
	%ImportButton.pressed.connect(func() -> void: %ImportDialog.popup_centered(Vector2i(640, 760)))
	%ExportDialog.file_selected.connect(_export)
	%ImportDialog.file_selected.connect(_confirm_import)

func _export(path: String) -> void:
	if SaveManager.export_to(path):
		ConfirmModal.open(self, "Save exported", "Keep %s somewhere safe. Import it on any device to get Kuiz and your worlds back." % path.get_file(), "OK", Callable(), false, "")
	else:
		ConfirmModal.open(self, "Export failed", "The save could not be written there. Try another folder.", "OK", Callable(), false, "")

func _confirm_import(path: String) -> void:
	ConfirmModal.open(self, "Import this save?", "It replaces Kuiz, your worlds and progress on this device with the ones in %s." % path.get_file(), "Import", _import.bind(path), true)

func _import(path: String) -> void:
	var error := SaveManager.import_from(path)
	if error != "":
		ConfirmModal.open(self, "Import refused", error + " Your current save was not changed.", "OK", Callable(), false, "")
		return
	get_tree().change_scene_to_file("res://scenes/ui/boot/peek.tscn")

# The fresh game starts at the tutorial, like a new install.
func _delete_all() -> void:
	SaveManager.delete_all()
	get_tree().change_scene_to_file("res://scenes/ui/boot/peek.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/boot/peek.tscn")
