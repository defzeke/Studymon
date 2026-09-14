extends Node
## SessionManager — Review Session flow (Phase 5+)

@warning_ignore("unused_signal")
signal topics_listed(topics: Array[Dictionary])
@warning_ignore("unused_signal")
signal extraction_started(job_id: String)
signal extraction_progress(job_id: String, progress: float)
signal extraction_completed(topic_id: String, questions: Array[Dictionary])
signal extraction_failed(job_id: String, error: String)
signal topic_saved(topic_id: String)
signal region_generated(topic_id: String, map_data: Dictionary)

var current_topic_id: String = ""
var pending_questions: Array[Dictionary] = []
var editing_topic_id: String = ""

func _ready() -> void:
	Api.job_status.connect(_on_job_status)

func list_topics() -> void:
	Api.mock_get_topics()

func start_upload(topic_name: String, _pdf_bytes: PackedByteArray) -> void:
	Api.mock_upload_pdf(topic_name)

func _on_job_status(job_id: String, status: String, progress: float, result: Variant) -> void:
	match status:
		"processing":
			extraction_progress.emit(job_id, progress)
		"completed":
			if typeof(result) == TYPE_DICTIONARY and result.has("questions"):
				var topic_id := str(result["topic_id"])
				var questions: Array[Dictionary] = []
				for q in result["questions"]:
					questions.append(q)
				pending_questions = questions
				extraction_completed.emit(topic_id, questions)
			else:
				extraction_failed.emit(job_id, "No questions extracted")
		"failed":
			extraction_failed.emit(job_id, str(result))

func set_editing_topic(topic_id: String, questions: Array[Dictionary]) -> void:
	editing_topic_id = topic_id
	pending_questions = questions.duplicate(true)

func add_question(text: String, qtype: String, answer: String = "", key_concepts: Array[String] = []) -> void:
	var id = "q_" + str(pending_questions.size() + 1)
	pending_questions.append({"id": id, "text": text, "type": qtype, "answer": answer, "key_concepts": key_concepts})

func remove_question(index: int) -> void:
	if index >= 0 and index < pending_questions.size():
		pending_questions.remove_at(index)

func update_question(index: int, data: Dictionary) -> void:
	if index >= 0 and index < pending_questions.size():
		pending_questions[index].merge(data)

func confirm_topic() -> void:
	if editing_topic_id != "" and pending_questions.size() > 0:
		Api.save_topic(editing_topic_id, pending_questions)
		topic_saved.emit(editing_topic_id)
		_enter_overworld(editing_topic_id)

func _enter_overworld(topic_id: String) -> void:
	# Placeholder for Phase 6: generate region/map data
	var map_data = {
		"topic_id": topic_id,
		"gyms": [],
		"trainers": [],
	}
	for q in pending_questions:
		if q.type not in map_data.gyms:
			map_data.gyms.append(q.type)
	region_generated.emit(topic_id, map_data)

func get_pending_questions() -> Array[Dictionary]:
	return pending_questions.duplicate(true)
