extends Control
## Phase 5: Categorizer — Upload → AI is studying... → editable question list → Confirm → Play
## Implements build-plan P5: word-count sanity, confidence badges, CRUD list, region generation.
## Phase 10: Quota label + paywall dialog via MonetizationState / Api.quota_exceeded.

@onready var topic_name_field: LineEdit = $Content/TopicRow/TopicName
@onready var file_btn: Button = $Content/UploadRow/FileButton
@onready var paste_area: TextEdit = $Content/PasteArea
@onready var study_btn: Button = $Content/StudyButton
@onready var status_label: Label = $Content/StatusLabel
@onready var loading_bar: ProgressBar = $Content/LoadingBar
@onready var sanity_label: Label = $Content/SanityLabel
@onready var questions_box: VBoxContainer = $Content/Scroll/QuestionsBox
@onready var add_q_btn: Button = $Content/AddQuestionButton
@onready var play_btn: Button = $Content/PlayButton
@onready var back_btn: Button = $Content/BackButton
@onready var file_dialog: FileDialog = $FileDialog
@onready var quota_label: Label = $Content/QuotaLabel
@onready var quota_dialog: ConfirmationDialog = $QuotaDialog

var _studying: bool = false
var _file_bytes: PackedByteArray = PackedByteArray()

func _ready() -> void:
	theme = load("res://ui/app_theme.tres") as Theme
	topic_name_field.placeholder_text = "Topic name (e.g. Biology 101)"
	topic_name_field.text = "My Review Topic"
	paste_area.placeholder_text = "Paste reviewer text here — or pick a PDF/notes file..."
	file_btn.pressed.connect(_on_pick_file)
	file_dialog.file_selected.connect(_on_file_selected)
	study_btn.pressed.connect(_on_study)
	add_q_btn.pressed.connect(_on_add_question)
	play_btn.pressed.connect(_on_play)
	back_btn.pressed.connect(_on_back)
	paste_area.text_changed.connect(_on_paste_changed)
	SessionManager.extraction_started.connect(_on_extraction_started)
	SessionManager.extraction_progress.connect(_on_extraction_progress)
	SessionManager.extraction_completed.connect(_on_extraction_completed)
	SessionManager.extraction_failed.connect(_on_extraction_failed)
	SessionManager.region_generated.connect(_on_region_generated)
	# Phase 10: quota UI + paywall
	_update_quota_label()
	if has_node("/root/MonetizationState"):
		MonetizationState.quota_changed.connect(_update_quota_label)
		MonetizationState.premium_changed.connect(_on_premium_changed)
	Api.quota_exceeded.connect(_on_quota_exceeded)
	loading_bar.visible = false
	_update_sanity()
	# If we arrived with pending questions (resume or after extraction), render them
	if SessionManager.pending_questions.size() > 0:
		_render_questions()
		status_label.text = "Loaded %d question(s) — edit before you Play." % SessionManager.pending_questions.size()
	_update_play_enabled()

func _update_quota_label() -> void:
	if quota_label == null:
		return
	if MonetizationState.is_premium:
		quota_label.text = "Premium: Unlimited"
	else:
		var pdf_rem: int = MonetizationState.get_remaining("pdf")
		var grade_rem: int = MonetizationState.get_remaining("grade")
		quota_label.text = "Free AI Uses: PDFs %d/%d | Grades %d/%d" % [pdf_rem, MonetizationState.FREE_PDF_LIMIT, grade_rem, MonetizationState.FREE_GRADE_LIMIT]

func _on_premium_changed(_is_premium: bool) -> void:
	_update_quota_label()

func _on_quota_exceeded(type: String) -> void:
	# Only handle pdf quota here; grade quota also triggers dialog but label already covers it.
	_update_quota_label()
	quota_dialog.dialog_text = "Weekly AI limit reached. Upgrade to Premium to continue."
	if type == "grade":
		quota_dialog.dialog_text = "Weekly AI limit reached. Upgrade to Premium to continue."
	quota_dialog.popup_centered()

func _on_pick_file() -> void:
	file_dialog.visible = true

func _on_file_selected(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		status_label.text = "Can't open file: " + path
		return
	_file_bytes = f.get_buffer(f.get_length())
	f.close()
	# Try to read as text for preview/sanity (PDF bytes will look garbled but we still send them)
	var txt := _file_bytes.get_string_from_utf8()
	if txt.length() > 0 and not txt.contains("�"):
		paste_area.text = txt.substr(0, 4000)
	else:
		paste_area.text = "[Binary file loaded: %d bytes — will send as reviewer]" % _file_bytes.size()
	status_label.text = "File loaded: %s (%d bytes)" % [path.get_file(), _file_bytes.size()]
	_update_sanity()

func _on_paste_changed() -> void:
	_update_sanity()

func _update_sanity() -> void:
	var text := paste_area.text
	var v := SessionManager.validate_source_text(text)
	if text.strip_edges() == "":
		sanity_label.text = ""
		sanity_label.visible = false
		return
	sanity_label.visible = true
	if v.get("ok", false):
		var words: int = int(v.get("words", 0))
		sanity_label.text = "✓ %d words — good to study." % words
		sanity_label.modulate = Color(0.6, 1.0, 0.6)
	else:
		sanity_label.text = str(v.get("error", "Too short"))
		sanity_label.modulate = Color(1.0, 0.6, 0.6)

func _on_study() -> void:
	if _studying:
		return
	var topic_name := topic_name_field.text.strip_edges()
	if topic_name == "":
		status_label.text = "Give your topic a name first."
		return
	var source_text := paste_area.text
	# Real file loaded: the bytes are what get sent, so the text gate doesn't apply.
	if _file_bytes.size() == 0:
		var v := SessionManager.validate_source_text(source_text)
		if not v.get("ok", false):
			status_label.text = str(v.get("error", "Too short"))
			return
	_studying = true
	study_btn.disabled = true
	status_label.text = "AI is studying... analyzing your reviewer"
	loading_bar.visible = true
	loading_bar.value = 12
	# Animate loading bar while we wait for mock 0.8s
	var tw := create_tween()
	tw.tween_property(loading_bar, "value", 85.0, 0.7)
	if _file_bytes.size() > 0:
		# Binary PDFs show a "[Binary file loaded...]" stub in the paste box —
		# only forward real reviewer text, else the mock uses placeholders.
		var hint := ""
		if not source_text.begins_with("[Binary file loaded:"):
			var hv := SessionManager.validate_source_text(source_text)
			if hv.get("ok", false):
				hint = source_text
		SessionManager.start_upload(topic_name, _file_bytes, hint)
	else:
		SessionManager.start_upload_from_text(topic_name, source_text)
	_update_quota_label()

func _on_extraction_started(_job_id: String) -> void:
	status_label.text = "AI is studying... extracting concepts"
	loading_bar.visible = true

func _on_extraction_progress(_job_id: String, progress: float) -> void:
	loading_bar.value = 12 + progress * 78

func _on_extraction_completed(_topic_id: String, questions: Array[Dictionary]) -> void:
	_studying = false
	study_btn.disabled = false
	loading_bar.value = 100
	status_label.text = "AI found %d question(s) — review and edit, then Play!" % questions.size()
	_render_questions()
	_update_play_enabled()
	_update_quota_label()
	# Hide bar after a beat
	await get_tree().create_timer(0.6).timeout
	loading_bar.visible = false

func _on_extraction_failed(_job_id: String, error: String) -> void:
	_studying = false
	study_btn.disabled = false
	loading_bar.visible = false
	status_label.text = "Extraction failed: " + error
	_update_quota_label()

func _render_questions() -> void:
	for c in questions_box.get_children():
		c.queue_free()
	var qs := SessionManager.get_pending_questions()
	for i in qs.size():
		var row := _make_question_row(qs[i], i)
		questions_box.add_child(row)

func _make_question_row(q: Dictionary, idx: int) -> Control:
	var conf: float = float(q.get("confidence", 0.7))
	var qtype: String = str(q.get("type", "essay")).to_lower()
	var text: String = str(q.get("text", ""))
	var answer: String = str(q.get("answer", ""))
	var concepts: String = ""
	if q.has("key_concepts") and q["key_concepts"] is Array:
		var parts: Array[String] = []
		for k in q["key_concepts"]:
			parts.append(str(k))
		concepts = ", ".join(parts)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 0)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(0, 0)
	panel.add_child(vbox)
	# Theme spacing via separation not needed — VBox default

	var header := HBoxContainer.new()
	var idx_label := Label.new()
	idx_label.text = "#%d" % (idx + 1)
	idx_label.custom_minimum_size = Vector2(40, 0)
	header.add_child(idx_label)

	var conf_label := Label.new()
	conf_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	conf_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if conf >= 0.85:
		conf_label.text = "✓ AI fairly sure (%.0f%%)" % (conf * 100)
		conf_label.modulate = Color(0.6, 1.0, 0.6)
	elif conf >= 0.6:
		conf_label.text = "○ Check this one (%.0f%%)" % (conf * 100)
		conf_label.modulate = Color(1.0, 0.92, 0.5)
	else:
		conf_label.text = "⚠ Double-check (%.0f%%)" % (conf * 100)
		conf_label.modulate = Color(1.0, 0.6, 0.6)
	header.add_child(conf_label)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.custom_minimum_size = Vector2(48, 32)
	del_btn.pressed.connect(_on_delete_question.bind(idx))
	header.add_child(del_btn)
	vbox.add_child(header)

	var text_edit := TextEdit.new()
	text_edit.text = text
	text_edit.custom_minimum_size = Vector2(0, 64)
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.placeholder_text = "Question prompt"
	text_edit.text_changed.connect(_on_question_text_changed.bind(idx, text_edit))
	vbox.add_child(text_edit)

	var type_row := HBoxContainer.new()
	var type_label := Label.new()
	type_label.text = "Type:"
	type_label.custom_minimum_size = Vector2(50, 0)
	type_row.add_child(type_label)
	var type_opt := OptionButton.new()
	type_opt.add_item("Essay", 0)
	type_opt.add_item("Identification", 1)
	type_opt.selected = 1 if qtype == "identification" else 0
	type_opt.item_selected.connect(_on_type_changed.bind(idx))
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(type_opt)
	vbox.add_child(type_row)

	var ans_field := LineEdit.new()
	ans_field.text = answer
	ans_field.placeholder_text = "Answer / key concepts (comma-separated for Essay)"
	if concepts != "" and answer == "":
		ans_field.text = concepts
		ans_field.placeholder_text = "Key concepts"
	ans_field.text_changed.connect(_on_answer_changed.bind(idx))
	vbox.add_child(ans_field)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	return panel

func _on_question_text_changed(idx: int, edit: TextEdit) -> void:
	SessionManager.update_question(idx, {"text": edit.text})

func _on_type_changed(idx_selected: int, q_idx: int) -> void:
	# OptionButton emits selected index; map back
	var t := "identification" if idx_selected == 1 else "essay"
	SessionManager.update_question(q_idx, {"type": t})

func _on_answer_changed(new_text: String, idx: int) -> void:
	SessionManager.update_question(idx, {"answer": new_text})

func _on_delete_question(idx: int) -> void:
	SessionManager.remove_question(idx)
	_render_questions()
	_update_play_enabled()

func _on_add_question() -> void:
	SessionManager.add_question("New question — tap to edit", "essay", "", [])
	_render_questions()
	_update_play_enabled()
	status_label.text = "Added a blank question — fill it in."

func _update_play_enabled() -> void:
	play_btn.disabled = SessionManager.pending_questions.size() == 0
	if play_btn.disabled:
		play_btn.text = "Add at least 1 question to Play"
	else:
		play_btn.text = "▶ Confirm & Play  (%d Q)" % SessionManager.pending_questions.size()

func _on_play() -> void:
	if SessionManager.pending_questions.size() == 0:
		status_label.text = "Add a question first."
		return
	var topic_name := topic_name_field.text.strip_edges()
	if topic_name == "":
		topic_name = SessionManager.editing_topic_id
	status_label.text = "Saving topic..."
	# Confirm persists to history + emits region_generated; Phase 6 will navigate to overworld
	SessionManager.confirm_topic(topic_name)
	play_btn.disabled = true

func _on_region_generated(topic_id: String, map_data: Dictionary) -> void:
	var gyms: Array = map_data.get("gyms", [])
	status_label.text = "Region ready! %d gym(s): %s — entering overworld..." % [gyms.size(), ", ".join(gyms)]
	GameState.set_active_region(topic_id)
	GameState.current_topic_id = topic_id
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file("res://scenes/overworld/region_map.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/session_list.tscn")
