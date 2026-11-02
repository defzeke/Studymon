extends Control
## Phase 5: Categorizer — Upload → AI is studying... → editable question list → Confirm → Play
## Implements build-plan P5: word-count sanity, confidence badges, CRUD list, region generation.

# Order matches %RowTemplate's TypeOption items; contract: docs/systems/gameplay-structure.md.
const QUESTION_TYPES: Array[String] = ["essay", "identification", "multiple_choice"]
const ConfirmModal := preload("res://scripts/ui/widgets/confirm_modal.gd")
# Reviewer files the study server reads (extension -> its type) and its size caps (backend/main.py).
const FILE_TYPES := {"pdf": "pdf", "png": "png", "jpg": "jpeg", "jpeg": "jpeg", "webp": "webp", "docx": "docx", "pptx": "pptx"}
const MAX_FILE_BYTES := 20 * 1024 * 1024
const MAX_IMAGE_BYTES := 5 * 1024 * 1024

@onready var topic_name_field: LineEdit = %TopicName
@onready var file_btn: Button = %FileButton
@onready var paste_area: TextEdit = %PasteArea
@onready var study_btn: Button = %StudyButton
@onready var more_btn: Button = %MoreButton
@onready var status_label: Label = %StatusLabel
@onready var loading_bar: ProgressBar = %LoadingBar
@onready var sanity_label: Label = %SanityLabel
@onready var questions_box: VBoxContainer = %QuestionsBox
@onready var row_template: PanelContainer = %RowTemplate
@onready var add_q_btn: Button = %AddQuestionButton
@onready var play_btn: Button = %PlayButton
@onready var back_btn: Button = %BackButton
@onready var file_dialog: FileDialog = %FileDialog

var _studying: bool = false
# Questions before "More questions" ran, to report how many it added; -1 for a normal upload.
var _count_before := -1
## A picked reviewer file (PDF, photo, Word, PowerPoint), sent as it is to the study server; empty
## when the reviewer is text.
var _file := PackedByteArray()
var _file_type := ""

func _ready() -> void:
	theme = load("res://assets/theme/app_theme.tres") as Theme
	var saved_name := SessionManager.world_name(SessionManager.editing_topic_id)
	topic_name_field.text = saved_name if saved_name != "" else "My New World"
	file_btn.pressed.connect(_on_pick_file)
	file_dialog.file_selected.connect(_on_file_selected)
	study_btn.pressed.connect(_on_study)
	more_btn.pressed.connect(_on_more)
	add_q_btn.pressed.connect(_on_add_question)
	play_btn.pressed.connect(_on_play)
	back_btn.pressed.connect(_on_back)
	paste_area.text_changed.connect(_on_paste_changed)
	SessionManager.extraction_started.connect(_on_extraction_started)
	SessionManager.extraction_progress.connect(_on_extraction_progress)
	SessionManager.extraction_completed.connect(_on_extraction_completed)
	SessionManager.extraction_failed.connect(_on_extraction_failed)
	SessionManager.region_generated.connect(_on_region_generated)
	loading_bar.visible = false
	_update_sanity()
	# If we arrived with pending questions (resume or after extraction), render them
	if SessionManager.pending_questions.size() > 0:
		_render_questions()
		status_label.text = "Loaded %d question(s) — edit before you Play." % SessionManager.pending_questions.size()
	_update_play_enabled()
	_refresh_more()

# "More questions" shows for a saved world that kept its reviewer text.
func _refresh_more() -> void:
	more_btn.visible = SessionManager.is_saved_world(SessionManager.editing_topic_id) and SessionManager.last_source_text.strip_edges() != ""

func _on_pick_file() -> void:
	file_dialog.popup_centered(Vector2i(640, 760))

func _on_file_selected(path: String) -> void:
	file_btn.text = path.get_file()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		status_label.text = "Can't open file: " + path
		return
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var txt := bytes.get_string_from_utf8()
	if txt.length() == 0 or txt.contains("�"):
		var kind: String = FILE_TYPES.get(path.get_extension().to_lower(), "")
		var cap := MAX_IMAGE_BYTES if kind in ["png", "jpeg", "webp"] else MAX_FILE_BYTES
		if Api.MOCK or kind == "":
			status_label.text = "Can't read this file as text. Use a PDF, photo, Word or PowerPoint file, or paste the text."
		elif bytes.size() > cap:
			status_label.text = "That file is over %d MB. Use a smaller one or paste the text instead." % (cap >> 20)
		else:
			paste_area.text = ""
			_file = bytes
			_file_type = kind
			status_label.text = "File ready: %s. Press Study to let the AI read it." % path.get_file()
			sanity_label.visible = false
		return
	_file = PackedByteArray()
	paste_area.text = txt
	status_label.text = "File loaded: %s (%d bytes)" % [path.get_file(), bytes.size()]
	_update_sanity()

func _on_paste_changed() -> void:
	if paste_area.text.strip_edges() != "":
		_file = PackedByteArray()
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
		status_label.text = "Give your world a name first."
		return
	var source_text := paste_area.text
	var v := SessionManager.validate_source_text(source_text)
	if _file.is_empty() and not v.get("ok", false):
		status_label.text = str(v.get("error", "Too short"))
		return
	if not GameState.ai_consent:
		ConfirmModal.open(self, "Before the AI reads your notes", GameState.AI_CONSENT_TEXT, "I agree", _on_consent, false, "Not now")
		return
	_studying = true
	study_btn.disabled = true
	status_label.text = "AI is studying... analyzing your reviewer"
	loading_bar.visible = true
	loading_bar.value = 12
	# Animate loading bar while we wait for mock 0.8s
	var tw := create_tween()
	tw.tween_property(loading_bar, "value", 85.0, 0.7)
	if _file.is_empty():
		SessionManager.start_upload_from_text(topic_name, source_text)
	else:
		SessionManager.start_upload(topic_name, _file, "", _file_type)

func _on_consent() -> void:
	GameState.ai_consent = true
	SaveManager.save_progress()
	_on_study()

func _on_consent_more() -> void:
	GameState.ai_consent = true
	SaveManager.save_progress()
	_on_more()

# New questions from the world's saved reviewer, added to the ones it has (a saved world only).
func _on_more() -> void:
	if _studying:
		return
	if not GameState.ai_consent:
		ConfirmModal.open(self, "Before the AI reads your notes", GameState.AI_CONSENT_TEXT, "I agree", _on_consent_more, false, "Not now")
		return
	_count_before = SessionManager.pending_questions.size()
	if not SessionManager.start_more_questions(topic_name_field.text.strip_edges()):
		_count_before = -1
		status_label.text = "This world has no saved reviewer text, so the AI has nothing new to read."
		return
	_studying = true
	study_btn.disabled = true
	more_btn.disabled = true
	status_label.text = "AI is reading your reviewer again for new questions..."
	loading_bar.visible = true
	loading_bar.value = 12

func _on_extraction_started(_job_id: String) -> void:
	status_label.text = "AI is studying... extracting concepts"
	loading_bar.visible = true

func _on_extraction_progress(_job_id: String, progress: float) -> void:
	loading_bar.value = 12 + progress * 78

func _on_extraction_completed(_topic_id: String, questions: Array[Dictionary]) -> void:
	_studying = false
	study_btn.disabled = false
	more_btn.disabled = false
	loading_bar.value = 100
	status_label.text = "AI found %d question(s) — review and edit, then Play!" % questions.size()
	if _count_before >= 0:
		status_label.text = "Added %d new question(s). Review them, then Play!" % (questions.size() - _count_before)
		_count_before = -1
	_refresh_more()
	_render_questions()
	_update_play_enabled()
	# Hide bar after a beat
	await get_tree().create_timer(0.6).timeout
	loading_bar.visible = false

func _on_extraction_failed(_job_id: String, error: String) -> void:
	_studying = false
	_count_before = -1
	study_btn.disabled = false
	more_btn.disabled = false
	loading_bar.visible = false
	status_label.text = "Extraction failed: " + error

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

	# The row's layout and look are %RowTemplate's; this fills one copy and wires it to the question.
	var panel := row_template.duplicate() as PanelContainer
	panel.visible = true
	var box := panel.get_node("Pad/Box")
	(box.get_node("Header/Index") as Label).text = "#%d" % (idx + 1)

	var conf_label := box.get_node("Header/Confidence") as Label
	if conf >= 0.85:
		conf_label.text = "AI is fairly sure (%.0f%%)" % (conf * 100)
		conf_label.modulate = Color("78A982")
	elif conf >= 0.6:
		conf_label.text = "Check this one (%.0f%%)" % (conf * 100)
		conf_label.modulate = Color("D6A85F")
	else:
		conf_label.text = "Double-check (%.0f%%)" % (conf * 100)
		conf_label.modulate = Color("C97970")

	(box.get_node("Header/Delete") as Button).pressed.connect(_on_delete_question.bind(idx))
	(box.get_node("Header/Report") as Button).pressed.connect(_on_report_question.bind(idx))

	var text_edit := box.get_node("Prompt") as TextEdit
	text_edit.text = text
	text_edit.text_changed.connect(_on_question_text_changed.bind(idx, text_edit))

	var type_opt := box.get_node("TypeRow/TypeOption") as OptionButton
	type_opt.selected = maxi(0, QUESTION_TYPES.find(qtype))
	type_opt.item_selected.connect(_on_type_changed.bind(idx))
	var diff_opt := box.get_node("TypeRow/Difficulty") as OptionButton
	for tier in SessionManager.DIFFICULTIES:
		diff_opt.add_item(tier.capitalize())
	diff_opt.selected = maxi(0, SessionManager.DIFFICULTIES.find(str(q.get("difficulty", "medium"))))
	diff_opt.item_selected.connect(_on_difficulty_changed.bind(idx))

	var ans_field := box.get_node("Answer") as LineEdit
	ans_field.text = answer
	if concepts != "" and answer == "":
		ans_field.text = concepts
		ans_field.placeholder_text = "Key concepts"
	ans_field.text_changed.connect(_on_answer_changed.bind(idx))
	if qtype == "identification":
		var also := box.get_node("Accepted") as LineEdit
		also.visible = true
		also.text = ", ".join(PackedStringArray(Array(q.get("accepted", [])).map(func(a: Variant) -> String: return str(a))))
		also.text_changed.connect(_on_accepted_changed.bind(idx))
	if qtype == "multiple_choice":
		ans_field.placeholder_text = "Correct option"
		var wrong: Array = q.get("distractors", [])
		for n in 3:
			var wrong_field := box.get_node("Wrong%d" % (n + 1)) as LineEdit
			wrong_field.visible = true
			wrong_field.text = str(wrong[n]) if n < wrong.size() else ""
			wrong_field.text_changed.connect(_on_distractor_changed.bind(idx, n))

	return panel

func _on_question_text_changed(idx: int, edit: TextEdit) -> void:
	SessionManager.update_question(idx, {"text": edit.text})

func _on_type_changed(idx_selected: int, q_idx: int) -> void:
	SessionManager.update_question(q_idx, {"type": QUESTION_TYPES[idx_selected]})
	_render_questions()

func _on_difficulty_changed(idx_selected: int, q_idx: int) -> void:
	SessionManager.update_question(q_idx, {"difficulty": SessionManager.DIFFICULTIES[idx_selected]})

func _on_distractor_changed(new_text: String, q_idx: int, n: int) -> void:
	var wrong: Array = SessionManager.get_pending_questions()[q_idx].get("distractors", [])
	while wrong.size() < 3:
		wrong.append("")
	wrong[n] = new_text
	SessionManager.update_question(q_idx, {"distractors": wrong})

func _on_answer_changed(new_text: String, idx: int) -> void:
	SessionManager.update_question(idx, {"answer": new_text})

func _on_accepted_changed(new_text: String, idx: int) -> void:
	var accepted: Array = []
	for a in new_text.split(",", false):
		if a.strip_edges() != "":
			accepted.append(a.strip_edges())
	SessionManager.update_question(idx, {"accepted": accepted})

func _on_delete_question(idx: int) -> void:
	SessionManager.remove_question(idx)
	_render_questions()
	_update_play_enabled()

# Flags an AI-written question as wrong or offensive (Google Play's AI-content rule); the player can
# still delete or fix it here.
func _on_report_question(idx: int) -> void:
	ConfirmModal.open(self, "Report this question?", "Send it to the Studymon team as wrong or offensive. You can also fix or delete it here.", "Report", _send_report.bind(idx), true)

func _send_report(idx: int) -> void:
	var q: Dictionary = SessionManager.get_pending_questions()[idx]
	Api.report_content(Api.new_job_id("report"), "question", "%s
Answer: %s" % [q.get("text", ""), q.get("answer", "")])
	status_label.text = "Thanks: question #%d was reported." % (idx + 1)

func _on_add_question() -> void:
	SessionManager.add_question("New question — tap to edit", "essay", "", [])
	_render_questions()
	_update_play_enabled()
	status_label.text = "Added a blank question — fill it in."

func _update_play_enabled() -> void:
	play_btn.disabled = SessionManager.pending_questions.size() == 0
	if play_btn.disabled:
		play_btn.text = "Add a question to play"
	else:
		play_btn.text = "Confirm & Play  (%d Q)" % SessionManager.pending_questions.size()

func _on_play() -> void:
	if SessionManager.pending_questions.size() == 0:
		status_label.text = "Add a question first."
		return
	var topic_name := topic_name_field.text.strip_edges()
	if topic_name == "":
		topic_name = SessionManager.editing_topic_id
	if not SessionManager.is_saved_world(SessionManager.editing_topic_id) and not SessionManager.has_free_world_slot():
		status_label.text = "All %d world slots are full. Delete a world or buy a slot on the worlds list." % GameState.world_slots
		return
	status_label.text = "Saving world..."
	# Confirm persists to history + emits region_generated; Phase 6 will navigate to overworld
	SessionManager.confirm_topic(topic_name)
	play_btn.disabled = true

func _on_region_generated(topic_id: String, map_data: Dictionary) -> void:
	var gyms: Array = map_data.get("gyms", [])
	status_label.text = "Region ready! %d gym(s): %s — entering overworld..." % [gyms.size(), ", ".join(gyms)]
	GameState.set_active_region(topic_id)
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file("res://scenes/overworld/region_map.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/session_list.tscn")
