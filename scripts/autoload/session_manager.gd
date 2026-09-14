extends Node
## SessionManager — Review Session flow (Phase 5) + Overworld progress (Phase 6)
## Client-side: topics → upload → extraction → edit → confirm → region → gyms

@warning_ignore("unused_signal")
signal topics_listed(topics: Array[Dictionary])
@warning_ignore("unused_signal")
signal extraction_started(job_id: String)
signal extraction_progress(job_id: String, progress: float)
signal extraction_completed(topic_id: String, questions: Array[Dictionary])
signal extraction_failed(job_id: String, error: String)
signal topic_saved(topic_id: String)
signal region_generated(topic_id: String, map_data: Dictionary)
signal overworld_progress_changed

# Client-side sanity: flag very short/garbled PDFs before sending to backend
const MIN_WORDS := 20
const MIN_CHARS := 80

var current_topic_id: String = ""
var pending_questions: Array[Dictionary] = []
var editing_topic_id: String = ""
var _topics: Array[Dictionary] = []
var _active_job_id: String = ""
# Phase 6: per-region clear state (mock-persisted in memory)
var _cleared_trainers: Dictionary = {}  # "topic_id:q_idx" -> true
var _cleared_gyms: Dictionary = {}  # "topic_id:gym_type" -> true
var _last_map_data: Dictionary = {}

func _ready() -> void:
	Api.job_status.connect(_on_job_status)

# --- Topics history (mock-persisted in memory until SaveManager handles it) ---

func list_topics() -> void:
	Api.mock_get_topics()

func get_topics_cache() -> Array[Dictionary]:
	return _topics.duplicate(true)

func add_topic_to_history(topic_id: String, name: String, questions: Array[Dictionary]) -> void:
	for i in _topics.size():
		if _topics[i].get("id", "") == topic_id:
			_topics[i] = {"id": topic_id, "name": name, "question_count": questions.size(), "questions": questions.duplicate(true)}
			return
	_topics.append({"id": topic_id, "name": name, "question_count": questions.size(), "questions": questions.duplicate(true)})

# --- Upload & extraction ---

func validate_source_text(text: String) -> Dictionary:
	var word_count := text.split(" ", false).size()
	var char_count := text.strip_edges().length()
	if char_count < MIN_CHARS:
		return {"ok": false, "error": "Too short — add more material (%d/%d chars)." % [char_count, MIN_CHARS]}
	if word_count < MIN_WORDS:
		return {"ok": false, "error": "Too brief — AI needs ~%d words, you have %d." % [MIN_WORDS, word_count]}
	return {"ok": true, "words": word_count, "chars": char_count}

func start_upload(topic_name: String, _pdf_bytes: PackedByteArray) -> void:
	# _pdf_bytes is unused in MOCK — real impl sends base64 to backend
	_active_job_id = "job_001"
	extraction_started.emit(_active_job_id)
	Api.mock_upload_pdf(topic_name)

func start_upload_from_text(topic_name: String, source_text: String) -> void:
	var v := validate_source_text(source_text)
	if not v.get("ok", false):
		extraction_failed.emit("", str(v.get("error", "Invalid input")))
		return
	start_upload(topic_name, source_text.to_utf8_buffer())

func _on_job_status(job_id: String, status: String, progress: float, result: Variant) -> void:
	# Handle topics listing (Api mocks topics via job_status with job_id "topics")
	if job_id == "topics" and status == "completed" and typeof(result) == TYPE_DICTIONARY:
		var topics_arr: Array[Dictionary] = []
		for t in result.get("topics", []):
			if t is Dictionary:
				topics_arr.append(t)
		# Merge mock topics into cache if not present
		for t in topics_arr:
			var found := false
			for existing in _topics:
				if existing.get("id", "") == t.get("id", ""):
					found = true
					break
			if not found:
				_topics.append(t)
		topics_listed.emit(_topics.duplicate(true))
		return
	match status:
		"processing":
			extraction_progress.emit(job_id, progress)
		"completed":
			if typeof(result) == TYPE_DICTIONARY and result.has("questions"):
				var topic_id := str(result["topic_id"])
				var questions: Array[Dictionary] = []
				for q in result["questions"]:
					if q is Dictionary:
						# Normalize type & confidence
						var d: Dictionary = q.duplicate(true)
						if not d.has("confidence"):
							d["confidence"] = 0.7
						if d.has("type"):
							d["type"] = str(d["type"]).to_lower()
						questions.append(d)
				pending_questions = questions
				editing_topic_id = topic_id
				current_topic_id = topic_id
				extraction_completed.emit(topic_id, questions)
			else:
				extraction_failed.emit(job_id, "No questions extracted")
		"failed":
			extraction_failed.emit(job_id, str(result))

func set_editing_topic(topic_id: String, questions: Array[Dictionary]) -> void:
	editing_topic_id = topic_id
	pending_questions = questions.duplicate(true)

func add_question(text: String, qtype: String, answer: String = "", key_concepts: Array[String] = []) -> void:
	var id = "q_" + str(pending_questions.size() + 1) + "_" + str(randi() % 10000)
	pending_questions.append({"id": id, "text": text, "type": qtype.to_lower(), "answer": answer, "key_concepts": key_concepts, "confidence": 0.5})

func remove_question(index: int) -> void:
	if index >= 0 and index < pending_questions.size():
		pending_questions.remove_at(index)

func update_question(index: int, data: Dictionary) -> void:
	if index >= 0 and index < pending_questions.size():
		for k in data.keys():
			pending_questions[index][k] = data[k]

func confirm_topic(topic_name: String = "") -> void:
	if editing_topic_id == "" or pending_questions.size() == 0:
		return
	var name := topic_name if topic_name != "" else editing_topic_id
	add_topic_to_history(editing_topic_id, name, pending_questions)
	Api.save_topic(editing_topic_id, pending_questions)
	topic_saved.emit(editing_topic_id)
	_enter_overworld(editing_topic_id)

func _enter_overworld(topic_id: String) -> void:
	var map_data := build_map_data(topic_id, pending_questions)
	_last_map_data = map_data
	region_generated.emit(topic_id, map_data)

func build_map_data(topic_id: String, questions: Array[Dictionary]) -> Dictionary:
	var gyms: Array = []
	var trainers: Array = []
	for i in questions.size():
		var q: Dictionary = questions[i]
		var t: String = str(q.get("type", "essay")).to_lower()
		if t not in gyms:
			gyms.append(t)
		trainers.append({"q_index": i, "gym": t, "id": str(q.get("id", "q_%d" % i))})
	return {"topic_id": topic_id, "gyms": gyms, "trainers": trainers}

func get_last_map_data() -> Dictionary:
	return _last_map_data.duplicate(true)

func get_pending_questions() -> Array[Dictionary]:
	return pending_questions.duplicate(true)

# --- Phase 6: gym structure + clear-state progress ---

## Groups pending questions by type: [{type, question_indices: [int]}]
func get_gym_structure() -> Array[Dictionary]:
	var order: Array = []
	var buckets: Dictionary = {}
	for i in pending_questions.size():
		var t: String = str(pending_questions[i].get("type", "essay")).to_lower()
		if not buckets.has(t):
			buckets[t] = []
			order.append(t)
		buckets[t].append(i)
	var out: Array[Dictionary] = []
	for t in order:
		out.append({"type": t, "question_indices": buckets[t]})
	return out

func _trainer_key(topic_id: String, q_idx: int) -> String:
	return "%s:%d" % [topic_id, q_idx]

func is_trainer_cleared(topic_id: String, q_idx: int) -> bool:
	return _cleared_trainers.has(_trainer_key(topic_id, q_idx))

func mark_trainer_cleared(topic_id: String, q_idx: int) -> void:
	_cleared_trainers[_trainer_key(topic_id, q_idx)] = true
	_recheck_gym_clear(topic_id)
	overworld_progress_changed.emit()

func is_gym_cleared(topic_id: String, gym_type: String) -> bool:
	return _cleared_gyms.has("%s:%s" % [topic_id, gym_type])

func mark_gym_cleared(topic_id: String, gym_type: String) -> void:
	_cleared_gyms["%s:%s" % [topic_id, gym_type]] = true
	overworld_progress_changed.emit()

func _recheck_gym_clear(topic_id: String) -> void:
	for gym in get_gym_structure():
		var t: String = str(gym["type"])
		var all_done := true
		for qi in gym["question_indices"]:
			if not is_trainer_cleared(topic_id, int(qi)):
				all_done = false
				break
		if all_done:
			_cleared_gyms["%s:%s" % [topic_id, t]] = true
	overworld_progress_changed.emit()

func get_progress(topic_id: String) -> Dictionary:
	var total := pending_questions.size()
	var done := 0
	for i in pending_questions.size():
		if is_trainer_cleared(topic_id, i):
			done += 1
	var gyms := get_gym_structure()
	var gyms_done := 0
	for g in gyms:
		if is_gym_cleared(topic_id, str(g["type"])):
			gyms_done += 1
	return {"cleared": done, "total": total, "gyms_cleared": gyms_done, "gyms_total": gyms.size()}

func reset_progress(topic_id: String) -> void:
	for k in _cleared_trainers.keys():
		if str(k).begins_with(topic_id + ":"):
			_cleared_trainers.erase(k)
	for k in _cleared_gyms.keys():
		if str(k).begins_with(topic_id + ":"):
			_cleared_gyms.erase(k)
	overworld_progress_changed.emit()
