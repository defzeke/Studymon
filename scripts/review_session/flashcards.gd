extends Control
## Flashcard Sanctuary: untimed review of a topic's questions, no HP, no game over.
## Again re-queues three cards ahead, Hard sends the card to the end, Easy banks it (New or
## Remaster become Learning; Mastered is earned only in battle).
## Contract: docs/systems/gameplay-structure.md §3.4. Every style lives in flashcards.tscn; the card's
## tags are copies of %TagTemplate.

const TEAL := Color("4F8F89")
const GREEN := Color("78A982")
const AMBER := Color("D6A85F")
const CORAL := Color("C97970")
const AGAIN_GAP := 3
const QUESTION_FONT := 38
# Once the answer shows, the question steps back to make room.
const QUESTION_FONT_ANSWERED := 26
const FLIP_TIME := 0.14
const DEAL_TIME := 0.22
const DEAL_OFF := 800.0
const DEAL_TILT := 0.2

const TIER_COLORS := {"easy": GREEN, "medium": AMBER, "hard": CORAL}

@onready var back_btn: Button = %BackButton
@onready var progress_label: Label = %ProgressLabel
@onready var progress_bar: ProgressBar = %Progress
@onready var card_panel: PanelContainer = %CardPanel
@onready var tags: HBoxContainer = %Tags
@onready var tag_template: Label = %TagTemplate
@onready var front_label: Label = %FrontLabel
@onready var back_box: Control = %Back
@onready var under_near: Control = %UnderNear
@onready var under_far: Control = %UnderFar
@onready var answer_label: Label = %AnswerLabel
@onready var source_label: Label = %SourceLabel
@onready var flip_btn: Button = %FlipButton
@onready var rate_row: HBoxContainer = %RateRow
@onready var again_btn: Button = %AgainButton
@onready var hard_btn: Button = %HardButton
@onready var easy_btn: Button = %EasyButton
@onready var done_label: Label = %DoneLabel
@onready var timer_btn: Button = %TimerButton

var _topic_id: String = ""
var _questions: Array[Dictionary] = []
var _queue: Array = []
var _banked: int = 0
var _deck_size: int = 0
# Set once this deck meets the daily study goal, for the progress line.
var _goal_note := ""
# A flip or deal is running; the card's buttons wait for it.
var _moving := false

func _ready() -> void:
	# Review is calm: the home loop, crossfading from the route theme when opened from the map.
	MusicManager.play_main_room()
	_topic_id = SessionManager.current_topic_id
	if _topic_id == "":
		_topic_id = SessionManager.editing_topic_id
	_questions = SessionManager.get_pending_questions()
	_queue = SessionManager.flashcard_deck(_topic_id)
	_deck_size = _queue.size()
	back_btn.pressed.connect(_on_back)
	flip_btn.pressed.connect(_on_flip)
	again_btn.pressed.connect(_rate.bind("again"))
	hard_btn.pressed.connect(_rate.bind("hard"))
	easy_btn.pressed.connect(_rate.bind("easy"))
	# The study timer: a 25-minute focus session (+focus for Kuiz), then a 5-minute rest; it keeps
	# running on other screens. Contract: docs/systems/companion-care.md §6.
	timer_btn.pressed.connect(CompanionState.start_pomodoro)
	_show_card()
	%CardArea.resized.connect(_center_pivots)
	_center_pivots.call_deferred()

func _center_pivots() -> void:
	for c: Control in [card_panel, under_near, under_far]:
		c.pivot_offset = c.size / 2.0

func _process(_delta: float) -> void:
	var p := CompanionState.get_pomodoro_state()
	timer_btn.disabled = p["mode"] != ""
	var left: int = p["remaining"] if p["mode"] != "" else p["focus_total"]
	var label := "Rest" if p["mode"] == "rest" else "Focus"
	timer_btn.text = "%s %02d:%02d" % [label, floori(left / 60.0), left % 60]

# A rounded tag on the card: the mastery state, the type and the tier. Each copy gets its own stylebox
# so its colour does not repaint the others.
func _tag(text: String, color: Color) -> Label:
	var l := tag_template.duplicate() as Label
	l.visible = true
	l.text = text
	var sb := tag_template.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	sb.bg_color = color
	l.add_theme_stylebox_override("normal", sb)
	return l

func _show_card() -> void:
	progress_label.text = "%d left · %d banked · Kuiz focus %d%s" % [_queue.size(), _banked, roundi(CompanionState.focus), _goal_note]
	progress_bar.value = float(_banked) / maxf(1.0, _deck_size)
	under_near.visible = _queue.size() > 1
	under_far.visible = _queue.size() > 2
	if _queue.is_empty():
		_finish()
		return
	var q: Dictionary = _questions[int(_queue[0])]
	var badge: Dictionary = SessionManager.mastery_badge(SessionManager.get_mastery_state(_topic_id, int(_queue[0])))
	var tier := str(q.get("difficulty", "medium")).to_lower()
	for c in tags.get_children():
		if c != tag_template:
			tags.remove_child(c)
			c.queue_free()
	tags.add_child(_tag(str(badge["name"]), badge["color"]))
	tags.add_child(_tag(str(q.get("type", "essay")).capitalize().replace("_", " "), TEAL))
	tags.add_child(_tag(tier.capitalize(), TIER_COLORS.get(tier, AMBER)))
	front_label.text = str(q.get("text", ""))
	answer_label.text = _answer_text(q)
	var source := str(q.get("source", ""))
	source_label.text = source if source != answer_label.text else ""
	back_box.visible = false
	%Gem.visible = true
	front_label.add_theme_font_size_override("font_size", QUESTION_FONT)
	flip_btn.visible = true
	rate_row.visible = false

func _answer_text(q: Dictionary) -> String:
	var parts: Array[String] = []
	var answer := str(q.get("answer", "")).strip_edges()
	if answer != "":
		parts.append(answer)
	var concepts: Array = q.get("key_concepts", [])
	var model := str(q.get("model_answer", "")).strip_edges()
	if str(q.get("type", "")) == "essay" and model != "" and model != answer:
		parts.append(model)
	if str(q.get("type", "")) == "essay" and not concepts.is_empty():
		parts.append("Key ideas: " + ", ".join(concepts))
	var why := str(q.get("explanation", "")).strip_edges()
	if why != "":
		parts.append(why)
	return "\n".join(parts) if not parts.is_empty() else "(No answer written for this card.)"

# The card turns on its edge; the answer is on it when it comes back round.
func _on_flip() -> void:
	if _moving:
		return
	_moving = true
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(card_panel, "scale:x", 0.0, FLIP_TIME).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		back_box.visible = true
		%Gem.visible = false
		source_label.visible = source_label.text != ""
		front_label.add_theme_font_size_override("font_size", QUESTION_FONT_ANSWERED)
		flip_btn.visible = false
		rate_row.visible = true)
	t.tween_property(card_panel, "scale:x", 1.0, FLIP_TIME).set_ease(Tween.EASE_OUT)
	await t.finished
	_moving = false

func _rate(rating: String) -> void:
	if _queue.is_empty() or _moving:
		return
	var qi: int = _queue.pop_front()
	if GameState.note_study(1, 0) > 0:
		_goal_note = " · Daily goal met! +%d crystals" % GameState.STUDY_GOAL_CRYSTALS
	match rating:
		"again":
			_queue.insert(mini(AGAIN_GAP, _queue.size()), qi)
		"hard":
			_queue.append(qi)
		"easy":
			_banked += 1
			if SessionManager.promote_from_review(_topic_id, qi):
				CompanionState.reward_card_banked()
	await _deal(1.0 if rating == "easy" else -1.0)

# The rated card slides off (`dir` 1 is right), and the next rises off the pile.
func _deal(dir: float) -> void:
	_moving = true
	# The rating row stays until the next card shows: hiding it now would resize the card area.
	var rest := card_panel.position
	var out := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	out.tween_property(card_panel, "position:x", rest.x + DEAL_OFF * dir, DEAL_TIME)
	out.tween_property(card_panel, "rotation", DEAL_TILT * dir, DEAL_TIME)
	await out.finished
	card_panel.position = rest
	card_panel.rotation = 0.0
	card_panel.scale = Vector2.ONE * 0.94
	card_panel.modulate.a = 0.0
	_show_card()
	var up := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	up.tween_property(card_panel, "scale", Vector2.ONE, DEAL_TIME)
	up.tween_property(card_panel, "modulate:a", 1.0, DEAL_TIME * 0.7)
	await up.finished
	_moving = false

# The card stays, holding the closing message.
func _finish() -> void:
	for c in %CardBox.get_children():
		(c as Control).visible = c == done_label
	flip_btn.visible = false
	rate_row.visible = false
	done_label.visible = true
	if _banked > 0:
		CompanionState.reward_deck_done()
		done_label.text = "Deck complete — %d card(s) banked. Nicely done!" % _banked
	else:
		done_label.text = "No cards to review yet. Add questions first."
	SaveManager.save_progress()

func _on_back() -> void:
	SaveManager.save_progress()
	get_tree().change_scene_to_file(SessionManager.flashcards_return)
