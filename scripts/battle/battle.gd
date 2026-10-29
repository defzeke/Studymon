extends Control
## Battle scene: one run (a Challenge House, Gym or the Champion Gym) of fixed items against one foe.
## Multiple Choice and Identification are graded on the device from the answer key; an Essay (and an
## Identification near-miss) goes to Api, with an offline mark when the server cannot answer.
## Each answer is followed by a review beat; a streak strengthens Kuiz's hits; Kuiz losing all its HP
## ends the run with Exit / Try Again. Juice: Camera2D shake + hit-stop.

# Contract: docs/systems/battle.md. A run is a fixed list of items fought against one foe.
const HP_PER_ITEM := 10
const HEAL_ON_CORRECT := 4
## Damage multiplier for the 1st, 2nd and 3rd+ miss in a row.
const MISS_MULT: Array[float] = [1.0, 1.25, 1.5]
## Reading time before Next, in seconds.
const REVIEW_SEC_RIGHT := 1.5
const REVIEW_SEC_WRONG := 4.0
const HIT_NAMES: Array[String] = ["HIT!", "STRONG!", "HEAVY!!", "ULTIMATE!!!"]
const RUN_NAMES := {"house": "Challenge House", "gym": "Gym", "champion": "Champion Gym"}
const FOE_NAMES := {"house": "CHALLENGER", "gym": "GYM LEADER", "champion": "CHAMPION"}
# Counter damage and the essay pass score, by the run's tier.
const TIERS := {
	"easy": {"counter": 15, "essay_pass": 0.5},
	"medium": {"counter": 25, "essay_pass": 0.65},
	"hard": {"counter": 35, "essay_pass": 0.8},
}
const HIT_STOP_BASE := 0.06

@export_group("Intro")
## Start-of-battle entrance (see _play_intro). Turn it off to drop straight into the fight.
@export var play_intro := true
@export var intro_text := "%s wants to battle!"
@export var intro_card_slide := 420.0
@export var intro_dialogue_slide := 700.0
@export var intro_vs_hold := 0.5
@export var intro_flash_strength := 0.85
@export var intro_shake := 10.0

@export_group("Sound effects")
@export var sfx_whoosh: AudioStream
@export var sfx_land: AudioStream
@export var sfx_vs: AudioStream
@export var sfx_click: AudioStream
@export var sfx_correct: AudioStream
@export var sfx_wrong: AudioStream
@export var sfx_hit: AudioStream
@export var sfx_hurt: AudioStream
@export var sfx_win: AudioStream
@export var sfx_lose: AudioStream

@export_group("Juice")
@export var hit_shake := 8.0
@export var hit_flash_strength := 0.45
## Screen flash when Kuiz is hit, and when Kuiz goes down.
@export var hurt_flash_color := Color(1.0, 0.35, 0.3)
@export var lose_flash_color := Color(0.8, 0.25, 0.2)
## How long the VICTORY / DEFEATED banner stays before the result panel appears.
@export var end_banner_hold := 1.5

@onready var stage: ArenaStage = %Stage
@onready var damage_template: Label = %DamageTemplate
@onready var end_banner: Label = %EndBanner
@onready var confetti: CPUParticles2D = %Confetti
@onready var blocker: Control = %Blocker
@onready var enemy_card: Control = %EnemyCard
@onready var player_card: Control = %PlayerCard
@onready var gauge_row: HBoxContainer = %GaugeRow
@onready var dialogue: Control = %Dialogue
@onready var vs_label: Label = %VsLabel
@onready var flash: ColorRect = %Flash
@onready var cam: Camera2D = %Camera2D
@onready var mc_box: VBoxContainer = %MCBox
@onready var mc_template: Button = %McTemplate
@onready var flee_btn: Button = %FleeButton
@onready var title_label: Label = %TitleLabel
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
@onready var report_btn: Button = %ReportButton

@onready var qscroll: Control = question_label.get_parent()

var _run: Array[Dictionary] = []
var _kind := "house"
var _standalone := false
var _index := 0
var _q: Dictionary = {}
var _qtype: String = "essay"
var _tier: String = "medium"
var _mc_options: Array[String] = []
var _correct := 0
var _streak := 0
var _best_streak := 0
var _loss_streak := 0
var _shield_used := false
var _hit_tier := 0
# Questions whose mastery this run already recorded; a repeated item or a retry does not count twice.
var _seen := {}
var _enemy_hp: int = 0
var _enemy_max: int = 0
var _player_hp: int = 0
var _player_max: int = 0
# HP last shown on the bars; a drop since then is what triggers the pet / robot reactions.
var _shown_enemy_hp: int = 0
var _shown_player_hp: int = 0
var _awaiting: bool = false
var _over: bool = false
var _phase := "answer"
var _last_feedback := ""
# The grade request in flight: its job id, what was typed and how it is graded, and the feedback to
# show if the server cannot answer. Contract: docs/systems/battle.md §5.
var _job_id := ""
var _typed := ""
var _grade_mode := ""
var _offline_feedback := ""
# The rubric points the last essay covered, for the review beat.
var _last_covered: Array = []
var _shake_tween: Tween

func _ready() -> void:
	_run = SessionManager.battle_run
	_standalone = _run.is_empty()
	if _standalone:
		# Direct scene run fallback: one easy question so the arena is testable solo.
		_run = [{"q_index": -1, "question": {"id": "q_preview", "text": "Preview: What is the capital of France?", "type": "identification", "answer": "Paris", "confidence": 0.9, "key_concepts": []}}]
	else:
		_kind = SessionManager.battle_kind
	_tier = SessionManager.RUN_TIER[_kind]
	_player_max = CompanionState.battle_max_hp()
	_player_hp = _player_max
	_enemy_max = _run.size() * HP_PER_ITEM
	_enemy_hp = _enemy_max
	enemy_hp_bar.max_value = _enemy_max
	player_hp_bar.max_value = _player_max
	CompanionState.in_run = true
	_refresh_gauges()
	CompanionState.stats_changed.connect(_refresh_gauges)
	_refresh_bars()
	var foe: String = FOE_NAMES[_kind]
	enemy_name.text = foe
	# Foes carry no stored level: their tier stands in so both cards match.
	enemy_level.text = "Lv%d" % (SessionManager.DIFFICULTIES.find(_tier) + 1)
	player_name.text = "KUIZ"
	player_level.text = "Lv%d" % CompanionState.level
	stage.setup(_kind != "house")
	_bind_item()
	judging_label.visible = false
	result_panel.visible = false
	submit_btn.pressed.connect(_on_submit)
	flee_btn.pressed.connect(_on_flee)
	retry_btn.pressed.connect(_on_retry)
	continue_btn.pressed.connect(_on_continue)
	report_btn.pressed.connect(_on_report)
	Api.job_status.connect(_on_job_status)
	if play_intro:
		_play_intro(foe)
	else:
		stage.start_hover()

func _exit_tree() -> void:
	CompanionState.in_run = false

# Kuiz's care stats on its card move as the run changes them. Each gauge in %GaugeRow is named after
# the CompanionState stat it shows.
func _refresh_gauges() -> void:
	for gauge in gauge_row.get_children():
		gauge.set("value", float(CompanionState.get(gauge.name)) / CompanionState.STAT_MAX)

# Shows the current item: its question, and its answer controls for the type it is played as.
func _bind_item() -> void:
	var item: Dictionary = _run[_index]
	_q = item["question"]
	_qtype = str(_q.get("type", "essay")).to_lower()
	_mc_options = []
	if _qtype == "multiple_choice":
		_mc_options = _mc_choices()
		if _mc_options.size() < 2:
			_qtype = "identification"
	for b in mc_box.get_children():
		if b != mc_template:
			b.queue_free()
	title_label.text = "%s  %d/%d" % [RUN_NAMES[_kind], _index + 1, _run.size()]
	qtype_label.text = "%s · Streak %d" % [_qtype.capitalize().replace("_", " "), _streak]
	question_label.text = str(_q.get("text", ""))
	qscroll.visible = true
	answer_input.text = ""
	answer_input.placeholder_text = "Type the exact term..." if _qtype == "identification" else "Explain in your own words..."
	result_label.text = ""
	if _qtype == "multiple_choice":
		_build_mc_buttons()
	_show_answer_controls(true)
	_phase = "answer"

# Start-of-battle entrance. The bots fly onto their pads (ArenaStage.play_intro), the HUD slides in
# around them, "VS" slams down and the screen flashes when the foe lands. Controls stay locked until
# it ends. Every duration is an export on this node or on the Stage.
func _play_intro(foe: String) -> void:
	_set_inputs(false)
	stage.play_intro()  # sets the start poses now, before the first frame
	_sfx(sfx_whoosh)
	_sfx_later(sfx_whoosh, stage.intro_foe_delay, 0.75)
	stage.pet_landed.connect(func() -> void: _sfx(sfx_land, 1.2, 0.7))
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
		_sfx(sfx_land)
		flash.modulate.a = intro_flash_strength
		create_tween().tween_property(flash, "modulate:a", 0.0, 0.4)
		_screen_shake(intro_shake, 0.3))
	# "VS" slams in over the arena, holds, then fades.
	get_tree().create_timer(0.85).timeout.connect(func() -> void:
		_sfx(sfx_vs)
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

func _sfx(stream: AudioStream, pitch := 1.0, gain := 1.0) -> void:
	MusicManager.play_sfx_layered(stream, pitch, gain)

# Holds only the stream, so a pending sound still plays (or is simply dropped) if the scene changes first.
func _sfx_later(stream: AudioStream, delay: float, pitch := 1.0) -> void:
	MusicManager.get_tree().create_timer(delay).timeout.connect(func() -> void: MusicManager.play_sfx_layered(stream, pitch))

# Locks or unlocks everything the player can press or type into.
func _set_inputs(on: bool) -> void:
	flee_btn.disabled = not on
	submit_btn.disabled = not on
	answer_input.editable = on
	_set_mc_enabled(on)

func _on_submit() -> void:
	if _awaiting or _over:
		return
	var answer: String = answer_input.text.strip_edges()
	if answer == "":
		result_label.text = "Type an answer first."
		return
	_sfx(sfx_click)
	_last_covered = []
	_grade_mode = "essay"
	_offline_feedback = ""
	if _qtype == "identification":
		# The answer key settles most answers on the device; only a near-miss asks the server.
		var check := Api.check_identification(_q, answer, _tier == "hard")
		if check["verdict"] != "near":
			_resolve(check["verdict"] == "correct", check["feedback"])
			return
		_grade_mode = "identification"
		_offline_feedback = check["feedback"]
	_awaiting = true
	_typed = answer
	submit_btn.disabled = true
	judging_label.visible = true
	result_label.text = ""
	_job_id = Api.new_job_id("grade")
	Api.grade_battle_question(_job_id, _q, answer, _grade_mode)

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

func _on_mc_pick(_button: Button, correct: bool) -> void:
	if _over or _awaiting or _phase != "answer":
		return
	_sfx(sfx_click)
	_resolve(correct, "")

# The server's grade. When it cannot answer (offline, an error), the device grades instead: a near-miss
# counts as a miss, an essay gets the offline rubric mark.
func _on_job_status(job_id: String, status: String, _progress: float, result: Variant) -> void:
	if job_id != _job_id or not _awaiting or status == "processing":
		return
	_awaiting = false
	judging_label.visible = false
	var data: Dictionary = result if status == "completed" and typeof(result) == TYPE_DICTIONARY else {}
	if data.is_empty():
		if _grade_mode == "identification":
			data = {"score": 0.0, "feedback": _offline_feedback}
		else:
			data = Api.essay_offline(_q, _typed)
			data["feedback"] = "Graded offline. " + str(data["feedback"])
	var score: float = clampf(float(data.get("score", 0.0)), 0.0, 1.0)
	var feedback: String = str(data.get("feedback", ""))
	_last_covered = data.get("covered", [])
	if _grade_mode == "identification":
		_resolve(score >= 0.5, feedback)
	else:
		# A failed essay still lands part of the counter: the closer it was, the softer the blow.
		_resolve(score >= float(TIERS[_tier]["essay_pass"]), feedback, 0.4 + 0.6 * (1.0 - score))

# Settles one item. Correct: the streak grows (and the hit with it), Kuiz heals a little, the foe's bar
# drops one item's worth but never to 0 before the last item, so every item is always played. Wrong: the
# streak breaks (the first miss of a run is forgiven when Kuiz has the focus) and the counter grows with
# each miss in a row.
func _resolve(correct: bool, feedback: String, miss_scale := 1.0) -> void:
	_phase = "resolving"
	_set_inputs(false)
	var q_idx: int = _run[_index]["q_index"]
	if q_idx >= 0 and not _seen.has(q_idx):
		_seen[q_idx] = true
		SessionManager.record_battle_outcome(SessionManager.battle_topic_id, q_idx, correct)
	var last := _index == _run.size() - 1
	_last_feedback = feedback
	CompanionState.play_item(correct)
	if correct:
		_correct += 1
		_streak += 1
		_best_streak = maxi(_best_streak, _streak)
		_loss_streak = 0
		_hit_tier = 0 if _streak < 3 else (1 if _streak < 5 else (2 if _streak < 8 else 3))
		_player_hp = mini(_player_max, _player_hp + HEAL_ON_CORRECT)
		_enemy_hp = maxi(0 if last else 1, _enemy_hp - HP_PER_ITEM)
		result_label.text = "%s  Streak %d" % [HIT_NAMES[_hit_tier], _streak]
	else:
		var counter := maxi(1, roundi(float(TIERS[_tier]["counter"]) * MISS_MULT[mini(_loss_streak, MISS_MULT.size() - 1)] * miss_scale * CompanionState.counter_mult()))
		_loss_streak += 1
		if CompanionState.has_streak_shield() and not _shield_used and _streak > 0:
			_shield_used = true
		else:
			_streak = 0
		_player_hp = maxi(0, _player_hp - counter)
		CompanionState.hurt(counter)
		result_label.text = "Missed! The foe strikes back for %d." % counter
	_finish_turn(correct)

func _refresh_bars() -> void:
	_shown_enemy_hp = _enemy_hp
	_shown_player_hp = _player_hp
	enemy_hp_bar.value = _enemy_hp
	player_hp_bar.value = _player_hp
	enemy_hp_text.text = "%d/%d" % [_enemy_hp, _enemy_max]
	player_hp_text.text = "%d/%d" % [_player_hp, _player_max]

# Plays out the turn's blows, then decides what happens next. A correct answer sends Kuiz at the foe; a
# wrong one sends the foe at Kuiz. HP drops when each blow lands.
func _finish_turn(correct: bool) -> void:
	var enemy_loss := _shown_enemy_hp - _enemy_hp
	var player_loss := _shown_player_hp - _player_hp
	blocker.visible = true
	if enemy_loss > 0:
		stage.pet_strike()
		await stage.strike_hit
		_land_hit(false, enemy_loss)
		await stage.strike_finished
	if player_loss > 0:
		stage.enemy_strike()
		await stage.strike_hit
		_land_hit(true, player_loss)
		await stage.strike_finished
	elif _player_hp > _shown_player_hp:
		_shown_player_hp = _player_hp
		create_tween().tween_property(player_hp_bar, "value", float(_player_hp), 0.3)
		player_hp_text.text = "%d/%d" % [_player_hp, _player_max]
	blocker.visible = false
	if _player_hp <= 0:
		_lose()
	elif _index == _run.size() - 1:
		_win()
	else:
		_show_review(correct)

# The review beat: the answer and its source, with Next held back so a miss is actually read.
func _show_review(correct: bool) -> void:
	_phase = "review"
	var text := "Answer: %s" % str(_q.get("answer", "")).strip_edges()
	if _qtype == "essay":
		text = "Model answer: %s" % str(_q.get("model_answer", _q.get("answer", ""))).strip_edges()
		var rubric := Api.rubric_for(_q)
		for i in rubric.size():
			var hit := i < _last_covered.size() and bool(_last_covered[i])
			text += "\n%s %s" % ["✓" if hit else "✗", str((rubric[i] as Dictionary).get("point", ""))]
	var why := str(_q.get("explanation", "")).strip_edges()
	if why != "":
		text += "\n" + why
	if _last_feedback != "":
		text += "\n" + _last_feedback
	var source := str(_q.get("source", "")).strip_edges()
	if source != "":
		text += "\n“%s”" % (source.left(140) + ("…" if source.length() > 140 else ""))
	result_title.text = "Correct!  Streak %d" % _streak if correct else "Not quite."
	xp_label.text = text
	retry_btn.visible = false
	report_btn.visible = true
	report_btn.disabled = false
	report_btn.text = "Report"
	continue_btn.text = "Next"
	continue_btn.disabled = true
	qscroll.visible = false
	_show_answer_controls(false)
	result_panel.visible = true
	await get_tree().create_timer(REVIEW_SEC_RIGHT if correct else REVIEW_SEC_WRONG).timeout
	if is_instance_valid(continue_btn) and _phase == "review":
		continue_btn.disabled = false

# A blow connects: the bar drops, the number flies up, the screen punches.
func _land_hit(on_pet: bool, amount: int) -> void:
	if on_pet:
		_shown_player_hp = _player_hp
		create_tween().tween_property(player_hp_bar, "value", float(_player_hp), 0.3)
		player_hp_text.text = "%d/%d" % [_player_hp, _player_max]
		_sfx(sfx_hurt)
		_sfx_later(sfx_wrong, 0.05)
		_flash_screen(hurt_flash_color, hit_flash_strength)
	else:
		_shown_enemy_hp = _enemy_hp
		create_tween().tween_property(enemy_hp_bar, "value", float(_enemy_hp), 0.3)
		enemy_hp_text.text = "%d/%d" % [_enemy_hp, _enemy_max]
		_sfx(sfx_hit, 1.0 + 0.12 * _hit_tier)
		_sfx_later(sfx_correct, 0.1, 1.0 + 0.12 * _hit_tier)
		_flash_screen(Color.WHITE, minf(1.0, hit_flash_strength * (0.7 + 0.25 * _hit_tier)))
		if _hit_tier > 0:
			_hit_stop(HIT_STOP_BASE * _hit_tier)
	var power := 1.0 if on_pet else 1.0 + 0.6 * _hit_tier
	_screen_shake(hit_shake * power, 0.22 + (0.0 if on_pet else 0.06 * _hit_tier))
	var label := "-%d" % amount if on_pet else HIT_NAMES[_hit_tier]
	_pop_damage(label, stage.impact_point(on_pet), Color("C97970") if on_pet else Color("D6A85F"))

# The answer field, Fight button and choice buttons give way to the result panel, so it fits the smaller box.
func _show_answer_controls(on: bool) -> void:
	var is_mc := _qtype == "multiple_choice"
	answer_input.visible = on and not is_mc
	submit_btn.visible = on and not is_mc
	mc_box.visible = on and is_mc

func _flash_screen(color: Color, strength: float) -> void:
	flash.color = color
	flash.modulate.a = strength
	create_tween().tween_property(flash, "modulate:a", 0.0, 0.4)

# A number that pops up at `at`, floats up and fades. Copies the DamageTemplate label.
func _pop_damage(text: String, at: Vector2, color: Color) -> void:
	var l := damage_template.duplicate() as Label
	l.text = text
	l.visible = true
	l.add_theme_color_override("font_color", color)
	add_child(l)
	l.reset_size()
	l.pivot_offset = l.size / 2.0
	l.position = at - l.size / 2.0
	l.scale = Vector2.ONE * 0.4
	var t := create_tween().set_parallel()
	t.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "position:y", l.position.y - 110.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	t.chain().tween_callback(l.queue_free)

# The end-of-battle moment: a big banner across the arena, confetti on a win, then the result panel.
func _end_sequence(win: bool, banner: String) -> void:
	if win:
		stage.enemy_defeat()
		stage.pet_win()
		_sfx(sfx_win)
		confetti.position.x = size.x / 2.0
		confetti.emission_rect_extents.x = size.x / 2.0
		confetti.restart()
		_flash_screen(Color.WHITE, 0.6)
	else:
		stage.enemy_attack()
		_sfx(sfx_lose)
		_flash_screen(lose_flash_color, 0.35)
	end_banner.text = banner
	end_banner.add_theme_color_override("font_color", Color("D6A85F") if win else Color("C97970"))
	end_banner.pivot_offset = end_banner.size / 2.0
	end_banner.scale = Vector2.ONE * 3.0
	end_banner.modulate.a = 0.0
	end_banner.visible = true
	var b := create_tween().set_parallel()
	b.tween_property(end_banner, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.tween_property(end_banner, "modulate:a", 1.0, 0.2)
	await get_tree().create_timer(end_banner_hold).timeout
	create_tween().tween_property(end_banner, "modulate:a", 0.0, 0.35)
	_show_answer_controls(false)
	result_panel.visible = true
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
	_phase = "end"
	_enemy_hp = 0
	create_tween().tween_property(enemy_hp_bar, "value", 0.0, 0.3)
	enemy_hp_text.text = "0/%d" % _enemy_max
	var line := "%d/%d correct  •  best streak %d" % [_correct, _run.size(), _best_streak]
	var cleared := true
	if not _standalone:
		var r := SessionManager.report_run(true, _correct, _run.size(), _best_streak)
		cleared = bool(r["cleared"])
		if cleared:
			line += "\nStars %d/3  •  +%d crystals  •  +%d XP" % [int(r["stars"]), int(r["coins"]), int(r["xp"])]
			line += "\nFirst clear bonus!" if bool(r["first"]) else "\nReplay: reduced rewards."
		else:
			line += "\nGet %d%% right to earn a star and clear it.\n+%d crystals  •  +%d XP for the effort." % [
				roundi(SessionManager.STAR_ACCURACY[0] * 100), int(r["coins"]), int(r["xp"])]
		line += _study_goal_line()
	result_title.text = "%s cleared!" % RUN_NAMES[_kind] if cleared else "Kuiz made it through!"
	xp_label.text = line
	retry_btn.visible = not cleared
	retry_btn.text = "↻ Try Again"
	continue_btn.text = "Overworld"
	continue_btn.disabled = false
	qscroll.visible = false
	# Without a star the foe stays up (no defeat pose), so Try Again starts from a standing foe.
	_end_sequence(cleared, ("CHAMPION!" if _kind == "champion" else "VICTORY!") if cleared else "SURVIVED")

# A finished run (cleared or not) meets the daily study goal; a fled one does not.
func _study_goal_line() -> String:
	var paid := GameState.note_study(0, 1)
	if paid == 0:
		return ""
	SaveManager.save_progress()
	return "\nDaily study goal met: %d-day streak  •  +%d crystals" % [GameState.study_streak, paid]

# Kuiz is out of HP: it topples over, then the player chooses to leave or to try the run again.
func _lose() -> void:
	_over = true
	_phase = "end"
	var line := "%d/%d correct before falling." % [_correct, _run.size()]
	if not _standalone:
		var r := SessionManager.report_run(false, _correct, _run.size(), _best_streak)
		line += "\n+%d crystals  •  +%d XP for the effort." % [int(r["coins"]), int(r["xp"])]
		line += _study_goal_line()
	result_title.text = "Kuiz is down!"
	xp_label.text = line
	retry_btn.text = "↻ Try Again"
	retry_btn.visible = true
	continue_btn.text = "Exit"
	continue_btn.disabled = false
	qscroll.visible = false
	stage.pet_defeat()
	_end_sequence(false, "DEFEATED")

# Try Again: the same run reshuffled, from item 1, Kuiz at full HP.
func _on_retry() -> void:
	_sfx(sfx_click)
	if not _standalone:
		SessionManager.reshuffle_run()
		_run = SessionManager.battle_run
	stage.pet_stand()
	_index = 0
	_correct = 0
	_streak = 0
	_best_streak = 0
	_loss_streak = 0
	_shield_used = false
	_enemy_max = _run.size() * HP_PER_ITEM
	_enemy_hp = _enemy_max
	_player_hp = _player_max
	enemy_hp_bar.max_value = _enemy_max
	_over = false
	_refresh_bars()
	result_panel.visible = false
	end_banner.visible = false
	_bind_item()
	_set_inputs(true)

# Flags the item's AI-written question or feedback as wrong or offensive (Google Play's AI-content rule).
func _on_report() -> void:
	_sfx(sfx_click)
	Api.report_content(Api.new_job_id("report"), "feedback", "%s
Answer key: %s
Feedback: %s" % [_q.get("text", ""), _q.get("answer", ""), _last_feedback])
	report_btn.disabled = true
	report_btn.text = "Reported"

func _on_continue() -> void:
	_sfx(sfx_click)
	if _phase == "review":
		_index += 1
		report_btn.visible = false
		result_panel.visible = false
		_bind_item()
		_set_inputs(true)
		return
	get_tree().change_scene_to_file("res://scenes/overworld/region_map.tscn")

# Leaving mid-run forfeits it: no clear and no pay, but the items answered keep their mastery.
func _on_flee() -> void:
	_sfx(sfx_click)
	SaveManager.save_progress()
	get_tree().change_scene_to_file("res://scenes/overworld/region_map.tscn")
