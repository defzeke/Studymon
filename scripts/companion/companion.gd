extends Control
## Phase 1: Pou-style care room controller (GDD §4.3). Three taps -> GameManager.care().

@onready var bot_sprite: TextureRect = $BotSprite
@onready var level_label: Label = $TopBar/LevelLabel
@onready var xp_bar: ProgressBar = $TopBar/XPBar
@onready var energy_bar: ProgressBar = $Stats/EnergyBar
@onready var focus_bar: ProgressBar = $Stats/FocusBar
@onready var mood_bar: ProgressBar = $Stats/MoodBar
@onready var tidbit_bubble: Label = $TidbitBubble
@onready var xp_tick: Label = $XPTick
@onready var campaign_btn: Button = $CampaignButton

var bot_textures: Array[Texture2D] = []
var _tick_tween: Tween

func _ready() -> void:
	SaveManager.load_game()
	_load_bot_textures()
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

func _load_bot_textures() -> void:
	bot_textures.clear()
	for i in range(1, 6):
		var p := "res://assets/sprites/bot_lv%d.png" % i
		if ResourceLoader.exists(p):
			bot_textures.append(load(p) as Texture2D)
	if bot_textures.is_empty():
		push_warning("Companion: no bot textures found, using placeholder.")
	else:
		_show_level(GameManager.level)

func _on_care(action: String) -> void:
	var res: Dictionary = GameManager.care(action)
	_pop_bot()
	_show_xp_tick("+%d XP" % int(res.get("xp", 1)))
	_refresh_all()
	SaveManager.save_game()

func _on_xp_changed(_current_xp: int, _level: int) -> void:
	_refresh_all()

func _on_leveled_up(new_level: int) -> void:
	_show_level(new_level)
	_pop_bot_big()
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
