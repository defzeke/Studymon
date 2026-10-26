extends Control
## Flashcard Sanctuary: untimed review of a topic's questions, no HP, no game over.
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

const BOLD: Font = preload("res://assets/fonts/JosefinSans-Bold.ttf")
const TIER_COLORS := {"easy": GREEN, "medium": AMBER, "hard": CORAL}

@onready var back_btn: Button = %BackButton
@onready var progress_label: Label = %ProgressLabel
@onready var progress_bar: ProgressBar = %Progress
@onready var card_panel: PanelContainer = %CardPanel
@onready var tags: HBoxContainer = %Tags
@onready var front_label: Label = %FrontLabel
@onready var back_box: VBoxContainer = %Back
@onready var answer_label: Label = %AnswerLabel
@onready var source_label: Label = %SourceLabel
@onready var flip_btn: Button = %FlipButton
@onready var rate_row: HBoxContainer = %RateRow
@onready var again_btn: Button = %AgainButton
@onready var hard_btn: Button = %HardButton
@onready var easy_btn: Button = %EasyButton
@onready var done_label: Label = %DoneLabel

var _topic_id: String = ""
var _questions: Array[Dictionary] = []
var _queue: Array = []
var _banked: int = 0
var _deck_size: int = 0

func _ready() -> void:
	# Review is calm: the home loop, crossfading from the route theme when opened from the map.
	MusicManager.play_main_room()
	_topic_id = SessionManager.current_topic_id
	if _topic_id == "":
		_topic_id = SessionManager.editing_topic_id
	_questions = SessionManager.get_pending_questions()
	_queue = SessionManager.flashcard_deck(_topic_id)
	_deck_size = _queue.size()
	_style()
	back_btn.pressed.connect(_on_back)
	flip_btn.pressed.connect(_on_flip)
	again_btn.pressed.connect(_rate.bind("again"))
	hard_btn.pressed.connect(_rate.bind("hard"))
	easy_btn.pressed.connect(_rate.bind("easy"))
	_show_card()

# The home HUD's look over the dimmed Study Room: an Off-White card with a Deep Slate outline and soft
# shadow, a round Back button, a teal progress bar, and buttons in palette colours with Off-White text.
func _style() -> void:
	var card := _box(OFF_WHITE, 32, 28)
	card.shadow_color = Color(SLATE, 0.35)
	card.shadow_size = 12
	card.shadow_offset = Vector2(0, 6)
	card_panel.add_theme_stylebox_override("panel", card)
	var line := StyleBoxLine.new()
	line.color = Color(SLATE, 0.18)
	line.thickness = 3
	%Sep.add_theme_stylebox_override("separator", line)
	progress_bar.add_theme_stylebox_override("background", _flat(Color(OFF_WHITE, 0.25), 7))
	progress_bar.add_theme_stylebox_override("fill", _flat(TEAL, 7))
	_style_button(back_btn, OFF_WHITE, 36)
	for pair: Array in [[flip_btn, TEAL], [again_btn, CORAL], [hard_btn, AMBER], [easy_btn, GREEN]]:
		_style_button(pair[0], pair[1], 24)

func _box(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := _flat(color, radius)
	sb.set_content_margin_all(margin)
	sb.border_color = SLATE
	sb.set_border_width_all(3)
	return sb

func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb

func _style_button(btn: Button, color: Color, radius: int) -> void:
	btn.add_theme_stylebox_override("normal", _box(color, radius, 12))
	btn.add_theme_stylebox_override("hover", _box(color.lightened(0.08), radius, 12))
	btn.add_theme_stylebox_override("pressed", _box(color.darkened(0.15), radius, 12))
	btn.add_theme_stylebox_override("focus", _box(color, radius, 12))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, OFF_WHITE)

# A rounded tag on the card: the mastery state, the type and the tier.
func _tag(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", BOLD)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", OFF_WHITE)
	var sb := _flat(color, 14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 3
	l.add_theme_stylebox_override("normal", sb)
	return l

func _show_card() -> void:
	progress_label.text = "%d left · %d banked" % [_queue.size(), _banked]
	progress_bar.value = float(_banked) / maxf(1.0, _deck_size)
	if _queue.is_empty():
		_finish()
		return
	var q: Dictionary = _questions[int(_queue[0])]
	var badge: Dictionary = SessionManager.mastery_badge(SessionManager.get_mastery_state(_topic_id, int(_queue[0])))
	var tier := str(q.get("difficulty", "medium")).to_lower()
	for c in tags.get_children():
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
	back_box.visible = true
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

# The card stays, holding the closing message.
func _finish() -> void:
	for c in card_panel.get_child(0).get_children():
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
