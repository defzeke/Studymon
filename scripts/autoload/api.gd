extends Node
## Api — HTTP wrapper for backend calls (canonical registered version).
## MOCK mode returns canned data so client dev is never blocked; exported release builds use the server.
## Godot only ever talks to OUR api, never api.anthropic.com directly.
## Contract: docs/api-backend.md. Do not name a helper plain `_get`: it would override Object._get().

signal job_status(job_id: String, status: String, progress: float, result: Variant)

## The deployed study server. Must be HTTPS: Android and iOS refuse plain http. Set before exporting.
const RELEASE_URL := ""
## true to try the local study server from the editor or a debug export instead of the mock.
const DEV_USES_SERVER := false
# 127.0.0.1, not localhost: localhost can resolve to IPv6 first, which uvicorn does not listen on.
const DEV_URL := "http://127.0.0.1:8000"
var MOCK := OS.is_debug_build() and not DEV_USES_SERVER
var BASE_URL := DEV_URL if OS.is_debug_build() else RELEASE_URL
# Seconds before a request counts as failed: generating a whole question bank takes the longest.
const EXTRACT_TIMEOUT := 180.0
const GRADE_TIMEOUT := 30.0

var _job_seq := 0

func _ready() -> void:
	if not MOCK and not BASE_URL.begins_with("https://") and not OS.is_debug_build():
		push_error("Api: RELEASE_URL must be the deployed HTTPS study server; every AI request will fail.")

## A job id no other request shares, so each screen only takes its own results (rules §5, issue #9).
func new_job_id(kind: String) -> String:
	_job_seq += 1
	return "%s_%d" % [kind, _job_seq]

# One HTTPRequest per call, so requests never cancel each other. Every outcome reaches job_status:
# the server's envelope on success, "failed" with a message the player can read otherwise.
func _request(job_id: String, method: int, endpoint: String, data: Dictionary, timeout: float) -> void:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		_on_request_completed(job_id, result, code, body))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if http.request(BASE_URL + endpoint, headers, method, JSON.stringify(data)) != OK:
		http.queue_free()
		_fail_later(job_id, "Could not start the request.")

func _on_request_completed(job_id: String, result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		job_status.emit(job_id, "failed", 1.0, "No connection to the study server.")
		return
	if code == 429:
		job_status.emit(job_id, "failed", 1.0, "You've reached today's AI limit. Try again tomorrow.")
		return
	if code < 200 or code >= 300:
		job_status.emit(job_id, "failed", 1.0, "The study server returned an error (%d)." % code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or str((parsed as Dictionary).get("job_id", "")) != job_id:
		job_status.emit(job_id, "failed", 1.0, "The study server sent an unreadable reply.")
		return
	var data: Dictionary = parsed
	job_status.emit(job_id, str(data.get("status", "failed")), float(data.get("progress", 1.0)), data.get("result", null))

func _fail_later(job_id: String, message: String) -> void:
	job_status.emit.call_deferred(job_id, "failed", 1.0, message)

## Grades a typed answer: `mode` is "identification" (a near-miss the answer key did not settle) or
## "essay". The result {score, feedback, covered?} arrives on job_status under `job_id`.
## Contract: docs/api-backend.md §2.
func grade_battle_question(job_id: String, q: Dictionary, answer: String, mode: String) -> void:
	if MOCK:
		_execute_mock_grade(job_id, q, answer, mode)
		return
	if not GameState.ai_consent:
		_fail_later(job_id, "AI grading is off in Settings.")
		return
	_request(job_id, HTTPClient.METHOD_POST, "/v1/grade", {
		"job_id": job_id,
		"mode": mode,
		"question": str(q.get("text", "")),
		"answer": answer,
		"expected": str(q.get("answer", "")),
		"accepted": q.get("accepted", []),
		"rubric": rubric_for(q),
		"model_answer": str(q.get("model_answer", "")),
		"source": str(q.get("source", "")),
	}, GRADE_TIMEOUT)

## Turns a reviewer into questions with their answer keys: pasted text, or a PDF's bytes (sent only
## when the server is on; the mock reads text). The result arrives on job_status under `job_id`.
func upload_reviewer(job_id: String, topic_name: String, source_text: String, pdf: PackedByteArray) -> void:
	if MOCK:
		_execute_mock_upload(job_id, topic_name, source_text)
		return
	if not GameState.ai_consent:
		_fail_later(job_id, "Allow the AI to read your reviewer first.")
		return
	job_status.emit.call_deferred(job_id, "processing", 0.0, null)
	var body := {"job_id": job_id, "topic_name": topic_name}
	if pdf.is_empty():
		body["text"] = source_text
	else:
		body["pdf_base64"] = Marshalls.raw_to_base64(pdf)
	_request(job_id, HTTPClient.METHOD_POST, "/v1/extract", body, EXTRACT_TIMEOUT)

## Reports a generated question or AI feedback as wrong or offensive (a store requirement). `kind` is
## "question" or "feedback"; the result arrives on job_status under `job_id`.
func report_content(job_id: String, kind: String, text: String) -> void:
	if MOCK:
		job_status.emit.call_deferred(job_id, "completed", 1.0, {"ok": true})
		return
	_request(job_id, HTTPClient.METHOD_POST, "/v1/reports", {"job_id": job_id, "kind": kind, "text": text.left(4000)}, GRADE_TIMEOUT)

# --- Answer checking on the device (contract: docs/systems/battle.md §2) ---

## Lowercase, punctuation stripped, spaces collapsed, a leading article dropped.
func normalize_answer(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if ch.is_valid_unicode_identifier() or ch.is_valid_int() or ch == " " else " "
	var words := out.split(" ", false)
	if words.size() > 1 and words[0] in ["a", "an", "the"]:
		words.remove_at(0)
	return " ".join(words)

## Typos forgiven for a key of this many letters: none up to 4, 1 up to 8, else 2; one fewer when strict.
func _typo_allowance(length: int, strict: bool) -> int:
	var n := 0 if length <= 4 else (1 if length <= 8 else 2)
	return maxi(0, n - (1 if strict else 0))

## An Identification answer against the question's answer key: {verdict: "correct" | "near" | "wrong",
## feedback}. "near" (close, but not on the key) is for grade_battle_question to settle.
func check_identification(q: Dictionary, given: String, strict: bool) -> Dictionary:
	var g := normalize_answer(given)
	var keys: Array[String] = []
	for k in [q.get("answer", "")] + Array(q.get("accepted", [])):
		var n := normalize_answer(str(k))
		if n != "" and not keys.has(n):
			keys.append(n)
	var expected := str(q.get("answer", "")).strip_edges()
	if g == "":
		return {"verdict": "wrong", "feedback": "No answer — the enemy shrugs it off."}
	if keys.is_empty():
		return {"verdict": "near", "feedback": "This card has no answer key yet. Add one with Edit on the worlds list."}
	for k in keys:
		if g == k:
			return {"verdict": "correct", "feedback": "Exact hit — that's the one!"}
	for k in keys:
		if _edit_distance(g, k) <= _typo_allowance(k.length(), strict):
			return {"verdict": "correct", "feedback": "Small typo, but the idea connected. The key says %s." % expected}
	for k in keys:
		var shares := false
		for w in g.split(" ", false):
			shares = shares or (w.length() >= 3 and w in k.split(" ", false))
		if shares or _edit_distance(g, k) <= floori(k.length() / 3.0):
			return {"verdict": "near", "feedback": "Close — the key says %s." % expected}
	return {"verdict": "wrong", "feedback": "That missed — the key says %s." % expected}

## The points an essay is marked on: its rubric, else one point per key idea, else its answer.
func rubric_for(q: Dictionary) -> Array:
	var rubric: Array = q.get("rubric", [])
	if not rubric.is_empty():
		return rubric
	var ideas: Array = q.get("key_concepts", [])
	if ideas.is_empty() and str(q.get("answer", "")).strip_edges() != "":
		ideas = [str(q["answer"]).strip_edges()]
	var out: Array = []
	for idea in ideas:
		out.append({"point": str(idea), "keywords": [str(idea)], "weight": 1.0})
	return out

## The offline essay mark, used by the mock and whenever the server cannot grade: a point counts when
## one of its keywords is in the answer, and length helps only once some point is covered (so filler
## alone scores 0). Returns {score, covered, feedback}.
func essay_offline(q: Dictionary, answer: String) -> Dictionary:
	var said := " %s " % normalize_answer(answer)
	var rubric := rubric_for(q)
	var covered: Array[bool] = []
	var got := 0.0
	var total := 0.0
	var missed: Array[String] = []
	for r: Dictionary in rubric:
		var hit := false
		for kw in Array(r.get("keywords", [])) + [r.get("point", "")]:
			var k := normalize_answer(str(kw))
			hit = hit or (k != "" and said.contains(" %s " % k))
		covered.append(hit)
		total += float(r.get("weight", 1.0))
		if hit:
			got += float(r.get("weight", 1.0))
		else:
			missed.append(str(r.get("point", "")))
	var coverage := got / total if total > 0.0 else 0.0
	var words := answer.split(" ", false).size()
	var score := 0.0 if coverage == 0.0 else 0.7 * coverage + 0.3 * clampf(words / 30.0, 0.0, 1.0)
	var feedback := "Full coverage — every key idea landed."
	if rubric.is_empty():
		feedback = "This card has no key ideas yet. Add them with Edit on the worlds list."
	elif coverage == 0.0:
		feedback = "None of the key ideas landed — aim at: %s." % ", ".join(missed)
	elif not missed.is_empty():
		feedback = "Good — still missing: %s." % ", ".join(missed)
	return {"score": score, "covered": covered, "feedback": feedback}

## MOCKS — the offline stand-ins for the study server (Api.MOCK)

func _execute_mock_upload(job_id: String, topic_name: String, source_text: String) -> void:
	# Simulate short processing beat like GDD §5.2 "AI is studying..."
	call_deferred("_mock_upload_done", {"job_id": job_id, "status": "processing"})
	# Complete after ~0.8s via timer if tree is ready, else immediate.
	# Questions are parsed from the USER's reviewer text; canned placeholders
	# only apply when no usable text survived (e.g. binary PDF bytes).
	var questions := _build_questions_from_text(topic_name, source_text)
	var topic_id := _slug_topic_id(topic_name)
	var payload := {
		"job_id": job_id,
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
				"text": ("Which term is described here? \"%s\"" if kind == 2 else "What key term is described here? \"%s\"") % _blank(excerpt, answer),
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

## `excerpt` with the answer term blanked out, so the question does not hand over its own answer.
## Terms are plain words (`_extract_terms` keeps valid identifiers), so they are safe in a pattern.
func _blank(excerpt: String, term: String) -> String:
	return RegEx.create_from_string("(?i)\\b%s\\b" % term).sub(excerpt, "_____", true)

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

## The mock grader: an essay gets the offline rubric mark; an Identification near-miss stays a miss,
## since only the server can judge a synonym the answer key does not list.
func _execute_mock_grade(job_id: String, q: Dictionary, answer: String, mode: String) -> void:
	var data := essay_offline(q, answer) if mode == "essay" else {"score": 0.0, "feedback": check_identification(q, answer, false)["feedback"]}
	job_status.emit.call_deferred(job_id, "completed", 1.0, data)

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

func mock_get_topics() -> void:
	call_deferred("_mock_topics_done", {"topics": []})

func _mock_topics_done(data: Dictionary) -> void:
	job_status.emit("topics", "completed", 1.0, data)
