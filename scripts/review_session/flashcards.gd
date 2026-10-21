extends Control
## Flashcard Sanctuary: untimed review of a topic's questions, no HP, no quota, no game over.
## Again re-queues three cards ahead, Hard sends the card to the end, Easy banks it (New or
## Remaster become Learning; Mastered is earned only in battle).
## Contract: docs/systems/gameplay-structure.md §3.4

const SAGE := Color("E8F0EA")
const OFF_WHITE := Color("F7F5EF")
const TEAL := Color("4F8F89")
const GREEN := Color("78A982")
const AMBER := Color("D6A85F")
const CORAL := Color("C97970")
const SLATE := Color("29383A")
const SLATE_GRAY := Color("687778")
const AGAIN_GAP := 3

@onready var background: ColorRect = $Background
@onready var back_btn: Button = $Margin/List/TopBar/BackButton
@onready var progress_label: Label = $Margin/List/TopBar/ProgressLabel
@onready var card_panel: PanelContainer = $Margin/List/CardPanel
@onready var badge_label: Label = $Margin/List/CardPanel/CardBox/BadgeLabel
@onready var front_label: Label = $Margin/List/CardPanel/CardBox/FrontLabel
@onready var answer_label: Label = $Margin/List/CardPanel/CardBox/AnswerLabel
@onready var source_label: Label = $Margin/List/CardPanel/CardBox/SourceLabel
@onready var flip_btn: Button = $Margin/List/FlipButton
@onready var rate_row: HBoxContainer = $Margin/List/RateRow
@onready var again_btn: Button = $Margin/List/RateRow/AgainButton
@onready var hard_btn: Button = $Margin/List/RateRow/HardButton
@onready var easy_btn: Button = $Margin/List/RateRow/EasyButton
@onready var done_label: Label = $Margin/List/DoneLabel

var _topic_id: String = ""
var _questions: Array[Dictionary] = []
var _queue: Array = []
var _banked: int = 0

func _ready() -> void:
	_topic_id = SessionManager.current_topic_id
	if _topic_id == "":
		_topic_id = SessionManager.editing_topic_id
	_questions = SessionManager.get_pending_questions()
	_queue = SessionManager.flashcard_deck(_topic_id)
	_style()
	back_btn.pressed.connect(_on_back)
	flip_btn.pressed.connect(_on_flip)
	again_btn.pressed.connect(_rate.bind("again"))
	hard_btn.pressed.connect(_rate.bind("hard"))
	easy_btn.pressed.connect(_rate.bind("easy"))
	_show_card()

func _style() -> void:
	background.color = SAGE
	for l: Label in [progress_label, front_label, answer_label, badge_label, done_label]:
		l.add_theme_color_override("font_color", SLATE)
	source_label.add_theme_color_override("font_color", SLATE_GRAY)
	front_label.add_theme_font_size_override("font_size", 36)
	var card := _box(OFF_WHITE, 24)
	card.border_color = TEAL
	card.set_border_width_all(2)
	card_panel.add_theme_stylebox_override("panel", card)
	for pair: Array in [[back_btn, TEAL], [flip_btn, TEAL], [again_btn, CORAL], [hard_btn, AMBER], [easy_btn, GREEN]]:
		_style_button(pair[0], pair[1])

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(16)
	return sb

func _style_button(btn: Button, color: Color) -> void:
	btn.add_theme_stylebox_override("normal", _box(color, 16))
	btn.add_theme_stylebox_override("hover", _box(color.lightened(0.1), 16))
	btn.add_theme_stylebox_override("pressed", _box(color.darkened(0.2), 16))
	var focus := _box(color, 16)
	focus.border_color = SLATE
	focus.set_border_width_all(4)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_color_override("font_color", SLATE)
	btn.add_theme_color_override("font_hover_color", SLATE)
	btn.add_theme_color_override("font_pressed_color", SLATE)

func _show_card() -> void:
	progress_label.text = "%d left · %d banked" % [_queue.size(), _banked]
	if _queue.is_empty():
		_finish()
		return
	var q: Dictionary = _questions[int(_queue[0])]
	var badge: Dictionary = SessionManager.mastery_badge(SessionManager.get_mastery_state(_topic_id, int(_queue[0])))
	badge_label.text = "%s %s · %s · %s" % [str(badge["emoji"]), str(badge["name"]), str(q.get("type", "essay")).capitalize(), str(q.get("difficulty", "medium")).capitalize()]
	front_label.text = str(q.get("text", ""))
	answer_label.text = _answer_text(q)
	var source := str(q.get("source", ""))
	source_label.text = source if source != answer_label.text else ""
	answer_label.visible = false
	source_label.visible = false
	flip_btn.visible = true
	rate_row.visible = false

func _answer_text(q: Dictionary) -> String:
	var parts: Array[String] = []
	var answer := str(q.get("answer", "")).strip_edges()
	if answer != "":
		parts.append(answer)
	var concepts: Array = q.get("key_concepts", [])
	if str(q.get("type", "")) == "essay" and not concepts.is_empty():
		parts.append("Key ideas: " + ", ".join(concepts))
	return "\n".join(parts) if not parts.is_empty() else "(No answer written for this card.)"

func _on_flip() -> void:
	answer_label.visible = true
	source_label.visible = source_label.text != ""
	flip_btn.visible = false
	rate_row.visible = true

func _rate(rating: String) -> void:
	if _queue.is_empty():
		return
	var qi: int = _queue.pop_front()
	match rating:
		"again":
			_queue.insert(mini(AGAIN_GAP, _queue.size()), qi)
		"hard":
			_queue.append(qi)
		"easy":
			_banked += 1
			if SessionManager.promote_from_review(_topic_id, qi):
				CompanionState.reward_card_banked()
	_show_card()

func _finish() -> void:
	card_panel.visible = false
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
