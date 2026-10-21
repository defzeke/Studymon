extends Control
## Phase 5: Session List — history of review topics (GDD §5.1)
## Combat-icon entry point: shows past topics, resume or Add New Topic.

@onready var list_box: VBoxContainer = $Content/Scroll/ListBox
@onready var add_btn: Button = $Content/AddButton
@onready var back_btn: Button = $Content/BackButton
@onready var empty_label: Label = $Content/EmptyLabel

func _ready() -> void:
	theme = load("res://assets/theme/app_theme.tres") as Theme
	add_btn.pressed.connect(_on_add_new)
	back_btn.pressed.connect(_on_back)
	SessionManager.topics_listed.connect(_on_topics_listed)
	_build_from_cache()
	SessionManager.list_topics()

func _build_from_cache() -> void:
	_on_topics_listed(SessionManager.get_topics_cache())

func _on_topics_listed(topics: Array[Dictionary]) -> void:
	for c in list_box.get_children():
		c.queue_free()
	if topics.is_empty():
		empty_label.visible = true
		empty_label.text = "No topics yet — tap Add New Topic to turn a PDF into gyms!"
		return
	empty_label.visible = false
	for t in topics:
		var row := _make_row(t)
		list_box.add_child(row)

func _make_row(topic: Dictionary) -> Control:
	var id: String = str(topic.get("id", ""))
	var name: String = str(topic.get("name", id))
	var count: int = int(topic.get("question_count", 0))
	# Fallback: derive count from stored questions
	if count == 0 and topic.has("questions"):
		var qs = topic["questions"]
		if qs is Array:
			count = qs.size()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var open_btn := Button.new()
	open_btn.custom_minimum_size = Vector2(0, 72)
	open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open_btn.text = "  %s  ·  %d Qs" % [name, count]
	open_btn.pressed.connect(_on_open_topic.bind(topic))
	row.add_child(open_btn)
	var cards_btn := Button.new()
	cards_btn.custom_minimum_size = Vector2(120, 72)
	cards_btn.text = "Cards"
	cards_btn.disabled = count == 0
	cards_btn.pressed.connect(_on_open_cards.bind(topic))
	row.add_child(cards_btn)
	return row

func _load_topic(topic: Dictionary) -> void:
	var questions: Array[Dictionary] = []
	if topic.has("questions") and topic["questions"] is Array:
		for q in topic["questions"]:
			if q is Dictionary:
				questions.append(q)
	SessionManager.set_editing_topic(str(topic.get("id", "")), questions)

func _on_open_topic(topic: Dictionary) -> void:
	_load_topic(topic)
	get_tree().change_scene_to_file("res://scenes/review_session/categorizer.tscn")

func _on_open_cards(topic: Dictionary) -> void:
	_load_topic(topic)
	SessionManager.current_topic_id = str(topic.get("id", ""))
	SessionManager.flashcards_return = "res://scenes/ui/session_list.tscn"
	get_tree().change_scene_to_file("res://scenes/review_session/flashcards.tscn")

func _on_add_new() -> void:
	SessionManager.pending_questions.clear()
	SessionManager.editing_topic_id = "topic_%d" % (int(Time.get_unix_time_from_system()) % 100000)
	get_tree().change_scene_to_file("res://scenes/review_session/categorizer.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/boot/peek.tscn")
