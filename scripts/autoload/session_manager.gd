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
## Phase 5: raw reviewer text from the last upload (paste or decoded file bytes).
## Stored so the mock extractor can parse USER material instead of canned defaults.
## Per-topic copies persist in _source_by_topic after confirm.
var last_source_text: String = ""
var _source_by_topic: Dictionary = {}
var _topics: Array[Dictionary] = []
var _active_job_id: String = ""
# Phase 6: per-region clear state (mock-persisted in memory)
var _cleared_trainers: Dictionary = {}  # "topic_id:q_idx" -> true
var _cleared_gyms: Dictionary = {}  # "topic_id:gym_type" -> true
var _last_map_data: Dictionary = {}
# Phase 7: battle context (survives the overworld -> battle scene change)
var battle_topic_id: String = ""
var battle_q_index: int = -1
var battle_is_boss: bool = false

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

func start_upload(topic_name: String, pdf_bytes: PackedByteArray, source_hint: String = "") -> void:
	# Wire reviewer input through to the extractor. Precedence: explicit hint
	# (paste box) > decodable bytes > previous last_source_text. Binary PDFs
	# won't decode cleanly — then the mock falls back to editable placeholders.
	var hint := source_hint.strip_edges()
	if hint != "":
		last_source_text = source_hint
	elif pdf_bytes.size() > 0:
		var decoded := pdf_bytes.get_string_from_utf8()
		if decoded.length() > 0 and not decoded.contains("�"):
			last_source_text = decoded
		else:
			last_source_text = ""
	_active_job_id = "job_001"
	extraction_started.emit(_active_job_id)
	Api.mock_upload_pdf(topic_name, last_source_text)

func start_upload_from_text(topic_name: String, source_text: String) -> void:
	var v := validate_source_text(source_text)
	if not v.get("ok", false):
		extraction_failed.emit("", str(v.get("error", "Invalid input")))
		return
	last_source_text = source_text
	start_upload(topic_name, source_text.to_utf8_buffer())

## Raw reviewer text for a topic ("" if none stored).
func get_source_text(topic_id: String) -> String:
	if _source_by_topic.has(topic_id):
		return str(_source_by_topic[topic_id])
	if topic_id == editing_topic_id or topic_id == current_topic_id:
		return last_source_text
	return ""

func _on_job_status(job_id: String, status: String, progress: float, result: Variant) -> void:
	# Grade jobs belong to the battle scene (Api._mock_grade_done) — not extraction.
	if job_id == "grade":
		return
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
	if last_source_text.strip_edges() != "":
		_source_by_topic[editing_topic_id] = last_source_text
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
	for k in _mastery.keys():
		if str(k).begins_with(topic_id + ":"):
			_mastery.erase(k)
	_champion_defeated.erase(topic_id)
	overworld_progress_changed.emit()
	mastery_changed.emit()

# --- Phase 7: battle handoff ---

## Called by the overworld encounter panel. Boss = final question of a gym.
func begin_battle(topic_id: String, q_idx: int, is_boss: bool = false) -> void:
	battle_topic_id = topic_id
	battle_q_index = q_idx
	battle_is_boss = is_boss

## The bound question for the active battle ({} if none).
func get_battle_question() -> Dictionary:
	if battle_q_index < 0 or battle_q_index >= pending_questions.size():
		return {}
	return (pending_questions[battle_q_index] as Dictionary).duplicate(true)

## Called by the battle scene on victory. Marks trainer cleared (+ gym badge for bosses).
## Phase 8: every result (win AND loss) also feeds the mastery tracker.
func report_battle_result(won: bool) -> void:
	if battle_topic_id == "" or battle_q_index < 0:
		return
	record_battle_outcome(battle_topic_id, battle_q_index, won)
	if not won:
		return
	mark_trainer_cleared(battle_topic_id, battle_q_index)
	if battle_is_boss and battle_q_index >= 0 and battle_q_index < pending_questions.size():
		var gym_type: String = str(pending_questions[battle_q_index].get("type", "essay")).to_lower()
		mark_gym_cleared(battle_topic_id, gym_type)

# --- Phase 8: mastery states ---
# Per-question mastery: New -> Learning -> Remaster -> Mastered.
# Updated after EVERY battle result; Mastered decays to Remaster after
# MASTERY_DECAY_DAYS without a correct re-encounter (spaced repetition).

enum Mastery { NEW, LEARNING, REMASTER, MASTERED }
const MASTERY_DECAY_DAYS := 7
const MASTERY_NAMES: Array[String] = ["new", "learning", "remaster", "mastered"]

signal mastery_changed
signal champion_defeated(topic_id: String)

var _mastery: Dictionary = {}
var _champion_defeated: Dictionary = {}

func _mastery_key(topic_id: String, q_idx: int) -> String:
	return "%s:%d" % [topic_id, q_idx]

func get_mastery_state(topic_id: String, q_idx: int) -> int:
	var k := _mastery_key(topic_id, q_idx)
	if not _mastery.has(k):
		return Mastery.NEW
	var rec: Dictionary = _mastery[k]
	var st: int = int(rec.get("state", Mastery.NEW))
	if st == Mastery.MASTERED:
		var age := int(Time.get_unix_time_from_system()) - int(rec.get("last_correct", 0))
		if age > MASTERY_DECAY_DAYS * 86400:
			st = Mastery.REMASTER
			rec["state"] = st
			_mastery[k] = rec
			mastery_changed.emit()
	return st

func mastery_badge(state: int) -> Dictionary:
	match state:
		Mastery.LEARNING:
			return {"emoji": "🟡", "color": Color(1.0, 0.85, 0.3), "name": "Learning"}
		Mastery.REMASTER:
			return {"emoji": "🟠", "color": Color(1.0, 0.6, 0.25), "name": "Remaster"}
		Mastery.MASTERED:
			return {"emoji": "🟢", "color": Color(0.45, 0.95, 0.5), "name": "Mastered"}
	return {"emoji": "⚪", "color": Color(0.75, 0.75, 0.8), "name": "New"}

func record_battle_outcome(topic_id: String, q_idx: int, won: bool) -> void:
	var k := _mastery_key(topic_id, q_idx)
	var rec: Dictionary = _mastery.get(k, {"state": Mastery.NEW, "attempts": 0, "correct": 0, "last_correct": 0})
	var st: int = int(rec.get("state", Mastery.NEW))
	rec["attempts"] = int(rec.get("attempts", 0)) + 1
	if won:
		rec["correct"] = int(rec.get("correct", 0)) + 1
		rec["last_correct"] = int(Time.get_unix_time_from_system())
		match st:
			Mastery.NEW:
				st = Mastery.LEARNING
			Mastery.LEARNING, Mastery.REMASTER:
				st = Mastery.MASTERED
	else:
		match st:
			Mastery.MASTERED:
				st = Mastery.REMASTER
			Mastery.REMASTER:
				st = Mastery.LEARNING
	rec["state"] = st
	_mastery[k] = rec
	if not Api.MOCK:
		var qs := _questions_for(topic_id)
		var qid := "q_%d" % q_idx
		if q_idx >= 0 and q_idx < qs.size():
			qid = str((qs[q_idx] as Dictionary).get("id", qid))
		Api.update_mastery(topic_id, qid, MASTERY_NAMES[st])
	mastery_changed.emit()

func _questions_for(topic_id: String) -> Array:
	if topic_id == editing_topic_id or topic_id == current_topic_id:
		return pending_questions
	for t in _topics:
		if str(t.get("id", "")) == topic_id:
			return t.get("questions", [])
	return []

# --- Phase 8: Champion battle ---
# Moveset = all current Mastered questions; falls back to every question
# so the fight stays playable even with zero mastered.

var battle_is_champion: bool = false
var battle_champion_queue: Array = []
var battle_champion_index: int = 0

func champion_moveset(topic_id: String) -> Array:
	var qs: Array = _questions_for(topic_id)
	var mastered: Array = []
	for i in qs.size():
		if get_mastery_state(topic_id, i) == Mastery.MASTERED:
			mastered.append(i)
	return mastered

func is_champion_available(topic_id: String) -> bool:
	var gyms := get_gym_structure()
	if gyms.is_empty():
		return false
	for g in gyms:
		if not is_gym_cleared(topic_id, str(g["type"])):
			return false
	return true

func is_champion_defeated(topic_id: String) -> bool:
	return _champion_defeated.has(topic_id)

func is_region_complete(topic_id: String) -> bool:
	return is_champion_defeated(topic_id)

func begin_champion_battle(topic_id: String) -> bool:
	if not is_champion_available(topic_id):
		return false
	var moveset := champion_moveset(topic_id)
	if moveset.is_empty():
		return false
	battle_is_champion = true
	battle_champion_queue = []
	for n in moveset.size():
		battle_champion_queue.append({
			"topic_id": topic_id,
			"q_idx": int(moveset[n]),
			"boss": n == moveset.size() - 1,
		})
	battle_champion_index = 0
	_apply_champion_active()
	return true

func _apply_champion_active() -> void:
	var step: Dictionary = battle_champion_queue[battle_champion_index]
	battle_topic_id = str(step["topic_id"])
	battle_q_index = int(step["q_idx"])
	battle_is_boss = bool(step["boss"])

func advance_champion() -> bool:
	if not battle_is_champion:
		return false
	battle_champion_index += 1
	if battle_champion_index < battle_champion_queue.size():
		_apply_champion_active()
		return true
	battle_is_champion = false
	_champion_defeated[battle_topic_id] = true
	champion_defeated.emit(battle_topic_id)
	overworld_progress_changed.emit()
	return false

func champion_progress() -> Dictionary:
	return {"done": battle_champion_index, "total": battle_champion_queue.size()}

func to_dict() -> Dictionary:
	return {
		"mastery": _mastery.duplicate(true),
		"cleared_trainers": _cleared_trainers.keys(),
		"cleared_gyms": _cleared_gyms.keys(),
		"champion_defeated": _champion_defeated.keys(),
		"topics": _topics.duplicate(true),
	}

func from_dict(data: Dictionary) -> void:
	_mastery = (data.get("mastery", {}) as Dictionary).duplicate(true)
	_cleared_trainers = {}
	for k in data.get("cleared_trainers", []):
		_cleared_trainers[str(k)] = true
	_cleared_gyms = {}
	for k in data.get("cleared_gyms", []):
		_cleared_gyms[str(k)] = true
	_champion_defeated = {}
	for k in data.get("champion_defeated", []):
		_champion_defeated[str(k)] = true
	_topics = []
	for t in data.get("topics", []):
		if t is Dictionary:
			_topics.append((t as Dictionary).duplicate(true))
	overworld_progress_changed.emit()
	mastery_changed.emit()
