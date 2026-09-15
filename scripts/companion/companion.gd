extends Control
## Phase 1: Pou-style care room controller (GDD §4.3). Three taps -> GameManager.care().

@onready var rig = $CompanionRig
@onready var level_label: Label = $TopBar/LevelLabel
@onready var xp_bar: ProgressBar = $TopBar/XPBar
@onready var energy_bar: ProgressBar = $Stats/EnergyBar
@onready var focus_bar: ProgressBar = $Stats/FocusBar
@onready var mood_bar: ProgressBar = $Stats/MoodBar
@onready var tidbit_bubble: Label = $TidbitBubble
@onready var xp_tick: Label = $XPTick
@onready var campaign_btn: Button = $CampaignButton

func _ready() -> void:
	SaveManager.load_game()
	GameManager.stats_changed.connect(_refresh_stats)
	GameManager.xp_changed.connect(_on_xp_changed)
	GameManager.leveled_up.connect(_on_leveled_up)
	GameManager.tidbit_unlocked.connect(_on_tidbit)
	$Buttons/FeedButton.pressed.connect(_on_care.bind("feed"))
	$Buttons/PetButton.pressed.connect(_on_care.bind("pet"))
	$Buttons/PlayButton.pressed.connect(_on_care.bind("play"))
	campaign_btn.pressed.connect(_on_campaign_pressed)
	_refresh_all()
	_on_tidbit(GameManager.level, GameManager.CURRICULUM.get(GameManager.level, ""))

func _process(_delta: float) -> void:
	# Stats drain in GameManager; poll bars cheaply.
	_refresh_stats()

func _on_care(action: String) -> void:
	var res: Dictionary = GameManager.care(action)
	rig.play_reaction(action)
	_show_xp_tick("+%d XP" % int(res.get("xp", 1)))
	_refresh_all()
	SaveManager.save_game()

func _on_xp_changed(_current_xp: int, _level: int) -> void:
	_refresh_all()

func _on_leveled_up(_new_level: int) -> void:
	rig.celebrate()
	_refresh_all()
	SaveManager.save_game()

func _on_tidbit(_lv: int, text: String) -> void:
	tidbit_bubble.text = "\"" + text + "\""

func _on_campaign_pressed() -> void:
	if GameManager.campaign_unlocked:
		tidbit_bubble.text = "Campaign unlocks in Phase 3 — your bot is ready! (stub)"
	else:
		var need := GameManager.xp_for_next_level()
		tidbit_bubble.text = "Locked! Reach Level 5 first. (%d XP to next level)" % need

func _refresh_all() -> void:
	_refresh_stats()
	level_label.text = "Lv %d / 5" % GameManager.level
	var lo: int = int(GameManager.XP_PER_LEVEL[GameManager.level - 1]) if GameManager.level >= 1 else 0
	var hi: int = int(GameManager.XP_PER_LEVEL[GameManager.level]) if GameManager.level < 5 else lo + 1
	xp_bar.min_value = lo
	xp_bar.max_value = hi
	xp_bar.value = GameManager.xp
	campaign_btn.disabled = not GameManager.campaign_unlocked
	campaign_btn.text = "⚔ Review Campaign" if GameManager.campaign_unlocked else "🔒 Lv 5 unlocks Campaign"

func _refresh_stats() -> void:
	energy_bar.value = GameManager.energy
	focus_bar.value = GameManager.focus
	mood_bar.value = GameManager.mood
	# Auto face: sad when drained, sleepy when unfocused, else happy.
	if GameManager.energy < 25.0:
		rig.set_mood("sad")
	elif GameManager.focus < 25.0:
		rig.set_mood("sleepy")
	else:
		rig.set_mood("happy")

func _show_xp_tick(text: String) -> void:
	xp_tick.text = text
	xp_tick.modulate.a = 1.0
	xp_tick.position = rig.position + Vector2(150, -160)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(xp_tick, "position:y", xp_tick.position.y - 40.0, 0.6)
	t.tween_property(xp_tick, "modulate:a", 0.0, 0.6)
