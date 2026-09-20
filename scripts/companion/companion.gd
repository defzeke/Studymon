extends Control
## Phase 2: Pou-style care room on CompanionState (GDD §4.3).
## Care taps -> CompanionState.care() -> stats/XP -> animation -> tidbit.
## Phase 9: CPUParticles2D burst on level-up + font-scale hook + data-driven insights.
## Phase 10: Settings navigation (Toggle Premium / Reset Quota lives in settings.tscn).

@onready var bot_sprite: TextureRect = get_node_or_null("BotSprite") as TextureRect
@onready var rig: Node2D = get_node_or_null("CompanionRig") as Node2D
@onready var level_label: Label = $HudStrip/StatusRow/LevelLabel
@onready var xp_bar: ProgressBar = $HudStrip/XPRow/XPBar
@onready var tidbit_bubble: Label = $TidbitBubble
@onready var xp_tick: Label = $XPTick
@onready var campaign_btn: Button = $CampaignButton
@onready var settings_btn: Button = $SettingsButton
@onready var pomodoro_btn: Button = $PomodoroButton
@onready var pomodoro_panel: Control = $Pomodoro
@onready var room_bg: TextureRect = $Background
@onready var charge_btn: Button = $ChargeButton
@onready var night_veil: ColorRect = $NightVeil
@onready var batt_energy: ProgressBar = $BatteryRow/EnergyCell/EnergyBar
@onready var batt_focus: ProgressBar = $BatteryRow/FocusCell/FocusBar
@onready var batt_integrity: ProgressBar = $BatteryRow/IntegrityCell/IntegrityBar

const ROOM_DAY: Texture2D = preload("res://assets/sprites/rooms/main.svg")
const ROOM_NIGHT: Texture2D = preload("res://assets/sprites/rooms/dark_main.svg")
const CHARGE_SFX: AudioStream = preload("res://assets/audio/charge.mp3")
const CHARGED_SFX: AudioStream = preload("res://assets/audio/charged.mp3")
const NIGHT_DIM := Color(0.7, 0.7, 0.75)
var _dark_room := false
var _base_modulate := {}

var bot_textures: Array[Texture2D] = []
var _tick_tween: Tween
var _levelup_particles: CPUParticles2D

func _ready() -> void:
	SaveManager.load_game()
	# ponytail: companion stays hidden for now (scene already visible=false; enforce here too)
	if rig != null:
		rig.visible = false
	_load_bot_textures()
	_ensure_levelup_particles()
	_snap_modulates()
	CompanionState.xp_changed.connect(_on_xp_changed)
	CompanionState.stats_changed.connect(_refresh_batteries)
	CompanionState.leveled_up.connect(_on_leveled_up)
	CompanionState.codex_entry_added.connect(_on_tidbit)
	CompanionState.campaign_gate_ready.connect(_on_campaign_ready)
	CompanionState.pomodoro_phase_changed.connect(_on_pomodoro_phase)
	if SessionManager.has_signal("insight_triggered"):
		SessionManager.insight_triggered.connect(_on_insight)
	# Phase 9: accessibility — apply saved large-text scale and listen for changes.
	if GameState.has_signal("large_text_changed"):
		GameState.large_text_changed.connect(_on_large_text_changed)
	campaign_btn.pressed.connect(_on_campaign_pressed)
	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)
	if pomodoro_btn:
		pomodoro_btn.pressed.connect(_on_pomodoro_pressed)
	if charge_btn:
		charge_btn.pressed.connect(_on_charge_pressed)
	# ponytail: subtle hover-big / press-small on the room icon buttons
	for icon_btn in [campaign_btn, charge_btn, settings_btn, pomodoro_btn]:
		if icon_btn:
			ButtonJuice.wire(icon_btn)
	# Sync gate for saves already max-level at load time.
	if CompanionState.campaign_ready:
		GameState.set_campaign_unlocked(true)
	_refresh_all()
	_show_level(CompanionState.level)
	_on_tidbit_current()
	if CompanionState.is_in_rest():
		_on_pomodoro_phase("rest")
	# Phase 9: insight has last word (unless pomodoro rest prompt is active — wellness nudge wins).
	elif SessionManager.last_insight != "":
		tidbit_bubble.text = "\"" + SessionManager.last_insight + "\""
		_pop_bot()
	else:
		_show_retention_insight_if_any()

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

# --- Phase 9: level-up particle burst (CPUParticles2D) ---
func _ensure_levelup_particles() -> void:
	if rig != null and not rig.visible:
		return
	if _levelup_particles and is_instance_valid(_levelup_particles):
		return
	_levelup_particles = CPUParticles2D.new()
	_levelup_particles.amount = 28
	_levelup_particles.lifetime = 0.65
	_levelup_particles.one_shot = true
	_levelup_particles.explosiveness = 1.0
	_levelup_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_levelup_particles.emission_sphere_radius = 6.0
	_levelup_particles.direction = Vector2(0, -1)
	_levelup_particles.spread = 45.0
	_levelup_particles.gravity = Vector2(0, 160)
	_levelup_particles.initial_velocity_min = 90.0
	_levelup_particles.initial_velocity_max = 170.0
	_levelup_particles.angular_velocity_min = -180.0
	_levelup_particles.angular_velocity_max = 180.0
	_levelup_particles.scale_amount_min = 3.0
	_levelup_particles.scale_amount_max = 6.0
	_levelup_particles.color = Color(1, 0.84, 0.25)
	_levelup_particles.emitting = false
	add_child(_levelup_particles)
	if bot_sprite:
		_levelup_particles.position = bot_sprite.position + bot_sprite.size * 0.5
	else:
		_levelup_particles.position = Vector2(360, 540)

func _burst_levelup() -> void:
	if rig != null and not rig.visible:
		return
	_ensure_levelup_particles()
	if bot_sprite:
		_levelup_particles.position = bot_sprite.position + bot_sprite.size * 0.5 + Vector2(0, -10)
	_levelup_particles.restart()
	_levelup_particles.emitting = true

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
	_burst_levelup()
	_refresh_all()
	SaveManager.save_game()

func _on_tidbit(text: String) -> void:
	tidbit_bubble.text = "\"" + text + "\""

func _on_tidbit_current() -> void:
	var lv: int = CompanionState.level
	if CompanionState.CURRICULUM.has(lv):
		_on_tidbit(CompanionState.CURRICULUM[lv])

func _on_insight(_topic_id: String, _q_idx: int, text: String) -> void:
	tidbit_bubble.text = "\"" + text + "\""
	_pop_bot()

func _show_retention_insight_if_any() -> void:
	# If any question has silently decayed to REMASTER, show retention nudge without needing a battle first.
	# Scans current topic only (cheap); no LLM.
	var topic_id := SessionManager.current_topic_id
	if topic_id == "":
		topic_id = SessionManager.editing_topic_id
	if topic_id == "":
		return
	for i in SessionManager.pending_questions.size():
		if SessionManager.get_mastery_state(topic_id, i) == SessionManager.Mastery.REMASTER:
			var pool: Array = SessionManager.INSIGHT_TRIGGERS["retention_risk"]["lines"]
			if pool.is_empty():
				return
			var line := str(pool[randi() % pool.size()])
			tidbit_bubble.text = "\"" + line + "\""
			_pop_bot()
			return

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

func _on_large_text_changed(_enabled: bool) -> void:
	# Theme already mutated in GameState; refresh layout if needed.
	_refresh_all()

func _on_campaign_ready() -> void:
	GameState.set_campaign_unlocked(true)
	_refresh_all()
	SaveManager.save_game()

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings.tscn")

func _on_pomodoro_pressed() -> void:
	if pomodoro_panel:
		pomodoro_panel.visible = not pomodoro_panel.visible

func _on_charge_pressed() -> void:
	var was_dark := _dark_room
	if has_node("/root/MusicManager"):
		var mm := get_node("/root/MusicManager")
		if was_dark:
			mm.call("play_sfx_chain", [CHARGE_SFX, CHARGED_SFX])
		else:
			mm.call("play_sfx", CHARGE_SFX)
	CompanionState.care("charge")
	_dark_room = not _dark_room
	if room_bg:
		room_bg.texture = ROOM_NIGHT if _dark_room else ROOM_DAY
	if night_veil:
		night_veil.visible = _dark_room
	for child in get_children():
		if child == room_bg or child == night_veil:
			continue
		var ci := child as CanvasItem
		if ci == null:
			continue
		var base: Color = _base_modulate.get(child, Color.WHITE)
		ci.modulate = base * NIGHT_DIM if _dark_room else base

func _snap_modulates() -> void:
	_base_modulate.clear()
	for child in get_children():
		_base_modulate[child] = (child as CanvasItem).modulate

func _on_campaign_pressed() -> void:
	if GameState.campaign_unlocked_flag:
		get_tree().change_scene_to_file("res://scenes/ui/session_list.tscn")
	else:
		var need := CompanionState.xp_for_next_level()
		tidbit_bubble.text = "Locked! Reach Level 5 first. (%d XP to next level)" % need

func _refresh_all() -> void:
	if level_label != null:
		level_label.text = "Lv %d" % CompanionState.level
	var lo: int = CompanionState.xp_threshold(CompanionState.level - 1)
	var hi: int = CompanionState.xp_threshold(CompanionState.level)
	if xp_bar != null:
		xp_bar.min_value = lo
		xp_bar.max_value = hi
		xp_bar.value = CompanionState.xp
	campaign_btn.disabled = not GameState.campaign_unlocked_flag
	campaign_btn.tooltip_text = "Review Campaign" if GameState.campaign_unlocked_flag else "Locked — reach Lv 5"
	campaign_btn.modulate = Color(1, 1, 1, 1) if GameState.campaign_unlocked_flag else Color(1, 1, 1, 0.75)

func _refresh_batteries() -> void:
	if batt_energy == null or batt_focus == null or batt_integrity == null:
		return
	batt_energy.value = CompanionState.energy
	batt_focus.value = CompanionState.focus
	batt_integrity.value = CompanionState.integrity

func _show_level(lv: int) -> void:
	# ponytail: skeletal rig has no level textures; no-op while hidden
	if rig != null and not rig.visible:
		return
	if bot_sprite == null:
		return
	if lv >= 1 and lv <= bot_textures.size():
		bot_sprite.texture = bot_textures[lv - 1]

func _pop_bot() -> void:
	if rig != null and not rig.visible:
		return
	if bot_sprite == null:
		return
	if _tick_tween and _tick_tween.is_valid():
		_tick_tween.kill()
	bot_sprite.pivot_offset = bot_sprite.size / 2.0
	_tick_tween = create_tween()
	_tick_tween.tween_property(bot_sprite, "scale", Vector2(1.12, 0.9), 0.09)
	_tick_tween.tween_property(bot_sprite, "scale", Vector2.ONE, 0.12)

func _pop_bot_big() -> void:
	if rig != null and not rig.visible:
		return
	if bot_sprite == null:
		return
	if _tick_tween and _tick_tween.is_valid():
		_tick_tween.kill()
	bot_sprite.pivot_offset = bot_sprite.size / 2.0
	_tick_tween = create_tween()
	_tick_tween.tween_property(bot_sprite, "scale", Vector2(1.3, 1.3), 0.15)
	_tick_tween.tween_property(bot_sprite, "scale", Vector2.ONE, 0.25)

func _show_xp_tick(text: String) -> void:
	xp_tick.text = text
	xp_tick.modulate.a = 1.0
	if rig != null:
		xp_tick.position = rig.position + Vector2(150, -160)
	else:
		xp_tick.position = Vector2(400, 470)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(xp_tick, "position:y", xp_tick.position.y - 40.0, 0.6)
	t.tween_property(xp_tick, "modulate:a", 0.0, 0.6)
