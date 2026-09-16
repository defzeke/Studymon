extends Control
## Phase 3: AI Codex — all unlocked "Did You Know?" tidbits, plus a
## post-Level-5 pop quiz reusing simple question UI (battle UI lands in Phase 7).

@onready var entries_box: VBoxContainer = $Content/EntriesBox
@onready var quiz_button: Button = $Content/QuizButton
@onready var back_button: Button = $Content/BackButton
@onready var quiz_box: VBoxContainer = $Content/QuizBox
@onready var quiz_question: Label = $Content/QuizBox/QuizQuestion
@onready var quiz_feedback: Label = $Content/QuizBox/QuizFeedback
@onready var ans_buttons: Array[Button] = [$Content/QuizBox/Ans0, $Content/QuizBox/Ans1, $Content/QuizBox/Ans2]

const QUIZ := [
	{
		"q": "Where does an AI like me get its knowledge?",
		"options": ["Training data (examples)", "Pre-loaded answers", "Magic"],
		"correct": 0,
	},
	{
		"q": "When you pet me for a good answer, what is that called?",
		"options": ["Feedback", "Feeding", "Sleeping"],
		"correct": 0,
	},
	{
		"q": "How do I get smarter at brand-new things?",
		"options": ["Trial-and-error practice", "One lucky guess", "Waiting quietly"],
		"correct": 0,
	},
]

var _quiz_index: int = -1
var _quiz_score: int = 0

func _ready() -> void:
	theme = load("res://ui/app_theme.tres") as Theme
	_build_entries()
	quiz_button.pressed.connect(_on_quiz_pressed)
	back_button.pressed.connect(_on_back)
	for i in ans_buttons.size():
		ans_buttons[i].pressed.connect(_on_answer.bind(i))
	quiz_box.visible = false
	if CompanionState.level >= 5:
		quiz_button.disabled = false
		quiz_button.text = "Pop Quiz"
	else:
		quiz_button.disabled = true
		quiz_button.text = "Pop Quiz (reach Lv 5)"

func _build_entries() -> void:
	for child in entries_box.get_children():
		child.queue_free()
	for lv in range(1, CompanionState.MAX_LEVEL + 1):
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if CompanionState.CURRICULUM.has(lv) and CompanionState.codex.has(CompanionState.CURRICULUM[lv]):
			label.text = "Lv %d: %s" % [lv, CompanionState.CURRICULUM[lv]]
		else:
			label.text = "Lv %d: ??? — keep training me!" % lv
		entries_box.add_child(label)
	_build_topic_entries()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")

## Phase 8: confirmed study topics with per-question mastery badges.
func _build_topic_entries() -> void:
	var topics := SessionManager.get_topics_cache()
	if topics.is_empty():
		return
	var header := Label.new()
	header.text = "— Study Topics —"
	entries_box.add_child(header)
	for t in topics:
		var tid := str(t.get("id", ""))
		var name_label := Label.new()
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.text = "%s (%d Q)" % [str(t.get("name", tid)), int(t.get("question_count", 0))]
		entries_box.add_child(name_label)
		var qs: Array = t.get("questions", [])
		for i in qs.size():
			var q: Dictionary = qs[i]
			var badge: Dictionary = SessionManager.mastery_badge(SessionManager.get_mastery_state(tid, i))
			var row := Label.new()
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.text = "%s Q%d [%s]: %s" % [str(badge["emoji"]), i + 1, str(badge["name"]), str(q.get("text", "")).left(80)]
			row.modulate = badge["color"]
			entries_box.add_child(row)

func _on_quiz_pressed() -> void:
	_quiz_index = 0
	_quiz_score = 0
	quiz_box.visible = true
	for b in ans_buttons:
		b.visible = true
	quiz_feedback.text = ""
	_show_question()

func _show_question() -> void:
	var item: Dictionary = QUIZ[_quiz_index]
	quiz_question.text = "Q%d: %s" % [_quiz_index + 1, item["q"]]
	var options: Array = item["options"]
	for i in ans_buttons.size():
		ans_buttons[i].text = options[i]
		ans_buttons[i].disabled = false

func _on_answer(choice: int) -> void:
	var item: Dictionary = QUIZ[_quiz_index]
	if choice == int(item["correct"]):
		_quiz_score += 1
		quiz_feedback.text = "Correct!"
	else:
		var options: Array = item["options"]
		quiz_feedback.text = "Not quite — it was: %s" % options[int(item["correct"])]
	for b in ans_buttons:
		b.disabled = true
	_quiz_index += 1
	if _quiz_index < QUIZ.size():
		var t := create_tween()
		t.tween_interval(1.0)
		t.tween_callback(_show_question)
	else:
		var t2 := create_tween()
		t2.tween_interval(1.0)
		t2.tween_callback(_show_score)

func _show_score() -> void:
	quiz_question.text = "Quiz complete!"
	quiz_feedback.text = "You scored %d/%d. %s" % [_quiz_score, QUIZ.size(), _verdict()]
	for b in ans_buttons:
		b.visible = false

func _verdict() -> String:
	if _quiz_score == QUIZ.size():
		return "Perfect — you think like an AI trainer!"
	return "Good effort — review the Codex above!"
