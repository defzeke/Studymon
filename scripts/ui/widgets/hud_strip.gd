extends VBoxContainer
## Phase 2: persistent companion status strip — instanced on every screen.
## CompanionState emits stats_changed every frame, so this stays live.

@onready var level_label: Label = $StatusRow/LevelLabel
@onready var energy_bar: ProgressBar = $StatusRow/EnergyCell/EnergyBar
@onready var focus_bar: ProgressBar = $StatusRow/FocusCell/FocusBar
@onready var mood_bar: ProgressBar = $StatusRow/MoodCell/MoodBar
@onready var pomo_badge: Label = $StatusRow/PomoBadge

func _ready() -> void:
	CompanionState.stats_changed.connect(_refresh)
	CompanionState.xp_changed.connect(_on_xp)
	_refresh()

func _on_xp(_xp: int, _level: int) -> void:
	_refresh()

func _refresh() -> void:
	if level_label == null or energy_bar == null or focus_bar == null or mood_bar == null or pomo_badge == null:
		return
	level_label.text = "Lv %d" % CompanionState.level
	energy_bar.value = CompanionState.energy
	focus_bar.value = CompanionState.focus
	mood_bar.value = CompanionState.mood
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
