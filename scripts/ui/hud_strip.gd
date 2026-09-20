extends VBoxContainer
## Phase 2: persistent companion status strip — instanced on every screen.
## CompanionState emits stats_changed every frame, so this stays live.

@onready var level_label: Label = $StatusRow/LevelLabel
@onready var pomo_badge: Label = $StatusRow/PomoBadge
@onready var xp_row: HBoxContainer = $XPRow
@onready var xp_bar: ProgressBar = $XPRow/XPBar

var _xp_tween: Tween
var _xp_open := false

func _ready() -> void:
	CompanionState.stats_changed.connect(_refresh)
	CompanionState.xp_changed.connect(_on_xp)
	if level_label:
		level_label.gui_input.connect(_on_level_input)
	_refresh()

func _on_xp(_xp: int, _level: int) -> void:
	_refresh()

func _on_level_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and xp_row:
			_xp_open = not _xp_open
			if xp_bar:
				xp_bar.mouse_filter = 0 if _xp_open else 2
			if _xp_tween and _xp_tween.is_valid():
				_xp_tween.kill()
			_xp_tween = create_tween()
			_xp_tween.tween_property(xp_row, "modulate:a", 1.0 if _xp_open else 0.0, 0.2)

func _refresh() -> void:
	if level_label == null or pomo_badge == null:
		return
	level_label.text = "Lv %d" % CompanionState.level
	_refresh_pomo_badge()

func _refresh_pomo_badge() -> void:
	var state := CompanionState.get_pomodoro_state()
	match String(state["mode"]):
		"focus":
			pomo_badge.visible = true
			pomo_badge.text = "FOCUS " + _fmt_pomo(int(state["remaining"]))
		"rest":
			pomo_badge.visible = true
			pomo_badge.text = "REST " + _fmt_pomo(int(state["remaining"]))
		_:
			pomo_badge.visible = false

func _fmt_pomo(sec: int) -> String:
	return "%02d:%02d" % [sec / 60, sec % 60]
