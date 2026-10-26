extends Node
## Api — HTTP wrapper for backend calls (canonical registered version).
## MOCK mode (default) returns canned data so client dev is never blocked.
## Godot only ever talks to OUR api, never api.anthropic.com directly.
## NOTE: internal helpers are named _http_get/_post/_put — plain `_get`
## would collide with Object's `_get(StringName)` virtual.

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
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	if data.has("job_id"):
		var jid := str(data["job_id"])
		var status := str(data.get("status", ""))
		var progress := float(data.get("progress", 0.0))
		job_status.emit(jid, status, progress, data.get("result", null))

func save_topic(topic_id: String, questions: Array[Dictionary]) -> void:
	_put("/topics/" + topic_id, {"questions": questions})

## Canonical Phase 7 entry: grade a full question dict (carries expected answer + key_concepts).
func grade_battle_question(q: Dictionary, answer: String) -> void:
	if MOCK:
		_execute_mock_grade(q, answer)
		return
	_post("/battle/grade", {
		"type": str(q.get("type", "essay")),
		"question": str(q.get("text", "")),
		"answer": answer,
		"source": str(q.get("source", "")),
		"expected": str(q.get("answer", "")),
		"key_concepts": q.get("key_concepts", []),
	})

func update_mastery(topic_id: String, question_id: String, state: String) -> void:
	_put("/mastery/" + topic_id + "/" + question_id, {"state": state})

## Internal
func _auth_headers() -> Array:
	var headers: Array = []
	if GameState.auth_token != "":
		headers.append("Authorization: *** " + GameState.auth_token)
	return headers

func _post(endpoint: String, data: Dictionary) -> void:
	var headers: Array = ["Content-Type: application/json"]
	headers.append_array(_auth_headers())
	_http.request(BASE_URL + endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(data))



func _put(endpoint: String, data: Dictionary) -> void:
	var headers: Array = ["Content-Type: application/json"]
	headers.append_array(_auth_headers())
	_http.request(BASE_URL + endpoint, headers, HTTPClient.METHOD_PUT, JSON.stringify(data))

## MOCKS — replaced by real calls when backend lands (Phase 5+)

func mock_upload_pdf(topic_name: String, source_text: String = "") -> void:
	_execute_mock_upload(topic_name, source_text)

func _execute_mock_upload(topic_name: String, source_text: String) -> void:
	# Simulate short processing beat like GDD §5.2 "AI is studying..."
	call_deferred("_mock_upload_done", {"job_id": "job_001", "status": "processing"})
	# Complete after ~0.8s via timer if tree is ready, else immediate.
	# Questions are parsed from the USER's reviewer text; canned placeholders
	# only apply when no usable text survived (e.g. binary PDF bytes).
	var questions := _build_questions_from_text(topic_name, source_text)
	var topic_id := _slug_topic_id(topic_name)
	var payload := {
		"job_id": "job_001",
		"status": "completed",
		"progress": 1.0,
		"result": {"topic_id": topic_id, "questions": questions},
	}
	if is_inside_tree():
		var t := Timer.new()
		t.wait_time = 0.8
		t.one_shot = true
		add_child(t)
		t.timeout.connect(func():
			_mock_poll_done(payload)
			t.queue_free()
		)
		t.start()
	else:
		call_deferred("_mock_poll_done", payload)

## Deterministic mock extractor: parses reviewer sentences into battle-ready questions, rotating
## Identification / Essay / Multiple Choice and tagging a tier by sentence length, so battles use
## real material. Stand-in for the Claude document-extraction endpoint; contract:
## docs/systems/gameplay-structure.md.
func _build_questions_from_text(_topic_name: String, source_text: String) -> Array:
	var sentences := _split_sentences(source_text)
	# Keep content-bearing sentences only.
	var usable: Array = []
	for s in sentences:
		var sent: String = str(s)
		var words := sent.split(" ", false)
		if words.size() >= 6 and sent.length() >= 40:
			usable.append(sent)
		if usable.size() >= 12:
			break
	if usable.is_empty():
		return _fallback_questions()
	var terms_by: Array = []
	for s in usable:
		terms_by.append(_extract_terms(str(s)))
	# Tier by sentence length: the shortest third is easy, the longest third hard.
	var by_length: Array = range(usable.size())
	by_length.sort_custom(func(a: int, b: int) -> bool: return str(usable[a]).length() < str(usable[b]).length())
	var length_rank: Array = range(usable.size())
	for r in by_length.size():
		length_rank[by_length[r]] = r
	var questions: Array = []
	var idx := 0
	for i in usable.size():
		var terms: Array = terms_by[i]
		var excerpt: String = str(usable[i]).strip_edges().left(220)
		var tier: String = ["easy", "medium", "hard"][mini(2, length_rank[i] * 3 / usable.size())]
		var concepts: Array = terms.slice(0, mini(3, terms.size()))
		var answer := str(terms[0]) if not terms.is_empty() else ""
		var kind := idx % 3
		var wrong: Array = []
		if kind == 2:
			wrong = _distractors_for(answer, terms_by, i)
			if wrong.size() < 3:
				kind = 0
		if kind == 1:
			questions.append({
				"id": "q%d" % (idx + 1),
				"text": "Explain in your own words: %s" % excerpt,
				"type": "essay",
				"difficulty": "medium" if tier == "easy" else tier,
				"answer": excerpt,
				"key_concepts": concepts,
				"confidence": 0.7,
				"source": excerpt,
			})
		else:
			if answer == "":
				continue
			questions.append({
				"id": "q%d" % (idx + 1),
				"text": ("Which term is described here? \"%s\"" if kind == 2 else "What key term is described here? \"%s\"") % excerpt,
				"type": "multiple_choice" if kind == 2 else "identification",
				"difficulty": tier,
				"answer": answer,
				"distractors": wrong,
				"key_concepts": concepts,
				"confidence": 0.8 if kind == 2 else 0.85,
				"source": excerpt,
			})
		idx += 1
	if questions.is_empty():
		return _fallback_questions()
	return questions

## Wrong options for a Multiple Choice question: top terms of the other sentences, never the answer.
func _distractors_for(answer: String, terms_by: Array, own: int) -> Array:
	var out: Array = []
	for rank in 2:
		for j in terms_by.size():
			if j == own or terms_by[j].size() <= rank:
				continue
			var t := str(terms_by[j][rank])
			if t.to_lower() != answer.to_lower() and out.find(t) == -1:
				out.append(t)
			if out.size() == 3:
				return out
	return out

## Canned set, used only when no reviewer text survived (binary PDF). Covers every type and tier;
## editable in the categorizer, and battles stay playable via this fallback.
func _fallback_questions() -> Array:
	return [
		{"id": "q1", "text": "What is training data?", "type": "identification", "difficulty": "easy", "answer": "Examples used to teach an AI", "confidence": 0.5, "key_concepts": ["examples", "training"], "source": ""},
		{"id": "q2", "text": "What does an AI learn from?", "type": "multiple_choice", "difficulty": "easy", "answer": "Training data", "distractors": ["Weather reports", "Phone batteries", "Screen brightness"], "confidence": 0.5, "key_concepts": ["training"], "source": ""},
		{"id": "q3", "text": "Explain how feedback helps an AI improve.", "type": "essay", "difficulty": "medium", "answer": "", "confidence": 0.45, "key_concepts": ["feedback", "reward", "iteration"], "source": ""},
		{"id": "q4", "text": "Which describes generalization?", "type": "multiple_choice", "difficulty": "medium", "answer": "Handling new examples it has not seen", "distractors": ["Memorizing every example", "Deleting old data", "Running faster"], "confidence": 0.4, "key_concepts": ["generalization"], "source": ""},
		{"id": "q5", "text": "Why does an AI need trial-and-error practice?", "type": "essay", "difficulty": "hard", "answer": "", "confidence": 0.4, "key_concepts": ["practice", "generalization"], "source": ""},
	]

## topic_001 stays the id for the default/empty name so old saves keep working.
func _slug_topic_id(topic_name: String) -> String:
	var slug := topic_name.strip_edges().to_lower().replace(" ", "_")
	var clean := ""
	for i in slug.length():
		var ch := slug.substr(i, 1)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			clean += ch
	while clean.contains("__"):
		clean = clean.replace("__", "_")
	clean = clean.trim_prefix("_").trim_suffix("_")
	return "topic_" + clean if clean != "" else "topic_001"

const _STOPWORDS = ["what", "when", "where", "which", "while", "with", "from",
	"that", "this", "these", "those", "they", "them", "their", "there", "then",
	"than", "also", "into", "such", "have", "has", "were", "been", "being",
	"does", "did", "will", "would", "could", "should", "about", "after",
	"before", "between", "through", "during", "under", "over", "each",
	"other", "more", "most", "some", "very", "just", "because", "example",
	"examples", "used", "using", "often", "process", "system", "called"]

func _split_sentences(text: String) -> Array:
	var norm := text.strip_edges().replace("\r\n", "\n").replace("\r", "\n")
	var out: Array = []
	for line in norm.split("\n"):
		var frag := line.strip_edges()
		if frag == "":
			continue
		# Split on sentence enders while keeping each chunk intact.
		var buf := ""
		for i in frag.length():
			var ch := frag.substr(i, 1)
			buf += ch
			if ch == "." or ch == "!" or ch == "?":
				var piece := buf.strip_edges().trim_suffix(".").trim_suffix("!").trim_suffix("?").strip_edges()
				if piece.length() >= 20:
					out.append(piece)
				buf = ""
		var tail := buf.strip_edges()
		if tail.length() >= 20:
			out.append(tail)
	return out

## Keyword-ish terms: lowercase alpha words len>=5, not stopwords, in
## first-seen order; capitalized mid-sentence words float to the front as
## likely proper terms. Used for answers + grading key_concepts.
func _extract_terms(sentence: String) -> Array:
	var seen: Dictionary = {}
	var proper: Array = []
	var common: Array = []
	var cleaned := sentence.replace(",", " ").replace(";", " ").replace(":", " ")
	cleaned = cleaned.replace("(", " ").replace(")", " ").replace("\"", " ")
	var raw_words := cleaned.split(" ", false)
	for n in raw_words.size():
		var w := str(raw_words[n]).strip_edges().trim_suffix(".").trim_suffix("!").trim_suffix("?").to_lower()
		if w.length() < 5 or not w.is_valid_identifier() or _STOPWORDS.has(w) or seen.has(w):
			continue
		seen[w] = true
		var orig := str(raw_words[n]).strip_edges()
		if n > 0 and orig.length() > 0 and orig.substr(0, 1) == orig.substr(0, 1).to_upper() and orig.substr(0, 1) != orig.substr(0, 1).to_lower():
			proper.append(w)
		else:
			common.append(w)
		if proper.size() + common.size() >= 6:
			break
	proper.append_array(common)
	return proper

func _mock_upload_done(data: Dictionary) -> void:
	job_status.emit(str(data["job_id"]), str(data["status"]), 0.0, null)


func _mock_poll_done(data: Dictionary) -> void:
	job_status.emit(str(data["job_id"]), str(data["status"]), float(data["progress"]), data["result"])

## Hybrid mock rubric (Phase 7): 50% keyword/concept coverage + 50% holistic
## judgment proxy (length/effort), so mock grading has a deterministic floor
## instead of hardcoded answers. Real Claude grading replaces this server-side.

func _execute_mock_grade(q: Dictionary, answer: String) -> void:
	var qtype: String = str(q.get("type", "essay")).to_lower()
	var tier: String = str(q.get("difficulty", "medium")).to_lower()
	var score := 0.0
	var feedback := ""
	if qtype == "identification" or qtype == "id":
		var expected: String = str(q.get("answer", "")).strip_edges().to_lower()
		var given: String = answer.strip_edges().to_lower()
		if given == "":
			score = 0.0
			feedback = "No answer — the enemy shrugs it off."
		elif expected != "" and given == expected:
			score = 1.0
			feedback = "Exact hit — that's the one!"
		elif expected != "" and tier != "hard" and (given.contains(expected) or expected.contains(given)):
			score = 0.8
			feedback = "Close enough — core term landed."
		elif expected != "" and _fuzzy_match(given, expected, 1 if tier == "hard" else 2):
			score = 0.7
			feedback = "Near miss on spelling, but the idea connected."
		elif expected == "":
			score = 0.5 if given.length() >= 2 else 0.0
			feedback = "No answer key — effort counts for half."
		else:
			score = 0.0
			feedback = "That missed — review the concept and strike again."
	else:
		var concepts: Array = q.get("key_concepts", [])
		var lowered: String = answer.strip_edges().to_lower()
		var hits := 0
		var missed: Array = []
		for c in concepts:
			var kw: String = str(c).to_lower()
			if kw != "" and lowered.contains(kw):
				hits += 1
			elif kw != "":
				missed.append(str(c))
		var coverage := 0.0
		if concepts.size() > 0:
			coverage = float(hits) / float(concepts.size())
		else:
			coverage = 0.5 if lowered.length() >= 10 else 0.0
		var words := lowered.split(" ", false).size()
		var holistic: float = clampf(float(words) / 30.0, 0.0, 1.0)
		score = 0.5 * coverage + 0.5 * holistic
		if concepts.size() > 0 and hits == concepts.size():
			feedback = "Full coverage — every key idea landed."
		elif hits > 0:
			feedback = "Good — covered %d/%d ideas, missed: %s." % [hits, concepts.size(), ", ".join(missed)]
		elif words < 4:
			feedback = "Too thin — explain the mechanism in your own words."
		else:
			feedback = "Words, but not the key ideas — aim at: %s." % ", ".join(concepts)
	var damage := int(round(score * 100.0))
	call_deferred("_mock_grade_done", {"score": score, "feedback": feedback, "damage": damage, "type": qtype})


## Token-overlap fuzzy match for identification answers (typo-tolerant).
func _fuzzy_match(a: String, b: String, max_distance: int = 2) -> bool:
	if a == "" or b == "":
		return false
	if abs(a.length() - b.length()) > 3:
		return false
	return _edit_distance(a, b) <= max_distance

func _edit_distance(a: String, b: String) -> int:
	var prev: Array = []
	prev.resize(b.length() + 1)
	for j in b.length() + 1:
		prev[j] = j
	for i in a.length():
		var cur: Array = [i + 1]
		for j in b.length():
			var cost := 0 if a[i] == b[j] else 1
			cur.append(mini(mini(int(cur[j]) + 1, int(prev[j + 1]) + 1), int(prev[j]) + cost))
		prev = cur
	return int(prev[b.length()])

func _mock_grade_done(data: Dictionary) -> void:
	job_status.emit("grade", "completed", 1.0, data)

func mock_get_topics() -> void:
	call_deferred("_mock_topics_done", {"topics": []})

func _mock_topics_done(data: Dictionary) -> void:
	job_status.emit("topics", "completed", 1.0, data)
