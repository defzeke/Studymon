extends Node
## Api — HTTP wrapper for backend calls (canonical registered version).
## MOCK mode (default) returns canned data so client dev is never blocked.
## Godot only ever talks to OUR api, never api.anthropic.com directly.
## NOTE: internal helpers are named _http_get/_post/_put — plain `_get`
## would collide with Object's `_get(StringName)` virtual.

signal request_failed(endpoint: String, error: String)
signal job_status(job_id: String, status: String, progress: float, result: Variant)

const MOCK := true
const BASE_URL := "http://localhost:8000"

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func _on_request_completed(result: int, _response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("", "connection failed")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		request_failed.emit("", "JSON parse error")
		return
	var data: Dictionary = parsed
	if data.has("job_id"):
		var jid := str(data["job_id"])
		var status := str(data.get("status", ""))
		var progress := float(data.get("progress", 0.0))
		job_status.emit(jid, status, progress, data.get("result", null))

## Generic mock POST (Phase 0 contract; used by Phase 7 battle grading).
func post_json(path: String, _body: Dictionary) -> Dictionary:
	if MOCK:
		return _mock_post(path)
	push_warning("Api: live mode not implemented yet (Phase 5).")
	return {"ok": false, "error": "live mode not implemented"}

func _mock_post(path: String) -> Dictionary:
	match path:
		"/extract":
			return {"ok": true, "job": "mock-job-1", "questions": [
				{"prompt": "Mock: what is training data?", "type": "Identification"},
				{"prompt": "Mock: explain feedback in your own words.", "type": "Essay"},
			]}
		"/grade":
			return {"ok": true, "score_0_1": 0.7, "feedback": "Mock grade: decent coverage."}
	return {"ok": true}

## Auth (Phase 1)
func login(email: String, password: String) -> void:
	_post("/auth/login", {"email": email, "password": password})

func signup(email: String, password: String) -> void:
	_post("/auth/signup", {"email": email, "password": password})

## Companion (Phase 2)
func get_companion() -> void:
	_http_get("/companion")

## Topics / PDF ingestion (Phase 5)
func upload_pdf(topic_name: String, pdf_bytes: PackedByteArray) -> void:
	_post("/topics/upload", {"topic_name": topic_name, "pdf_base64": Marshalls.raw_to_base64(pdf_bytes)})

func poll_extraction(job_id: String) -> void:
	_http_get("/topics/extract/" + job_id)

func get_topics() -> void:
	_http_get("/topics")

func save_topic(topic_id: String, questions: Array[Dictionary]) -> void:
	_put("/topics/" + topic_id, {"questions": questions})

## Battle grading (Phase 7)
func grade_answer(question_type: String, question: String, answer: String, source_context: String) -> void:
	_post("/battle/grade", {"type": question_type, "question": question, "answer": answer, "source": source_context})

## Mastery (Phase 8)
func get_mastery(topic_id: String) -> void:
	_http_get("/mastery/" + topic_id)

func update_mastery(topic_id: String, question_id: String, state: String) -> void:
	_put("/mastery/" + topic_id + "/" + question_id, {"state": state})

## Internal
func _auth_headers() -> Array:
	var headers: Array = []
	if GameState.auth_token != "":
		headers.append("Authorization: Bearer " + GameState.auth_token)
	return headers

func _post(endpoint: String, data: Dictionary) -> void:
	var headers: Array = ["Content-Type: application/json"]
	headers.append_array(_auth_headers())
	_http.request(BASE_URL + endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(data))

func _http_get(endpoint: String) -> void:
	_http.request(BASE_URL + endpoint, _auth_headers(), HTTPClient.METHOD_GET)

func _put(endpoint: String, data: Dictionary) -> void:
	var headers: Array = ["Content-Type: application/json"]
	headers.append_array(_auth_headers())
	_http.request(BASE_URL + endpoint, headers, HTTPClient.METHOD_PUT, JSON.stringify(data))

## MOCKS — replaced by real calls when backend lands (Phase 5+)
func mock_login(_email: String, _password: String) -> void:
	call_deferred("_mock_login_done", {"user_id": "user_123", "token": "mock_token_abc"})

func _mock_login_done(data: Dictionary) -> void:
	GameState.set_user(str(data["user_id"]), str(data["token"]))

func mock_get_companion() -> void:
	call_deferred("_mock_companion_done", {
		"level": 1,
		"xp": 0,
		"energy": 80.0,
		"focus": 70.0,
		"mood": 75.0,
		"bond": 0,
		"codex": ["I start out knowing NOTHING — like a baby! I need training to learn. (AI starts blank)"],
	})

func _mock_companion_done(data: Dictionary) -> void:
	if has_node("/root/CompanionState"):
		get_node("/root/CompanionState").from_dict(data)

func mock_upload_pdf(_topic_name: String) -> void:
	call_deferred("_mock_upload_done", {"job_id": "job_001", "status": "processing"})

func _mock_upload_done(data: Dictionary) -> void:
	job_status.emit(str(data["job_id"]), str(data["status"]), 0.0, null)

func mock_poll_extraction(job_id: String) -> void:
	call_deferred("_mock_poll_done", {
		"job_id": job_id,
		"status": "completed",
		"progress": 1.0,
		"result": {
			"topic_id": "topic_001",
			"questions": [
				{"id": "q1", "text": "What is the capital of France?", "type": "identification", "answer": "Paris"},
				{"id": "q2", "text": "Explain photosynthesis.", "type": "essay", "key_concepts": ["chlorophyll", "light", "CO2", "glucose"]},
			],
		},
	})

func _mock_poll_done(data: Dictionary) -> void:
	job_status.emit(str(data["job_id"]), str(data["status"]), float(data["progress"]), data["result"])

func mock_grade_answer(question_type: String, _question: String, answer: String, _source_context: String) -> void:
	var score := 0.5
	if question_type == "identification":
		score = 1.0 if answer.to_lower().strip_edges() == "paris" else 0.0
	else:
		var hits := 0
		for kw in ["chlorophyll", "light", "co2", "glucose"]:
			if answer.to_lower().contains(kw):
				hits += 1
		score = hits / 4.0
	call_deferred("_mock_grade_done", {"score": score, "feedback": "Mock grading — " + str(score * 100) + "%"})

func _mock_grade_done(data: Dictionary) -> void:
	job_status.emit("grade", "completed", 1.0, data)

func mock_get_topics() -> void:
	call_deferred("_mock_topics_done", {"topics": [{"id": "topic_001", "name": "Biology 101", "question_count": 2}]})

func _mock_topics_done(data: Dictionary) -> void:
	job_status.emit("topics", "completed", 1.0, data)
