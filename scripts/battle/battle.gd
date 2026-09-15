extends Control
## Phase 7: Battle scene (GDD §6.2) — Identification + Essay via one judging pipeline.
## Flow: bound question from SessionManager -> answer input -> "judging..." beat
## -> damage + one-line AI feedback -> enemy counter -> win/lose -> overworld.
## Phase 8: Champion gauntlet — back-to-back battles over the moveset, final
## step at boss HP; clearing the last one completes the region.
## Phase 9: Juice — Camera2D screen-shake + hit-stop (brief time_scale pause) on strong essay hits.

const PLAYER_MAX_HP := 100
const ENEMY_HP := 100
const BOSS_HP := 150
const ID_COUNTER := 30
const XP_REWARD := 5
const BOSS_XP_REWARD := 10
const CHAMPION_XP_REWARD := 15
# Phase 9 juice thresholds
const STRONG_ESSAY_SCORE := 0.7
const SHAKE_BASE_INTENSITY := 8.0
const HIT_STOP_BASE := 0.06

@onready var flee_btn: Button = $Margin/List/TopBar/FleeButton
@onready var title_label: Label = $Margin/List/TopBar/TitleLabel
@onready var enemy_name: Label = $Margin/List/EnemyCard/Row/EnemyInfo/EnemyName
@onready var enemy_hp_bar: ProgressBar = $Margin/List/EnemyCard/Row/EnemyInfo/EnemyHP
@onready var player_hp_bar: ProgressBar = $Margin/List/PlayerCard/Row/PlayerInfo/PlayerHP
@onready var qtype_label: Label = $Margin/List/QuestionCard/QBox/QuestionType
@onready var question_label: Label = $Margin/List/QuestionCard/QBox/QuestionText
@onready var answer_input: TextEdit = $Margin/List/AnswerInput
@onready var submit_btn: Button = $Margin/List/SubmitButton
@onready var judging_label: Label = $Margin/List/JudgingLabel
@onready var result_label: Label = $Margin/List/ResultLabel
@onready var result_panel: PanelContainer = $Margin/List/ResultPanel
@onready var result_title: Label = $Margin/List/ResultPanel/RBox/ResultTitle
@onready var xp_label: Label = $Margin/List/ResultPanel/RBox/XPLabel
@onready var retry_btn: Button = $Margin/List/ResultPanel/RBox/RButtons/RetryButton
@onready var continue_btn: Button = $Margin/List/ResultPanel/RBox/RButtons/ContinueButton

var _q: Dictionary = {}
var _qtype: String = "essay"
var _is_boss: bool = false
var _is_champion: bool = false
var _enemy_hp: int = ENEMY_HP
var _enemy_max: int = ENEMY_HP
var _player_hp: int = PLAYER_MAX_HP
var _awaiting: bool = false
var _over: bool = false
var _shake_tween: Tween

func _ready() -> void:
	# Phase 9 fix: Camera2D was breaking top-left anchored Control layout via Drag Center.
	# Force FIXED_TOP_LEFT so shaking the camera offset never shifts the UI canvas origin.
	var _cam := get_node_or_null("Camera2D") as Camera2D
	if _cam:
		_cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		_cam.position = Vector2.ZERO
		_cam.offset = Vector2.ZERO
	_q = SessionManager.get_battle_question()
	if _q.is_empty():
		# Direct scene run fallback: easy ID question so the arena is testable solo.
		_q = {"id": "q_preview", "text": "Preview: What is the capital of France?", "type": "identification", "answer": "Paris", "confidence": 0.9, "key_concepts": []}
	_is_boss = bool(SessionManager.battle_is_boss)
	_is_champion = bool(SessionManager.battle_is_champion)
	_qtype = str(_q.get("type", "essay")).to_lower()
	_enemy_max = BOSS_HP if _is_boss else ENEMY_HP
	_enemy_hp = _enemy_max
	enemy_hp_bar.max_value = _enemy_max
	enemy_hp_bar.value = _enemy_hp
	player_hp_bar.max_value = PLAYER_MAX_HP
	player_hp_bar.value = _player_hp
	var foe := "Trainer"
	if _is_champion:
		foe = "Champion"
	elif _is_boss:
		foe = "Gym Boss"
	enemy_name.text = "%s  HP %d/%d" % [foe, _enemy_hp, _enemy_max]
	if _is_champion:
		var cp := SessionManager.champion_progress()
		title_label.text = "CHAMPION %d/%d" % [int(cp["done"]) + 1, int(cp["total"])]
	else:
		title_label.text = "Boss Battle" if _is_boss else "Battle"
	qtype_label.text = _qtype.capitalize()
	question_label.text = str(_q.get("text", ""))
	answer_input.placeholder_text = "Type the exact term..." if _qtype == "identification" else "Explain in your own words..."
	judging_label.visible = false
	result_panel.visible = false
	submit_btn.pressed.connect(_on_submit)
	flee_btn.pressed.connect(_on_flee)
	retry_btn.pressed.connect(_on_retry)
	continue_btn.pressed.connect(_on_continue)
	Api.job_status.connect(_on_job_status)

func _on_submit() -> void:
	if _awaiting or _over:
		return
	var answer: String = answer_input.text.strip_edges()
	if answer == "":
		result_label.text = "Type an answer first."
		return
	_awaiting = true
	submit_btn.disabled = true
	judging_label.visible = true
	result_label.text = ""
	Api.grade_battle_question(_q, answer)

func _on_job_status(job_id: String, status: String, _progress: float, result: Variant) -> void:
	if job_id != "grade" or status != "completed" or not _awaiting:
		return
	_awaiting = false
	judging_label.visible = false
	if typeof(result) != TYPE_DICTIONARY:
		result_label.text = "Grading hiccup — try again."
		submit_btn.disabled = false
		return
	var data: Dictionary = result
	var score: float = clampf(float(data.get("score", 0.0)), 0.0, 1.0)
	var feedback: String = str(data.get("feedback", ""))
	if _qtype == "identification":
		if score >= 0.7:
			_enemy_hp = 0
			result_label.text = "ONE-HIT KO! %s" % feedback
			# Identification KO also gets light juice — but essay strong hits are heavier.
			_screen_shake(6.0, 0.18)
		else:
			_player_hp = maxi(0, _player_hp - ID_COUNTER)
			result_label.text = "Blocked! Enemy counters for %d. %s" % [ID_COUNTER, feedback]
	else:
		var damage: int = int(data.get("damage", int(round(score * 100.0))))
		_enemy_hp = maxi(0, _enemy_hp - damage)
		# Phase 9: strong essay answers trigger hit-stop + Camera2D/Control shake.
		if score >= STRONG_ESSAY_SCORE and damage > 0:
			_trigger_strong_hit_juice(score)
		if _enemy_hp > 0:
			var counter: int = 10 + int((1.0 - score) * 20.0)
			_player_hp = maxi(0, _player_hp - counter)
			result_label.text = "%d dmg — %s\nEnemy hits back for %d." % [damage, feedback, counter]
		else:
			result_label.text = "%d dmg — %s" % [damage, feedback]
	enemy_hp_bar.value = _enemy_hp
	player_hp_bar.value = _player_hp
	if _enemy_hp <= 0:
		_win()
	elif _player_hp <= 0:
		_lose()
	else:
		submit_btn.disabled = false

# --- Phase 9: juice ---
func _trigger_strong_hit_juice(score: float) -> void:
	var intensity := SHAKE_BASE_INTENSITY + score * 10.0
	var duration := 0.22 + score * 0.08
	_screen_shake(intensity, duration)
	var stop_dur := HIT_STOP_BASE + score * 0.04
	_hit_stop(stop_dur)

func _screen_shake(intensity: float, duration: float) -> void:
	# Prefer Camera2D offset if present (spec requirement), fallback to Control position.
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam:
		var orig: Vector2 = cam.offset
		var t := create_tween()
		var steps := 5
		for i in steps:
			var off := Vector2(randf_range(-intensity, intensity), randf_range(-intensity * 0.7, intensity * 0.7))
			t.tween_property(cam, "offset", off, duration / float(steps * 2))
			t.tween_property(cam, "offset", orig, duration / float(steps * 2))
		t.tween_property(cam, "offset", orig, 0.02)
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	var base: Vector2 = position
	_shake_tween = create_tween()
	for i in 4:
		var off := Vector2(randf_range(-intensity, intensity), randf_range(-intensity * 0.6, intensity * 0.6))
		_shake_tween.tween_property(self, "position", base + off, duration / 8.0)
		_shake_tween.tween_property(self, "position", base, duration / 8.0)
	_shake_tween.tween_property(self, "position", base, 0.01)

func _hit_stop(duration: float) -> void:
	# Brief time_scale dip — timer ignores time_scale so it always recovers.
	var prev: float = Engine.time_scale
	Engine.time_scale = 0.08
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = prev

func _win() -> void:
	_over = true
	SessionManager.report_battle_result(true)
	var reward: int = BOSS_XP_REWARD if _is_boss else XP_REWARD
	var more := false
	if _is_champion:
		more = SessionManager.advance_champion()
		if not more:
			reward += CHAMPION_XP_REWARD
	CompanionState.add_xp(reward)
	if _is_champion and not more:
		result_title.text = "CHAMPION DEFEATED — Region Complete!"
		xp_label.text = "+%d XP (incl. champion bonus)  •  %s" % [reward, str(_q.get("text", "")).left(60)]
	elif _is_champion:
		var cp := SessionManager.champion_progress()
		result_title.text = "Opponent down! (%d/%d)" % [int(cp["done"]), int(cp["total"])]
		xp_label.text = "+%d XP — next challenger awaits." % reward
	else:
		result_title.text = "Victory!"
		xp_label.text = "+%d XP  •  %s" % [reward, str(_q.get("text", "")).left(60)]
	retry_btn.visible = false
	continue_btn.text = "Next" if more else "Overworld"
	result_panel.visible = true

func _lose() -> void:
	_over = true
	SessionManager.report_battle_result(false)
	result_title.text = "Defeated — review and retry!"
	xp_label.text = "Tip: check the Codex, then strike again."
	retry_btn.visible = true
	continue_btn.text = "Flee"
	result_panel.visible = true

func _on_retry() -> void:
	_enemy_hp = _enemy_max
	_player_hp = PLAYER_MAX_HP
	_over = false
	enemy_hp_bar.value = _enemy_hp
	player_hp_bar.value = _player_hp
	answer_input.text = ""
	result_label.text = ""
	result_panel.visible = false
	submit_btn.disabled = false

func _on_continue() -> void:
	# Champion gauntlet: next fight reloads the arena with the queued question.
	if _is_champion and SessionManager.battle_is_champion:
		get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/overworld/region_map.tscn")

func _on_flee() -> void:
	# Abandoning the gauntlet forfeits the run (progress per-question stays).
	SessionManager.battle_is_champion = false
	get_tree().change_scene_to_file("res://scenes/overworld/region_map.tscn")
