extends Control
## Phase 7: Battle scene (GDD §6.2) — Identification + Essay via one judging pipeline; Multiple
## Choice is tapped and graded locally. Enemy HP, counters and thresholds follow the question's tier.
## Flow: bound question from SessionManager -> answer input -> "judging..." beat
## -> damage + one-line AI feedback -> enemy counter -> win/lose -> overworld.
## Phase 8: Champion gauntlet — back-to-back battles over the moveset, final
## step at boss HP; clearing the last one completes the region.
## Phase 9: Juice — Camera2D screen-shake + hit-stop (brief time_scale pause) on strong essay hits.
## Phase 10: Quota label + paywall dialog via MonetizationState / Api.quota_exceeded.

const PLAYER_MAX_HP := 100
const BOSS_HP := 150
const CHAMPION_XP_REWARD := 15
# Contract: docs/systems/gameplay-structure.md (difficulty table).
const TIERS := {
	"easy": {"hp": 60, "counter": 15, "xp": 5, "essay_pass": 0.5},
	"medium": {"hp": 100, "counter": 25, "xp": 8, "essay_pass": 0.65},
	"hard": {"hp": 150, "counter": 35, "xp": 12, "essay_pass": 0.8},
}
# Phase 9 juice thresholds
const STRONG_ESSAY_SCORE := 0.7
const SHAKE_BASE_INTENSITY := 8.0
const HIT_STOP_BASE := 0.06

## Start-of-battle entrance (see _play_intro). Turn it off to drop straight into the fight.
@export var play_intro := true
@export var intro_text := "%s wants to battle!"
@export var intro_card_slide := 420.0
@export var intro_dialogue_slide := 700.0
@export var intro_vs_hold := 0.5
@export var intro_flash_strength := 0.85
@export var intro_shake := 10.0

@onready var stage: ArenaStage = %Stage
@onready var enemy_card: Control = %EnemyCard
@onready var player_card: Control = %PlayerCard
@onready var dialogue: Control = %Dialogue
@onready var vs_label: Label = %VsLabel
@onready var flash: ColorRect = %Flash
@onready var cam: Camera2D = %Camera2D
@onready var mc_box: VBoxContainer = %MCBox
@onready var mc_template: Button = %McTemplate
@onready var flee_btn: Button = %FleeButton
@onready var title_label: Label = %TitleLabel
@onready var quota_label: Label = %QuotaLabel
@onready var enemy_name: Label = %EnemyName
@onready var enemy_level: Label = %EnemyLevel
@onready var enemy_hp_bar: ProgressBar = %EnemyHP
@onready var enemy_hp_text: Label = %EnemyHPText
@onready var player_name: Label = %PlayerName
@onready var player_level: Label = %PlayerLevel
@onready var player_hp_bar: ProgressBar = %PlayerHP
@onready var player_hp_text: Label = %PlayerHPText
@onready var qtype_label: Label = %QuestionType
@onready var question_label: Label = %QuestionText
@onready var answer_input: TextEdit = %AnswerInput
@onready var submit_btn: Button = %SubmitButton
@onready var judging_label: Label = %JudgingLabel
@onready var result_label: Label = %ResultLabel
@onready var result_panel: PanelContainer = %ResultPanel
@onready var result_title: Label = %ResultTitle
@onready var xp_label: Label = %XPLabel
@onready var retry_btn: Button = %RetryButton
@onready var continue_btn: Button = %ContinueButton
@onready var quota_dialog: ConfirmationDialog = %QuotaDialog

var _q: Dictionary = {}
var _qtype: String = "essay"
var _tier: String = "medium"
var _mc_options: Array[String] = []
var _is_boss: bool = false
var _is_champion: bool = false
var _enemy_hp: int = 0
var _enemy_max: int = 0
var _player_hp: int = PLAYER_MAX_HP
# HP last shown on the bars; a drop since then is what triggers the pet / robot reactions.
var _shown_enemy_hp: int = 0
var _shown_player_hp: int = 0
var _awaiting: bool = false
var _over: bool = false
var _shake_tween: Tween

func _ready() -> void:
	_q = SessionManager.get_battle_question()
	if _q.is_empty():
		# Direct scene run fallback: easy ID question so the arena is testable solo.
		_q = {"id": "q_preview", "text": "Preview: What is the capital of France?", "type": "identification", "answer": "Paris", "confidence": 0.9, "key_concepts": []}
	_is_boss = bool(SessionManager.battle_is_boss)
	_is_champion = bool(SessionManager.battle_is_champion)
	_qtype = str(_q.get("type", "essay")).to_lower()
	_tier = str(_q.get("difficulty", "medium")).to_lower()
	if not TIERS.has(_tier):
		_tier = "medium"
	if _qtype == "multiple_choice":
		_mc_options = _mc_choices()
		if _mc_options.size() < 2:
			_qtype = "identification"
	_enemy_max = BOSS_HP if _is_boss else int(TIERS[_tier]["hp"])
	_enemy_hp = _enemy_max
	enemy_hp_bar.max_value = _enemy_max
	player_hp_bar.max_value = PLAYER_MAX_HP
	_refresh_bars()
	var foe := "TRAINER"
	if _is_champion:
		foe = "CHAMPION"
	elif _is_boss:
		foe = "GYM BOSS"
	enemy_name.text = foe
	# Foes carry no stored level: show their tier (+1 for a boss / Champion) so both cards match.
	enemy_level.text = "Lv%d" % (SessionManager.DIFFICULTIES.find(_tier) + 1 + (1 if _is_boss or _is_champion else 0))
	player_name.text = "KUIZ"
	player_level.text = "Lv%d" % CompanionState.level
	stage.setup(_is_boss or _is_champion)
	if _is_champion:
		var cp := SessionManager.champion_progress()
		title_label.text = "CHAMPION %d/%d" % [int(cp["done"]) + 1, int(cp["total"])]
	else:
		title_label.text = "Boss Battle" if _is_boss else "Battle"
	qtype_label.text = "%s · %s" % [_qtype.capitalize(), _tier.capitalize()]
	question_label.text = str(_q.get("text", ""))
	answer_input.placeholder_text = "Type the exact term..." if _qtype == "identification" else "Explain in your own words..."
	if _qtype == "multiple_choice":
		_build_mc_buttons()
	judging_label.visible = false
	result_panel.visible = false
	submit_btn.pressed.connect(_on_submit)
	flee_btn.pressed.connect(_on_flee)
	retry_btn.pressed.connect(_on_retry)
	continue_btn.pressed.connect(_on_continue)
	Api.job_status.connect(_on_job_status)
	# Phase 10: quota display + paywall
	_update_quota_label()
	var _ms := get_node_or_null("/root/MonetizationState")
	if _ms != null:
		_ms.quota_changed.connect(_update_quota_label)
		_ms.premium_changed.connect(_on_premium_changed)
	Api.quota_exceeded.connect(_on_quota_exceeded)
	if play_intro:
		_play_intro(foe)
	else:
		stage.start_hover()

# Start-of-battle entrance. The bots fly onto their pads (ArenaStage.play_intro), the HUD slides in
# around them, "VS" slams down and the screen flashes when the foe lands. Controls stay locked until
# it ends. Every duration is an export on this node or on the Stage.
func _play_intro(foe: String) -> void:
	_set_inputs(false)
	stage.play_intro()  # sets the start poses now, before the first frame
	var cards: Array[Control] = [enemy_card, player_card, dialogue]
	for c in cards:
		c.modulate.a = 0.0
	vs_label.visible = false
	result_label.text = intro_text % foe.capitalize()
	await get_tree().process_frame  # let the anchored layout settle so the rest positions are real
	var enemy_rest := enemy_card.position
	var player_rest := player_card.position
	var dialogue_rest := dialogue.position
	enemy_card.position.x -= intro_card_slide
	player_card.position.x += intro_card_slide
	dialogue.position.y += intro_dialogue_slide
	var t := create_tween().set_parallel()
	t.tween_property(dialogue, "position:y", dialogue_rest.y, 0.55).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(dialogue, "modulate:a", 1.0, 0.3).set_delay(0.3)
	t.tween_property(enemy_card, "position:x", enemy_rest.x, 0.5).set_delay(0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(enemy_card, "modulate:a", 1.0, 0.25).set_delay(0.6)
	t.tween_property(player_card, "position:x", player_rest.x, 0.5).set_delay(0.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(player_card, "modulate:a", 1.0, 0.25).set_delay(0.75)
	# Screen punch when the foe touches down.
	stage.foe_landed.connect(func() -> void:
		flash.modulate.a = intro_flash_strength
		create_tween().tween_property(flash, "modulate:a", 0.0, 0.4)
		_screen_shake(intro_shake, 0.3))
	# "VS" slams in over the arena, holds, then fades.
	get_tree().create_timer(0.85).timeout.connect(func() -> void:
		vs_label.pivot_offset = vs_label.size / 2.0
		vs_label.scale = Vector2.ONE * 3.0
		vs_label.modulate.a = 0.0
		vs_label.visible = true
		var v := create_tween().set_parallel()
		v.tween_property(vs_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		v.tween_property(vs_label, "modulate:a", 1.0, 0.15)
		v.chain().tween_interval(intro_vs_hold)
		v.chain().tween_property(vs_label, "modulate:a", 0.0, 0.3)
		v.chain().tween_callback(vs_label.hide))
	await t.finished
	while stage.intro_running:
		await get_tree().process_frame
	if intro_vs_hold > 0.0:
		await get_tree().create_timer(intro_vs_hold * 0.5).timeout
	result_label.text = ""
	_set_inputs(true)

# Locks or unlocks everything the player can press or type into.
func _set_inputs(on: bool) -> void:
	flee_btn.disabled = not on
	submit_btn.disabled = not on
	answer_input.editable = on
	_set_mc_enabled(on)

func _update_quota_label() -> void:
	if quota_label == null:
		return
	var _ms := get_node_or_null("/root/MonetizationState")
	# Null-guard: the arena also runs standalone, without autoloads.
	if _ms == null:
		return
	if _ms.is_premium:
		quota_label.text = "Premium: Unlimited"
	else:
		var rem: int = _ms.get_remaining("grade")
		quota_label.text = "Free AI Uses: %d/%d" % [rem, _ms.FREE_GRADE_LIMIT]

func _on_premium_changed(_is_premium: bool) -> void:
	_update_quota_label()

func _on_quota_exceeded(_type: String) -> void:
	_update_quota_label()
	_awaiting = false
	judging_label.visible = false
	submit_btn.disabled = false
	quota_dialog.dialog_text = "Weekly AI limit reached. Upgrade to Premium to continue."
	quota_dialog.popup_centered()

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

# Correct answer plus its wrong options, shuffled; empty when the row cannot be played as MC.
func _mc_choices() -> Array[String]:
	var correct := str(_q.get("answer", "")).strip_edges()
	var out: Array[String] = []
	if correct == "":
		return out
	out.append(correct)
	for x in _q.get("distractors", []):
		var s := str(x).strip_edges()
		if s != "" and not out.has(s):
			out.append(s)
	out.shuffle()
	return out

func _build_mc_buttons() -> void:
	answer_input.visible = false
	submit_btn.visible = false
	mc_box.visible = true
	var correct := str(_q.get("answer", "")).strip_edges()
	for opt in _mc_options:
		var b := mc_template.duplicate() as Button
		b.text = opt
		b.visible = true
		b.pressed.connect(_on_mc_pick.bind(b, opt == correct))
		mc_box.add_child(b)

func _set_mc_enabled(on: bool) -> void:
	for b: Button in mc_box.get_children():
		b.disabled = not on

func _on_mc_pick(button: Button, correct: bool) -> void:
	if _over:
		return
	if correct:
		_enemy_hp = 0
		result_label.text = "ONE-HIT KO! That's the one."
		_screen_shake(6.0, 0.18)
	else:
		button.disabled = true
		var counter := int(TIERS[_tier]["counter"])
		_player_hp = maxi(0, _player_hp - counter)
		result_label.text = "Blocked! Enemy counters for %d." % counter
	_finish_turn()

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
			var counter := int(TIERS[_tier]["counter"])
			_player_hp = maxi(0, _player_hp - counter)
			result_label.text = "Blocked! Enemy counters for %d. %s" % [counter, feedback]
	else:
		var passed := score >= float(TIERS[_tier]["essay_pass"])
		var damage: int = int(data.get("damage", int(round(score * 100.0)))) if passed else 0
		_enemy_hp = maxi(0, _enemy_hp - damage)
		# Phase 9: strong essay answers trigger hit-stop + Camera2D/Control shake.
		if score >= STRONG_ESSAY_SCORE and damage > 0:
			_trigger_strong_hit_juice(score)
		if _enemy_hp > 0:
			var counter := int(round(float(TIERS[_tier]["counter"]) * (0.4 + 0.6 * (1.0 - score))))
			_player_hp = maxi(0, _player_hp - counter)
			result_label.text = "%d dmg — %s\nEnemy hits back for %d." % [damage, feedback, counter]
		else:
			result_label.text = "%d dmg — %s" % [damage, feedback]
	_finish_turn()

func _refresh_bars() -> void:
	_shown_enemy_hp = _enemy_hp
	_shown_player_hp = _player_hp
	enemy_hp_bar.value = _enemy_hp
	player_hp_bar.value = _player_hp
	enemy_hp_text.text = "%d/%d" % [_enemy_hp, _enemy_max]
	player_hp_text.text = "%d/%d" % [_player_hp, PLAYER_MAX_HP]

func _finish_turn() -> void:
	if _player_hp < _shown_player_hp:
		stage.enemy_attack()
		stage.pet_hurt()
	elif _enemy_hp < _shown_enemy_hp:
		stage.pet_hit()
	_refresh_bars()
	_update_quota_label()
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
	stage.enemy_defeat()
	stage.pet_win()
	SessionManager.report_battle_result(true)
	_set_mc_enabled(false)
	var reward: int = int(TIERS[_tier]["xp"]) * (2 if _is_boss else 1)
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
	SaveManager.save_progress()

func _lose() -> void:
	_over = true
	_set_mc_enabled(false)
	SessionManager.report_battle_result(false)
	result_title.text = "Defeated — review and retry!"
	xp_label.text = "Tip: train up, then strike again."
	retry_btn.visible = true
	continue_btn.text = "Flee"
	result_panel.visible = true
	SaveManager.save_progress()

func _on_retry() -> void:
	_enemy_hp = _enemy_max
	_player_hp = PLAYER_MAX_HP
	_over = false
	_refresh_bars()
	answer_input.text = ""
	result_label.text = ""
	result_panel.visible = false
	_set_mc_enabled(true)
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
