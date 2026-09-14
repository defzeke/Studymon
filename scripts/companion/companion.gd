extends Control
## Phase 2: Pou-style care room on CompanionState (GDD §4.3).
## Three taps -> CompanionState.care() -> stats/XP -> animation -> tidbit.

@onready var bot_sprite: TextureRect = $BotSprite
@onready var level_label: Label = $HudStrip/StatusRow/LevelLabel
@onready var xp_bar: ProgressBar = $HudStrip/XPRow/XPBar
@onready var energy_bar: ProgressBar = $Stats/EnergyRow/EnergyBar
@onready var focus_bar: ProgressBar = $Stats/FocusRow/FocusBar
@onready var mood_bar: ProgressBar = $Stats/MoodRow/MoodBar
@onready var tidbit_bubble: Label = $TidbitBubble
@onready var xp_tick: Label = $XPTick
@onready var campaign_btn: Button = $CampaignButton
@onready var codex_btn: Button = $CodexButton

var bot_textures: Array[Texture2D] = []
var _tick_tween: Tween

func _ready() -> void:
	SaveManager.load_game()
	_load_bot_textures()
	CompanionState.stats_changed.connect(_refresh_stats)
	CompanionState.xp_changed.connect(_on_xp_changed)
	CompanionState.leveled_up.connect(_on_leveled_up)
	CompanionState.codex_entry_added.connect(_on_tidbit)
	CompanionState.campaign_gate_ready.connect(_on_campaign_ready)
	CompanionState.pomodoro_phase_changed.connect(_on_pomodoro_phase)
	$Buttons/FeedButton.pressed.connect(_on_care.bind("feed"))
	$Buttons/PetButton.pressed.connect(_on_care.bind("pet"))
	$Buttons/PlayButton.pressed.connect(_on_care.bind("play"))
	campaign_btn.pressed.connect(_on_campaign_pressed)
	codex_btn.pressed.connect(_on_codex_pressed)
	# Sync gate for saves already max-level at load time.
	if CompanionState.campaign_ready:
		GameState.set_campaign_unlocked(true)
	_refresh_all()
	_show_level(CompanionState.level)
	_on_tidbit_current()
	if CompanionState.is_in_rest():
		_on_pomodoro_phase("rest")

func _process(_delta: float) -> void:
	_refresh_stats()

func _load_bot_textures() -> void:
	bot_textures.clear()
	for i in range(1, 6):
		var p := "res://assets/sprites/bot_lv%d.png" % i
		if ResourceLoader.exists(p):
			bot_textures.append(load(p) as Texture2D)
	if bot_textures.is_empty():
		push_warning("Companion: no bot textures found.")
	else:
		_show_level(CompanionState.level)

func _on_care(action: String) -> void:
	var res: Dictionary = CompanionState.care(action)
	_pop_bot()
	var tick := "+%d XP" % int(res.get("xp", 1))
	if int(res.get("tap_count", 1)) > CompanionState.DAILY_CAP_BASE_XP:
		tick += " (tired)"
	_show_xp_tick(tick)
	_refresh_all()
	SaveManager.save_game()

func _on_xp_changed(_current_xp: int, _level: int) -> void:
	_refresh_all()

func _on_leveled_up(new_level: int) -> void:
	_show_level(new_level)
	_pop_bot_big()
	_refresh_all()
	SaveManager.save_game()

func _on_tidbit(text: String) -> void:
	tidbit_bubble.text = "\"" + text + "\""

func _on_tidbit_current() -> void:
	var lv: int = CompanionState.level
	if CompanionState.CURRICULUM.has(lv):
		_on_tidbit(CompanionState.CURRICULUM[lv])

func _on_pomodoro_phase(mode: String) -> void:
	match mode:
		"focus":
			tidbit_bubble.text = "\"Focus time! I'll keep you company.\""
			_pop_bot()
		"rest":
			tidbit_bubble.text = "\"Phew... my circuits are warm. Can we rest together?\""
			_pop_bot()
		"done":
			tidbit_bubble.text = "\"That rest hit the spot! I feel sharper already.\""
			_pop_bot()

func _on_campaign_ready() -> void:
	GameState.set_campaign_unlocked(true)
	_refresh_all()
	SaveManager.save_game()

func _on_codex_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/codex.tscn")

func _on_campaign_pressed() -> void:
	if GameState.campaign_unlocked_flag:
		get_tree().change_scene_to_file("res://scenes/ui/session_list.tscn")
	else:
		var need := CompanionState.xp_for_next_level()
		tidbit_bubble.text = "Locked! Reach Level 5 first. (%d XP to next level)" % need

func _refresh_all() -> void:
	_refresh_stats()
	level_label.text = "Lv %d / 5" % CompanionState.level
	var lo: int = int(CompanionState.XP_PER_LEVEL[CompanionState.level - 1])
	var hi: int = int(CompanionState.XP_PER_LEVEL[CompanionState.level]) if CompanionState.level < 5 else lo + 1
	xp_bar.min_value = lo
	xp_bar.max_value = hi
	xp_bar.value = CompanionState.xp
	campaign_btn.disabled = not GameState.campaign_unlocked_flag
	campaign_btn.text = "Review Campaign" if GameState.campaign_unlocked_flag else "Lv 5 unlocks Campaign"

func _refresh_stats() -> void:
	energy_bar.value = CompanionState.energy
	focus_bar.value = CompanionState.focus
	mood_bar.value = CompanionState.mood

func _show_level(lv: int) -> void:
	if lv >= 1 and lv <= bot_textures.size():
		bot_sprite.texture = bot_textures[lv - 1]

func _pop_bot() -> void:
	if _tick_tween and _tick_tween.is_valid():
		_tick_tween.kill()
	bot_sprite.pivot_offset = bot_sprite.size / 2.0
	_tick_tween = create_tween()
	_tick_tween.tween_property(bot_sprite, "scale", Vector2(1.12, 0.9), 0.09)
	_tick_tween.tween_property(bot_sprite, "scale", Vector2.ONE, 0.12)

func _pop_bot_big() -> void:
	if _tick_tween and _tick_tween.is_valid():
		_tick_tween.kill()
	bot_sprite.pivot_offset = bot_sprite.size / 2.0
	_tick_tween = create_tween()
	_tick_tween.tween_property(bot_sprite, "scale", Vector2(1.3, 1.3), 0.15)
	_tick_tween.tween_property(bot_sprite, "scale", Vector2.ONE, 0.25)

func _show_xp_tick(text: String) -> void:
	xp_tick.text = text
	xp_tick.modulate.a = 1.0
	xp_tick.position = bot_sprite.position + Vector2(60, -20)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(xp_tick, "position:y", xp_tick.position.y - 40.0, 0.6)
	t.tween_property(xp_tick, "modulate:a", 0.0, 0.6)
