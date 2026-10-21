extends VBoxContainer
## Phase 4: Pomodoro timer UI — embedded in the HUD strip area.
## CompanionState owns the timer logic; this just renders it.

@onready var mode_label: Label = $ModeLabel
@onready var timer_label: Label = $TimerLabel
@onready var start_btn: Button = $StartButton
@onready var skip_btn: Button = $SkipButton

func _ready() -> void:
	CompanionState.stats_changed.connect(_refresh)
	start_btn.pressed.connect(_on_start)
	skip_btn.pressed.connect(_on_skip)
	_refresh()

func _refresh() -> void:
	var state := CompanionState.get_pomodoro_state()
	var mode: String = str(state["mode"])
	var remaining: int = int(state["remaining"])

	if mode == "":
		mode_label.text = "Pomodoro"
		timer_label.text = "25:00"
		start_btn.text = "Start Focus"
		start_btn.disabled = false
		skip_btn.visible = false
	elif mode == "focus":
		mode_label.text = "Focus"
		timer_label.text = _fmt(remaining)
		start_btn.text = "Focus…"
		start_btn.disabled = true
		skip_btn.text = "Skip Focus"
		skip_btn.visible = true
	else:
		mode_label.text = "Rest"
		timer_label.text = _fmt(remaining)
		start_btn.text = "Resting…"
		start_btn.disabled = true
		skip_btn.text = "Skip Rest"
		skip_btn.visible = true

func _fmt(sec: int) -> String:
	var m := sec / 60
	var s := sec % 60
	return "%02d:%02d" % [m, s]

func _on_start() -> void:
	CompanionState.start_pomodoro()

func _on_skip() -> void:
	CompanionState.skip_pomodoro()