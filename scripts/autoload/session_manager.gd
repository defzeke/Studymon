extends Node
## SessionManager — Review Session flow (Phase 5) + Overworld progress (Phase 6)
## Client-side: topics → upload → extraction → edit → confirm → region → gyms

signal topics_listed(topics: Array[Dictionary])
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
# Contract: docs/systems/gameplay-structure.md
const DIFFICULTIES: Array[String] = ["easy", "medium", "hard"]
## The three question types, in GymSlot order: each has a Challenge House and a Gym.
const RUN_TYPES: Array[String] = ["identification", "essay", "multiple_choice"]
## Items per run: [type, count] segments. The Champion plays all three in one run.
const RUN_QUOTAS := {
	"house": [["multiple_choice", 10], ["identification", 5], ["essay", 5]],
	"gym": [["multiple_choice", 20], ["identification", 10], ["essay", 10]],
	"champion": [["multiple_choice", 20], ["identification", 10], ["essay", 10]],
}
## The tier a run is fought at and the questions it prefers.
const RUN_TIER := {"house": "easy", "gym": "medium", "champion": "hard"}
## The review time a run is built to last, in minutes (about one per item; see the review beat).
const RUN_MINUTES := {"house": 10, "gym": 20, "champion": 30}
## Crystals / XP per correct item, and the first-clear bonus.
const RUN_REWARDS := {
	"house": {"coin": 1, "xp": 1, "clear_coin": 20, "clear_xp": 10},
	"gym": {"coin": 2, "xp": 2, "clear_coin": 60, "clear_xp": 30},
	"champion": {"coin": 3, "xp": 3, "clear_coin": 200, "clear_xp": 100},
}
## Accuracy needed for 1, 2 and 3 stars, and the reward multiplier for 0..3 stars.
const STAR_ACCURACY: Array[float] = [0.70, 0.85, 0.95]
const STAR_MULT: Array[float] = [1.0, 1.0, 1.25, 1.5]
const REPLAY_RATE := 0.25
const DEFEAT_RATE := 0.5

var current_topic_id: String = ""
var pending_questions: Array[Dictionary] = []
var editing_topic_id: String = ""
## Phase 5: raw reviewer text from the last upload (paste or decoded file bytes).
## Stored so the mock extractor can parse USER material instead of canned defaults.
var last_source_text: String = ""
var _topics: Array[Dictionary] = []
var _active_job_id: String = ""
# Phase 6: per-region clear state (mock-persisted in memory)
var _cleared_houses: Dictionary = {}  # "topic_id:gym_type#house_id" -> true
var _cleared_gyms: Dictionary = {}  # "topic_id:gym_type" -> true
var _best_stars: Dictionary = {}  # "kind:topic_id:run_key" -> 0..3 (run_key: type, or type#house_id)

func _ready() -> void:
	Api.job_status.connect(_on_job_status)

# --- Topics history (mock-persisted in memory until SaveManager handles it) ---

## Fills defaults and repairs rows a battle could not play: an unknown tier becomes medium, and a
## Multiple Choice row without a correct answer and a wrong option becomes Identification.
func normalize_question(q: Dictionary) -> Dictionary:
	var d: Dictionary = q.duplicate(true)
	d["type"] = str(d.get("type", "essay")).to_lower()
	var tier := str(d.get("difficulty", "medium")).to_lower()
	d["difficulty"] = tier if tier in DIFFICULTIES else "medium"
	if d["type"] == "multiple_choice":
		var wrong: Array = []
		for x in d.get("distractors", []):
			if str(x).strip_edges() != "":
				wrong.append(str(x).strip_edges())
		d["distractors"] = wrong
		if str(d.get("answer", "")).strip_edges() == "" or wrong.is_empty():
			d["type"] = "identification"
	return d

func list_topics() -> void:
	Api.mock_get_topics()

func get_topics_cache() -> Array[Dictionary]:
	return _topics.duplicate(true)

func add_topic_to_history(topic_id: String, topic_label: String, questions: Array[Dictionary]) -> void:
	for i in _topics.size():
		if _topics[i].get("id", "") == topic_id:
			_topics[i] = {"id": topic_id, "name": topic_label, "question_count": questions.size(), "questions": questions.duplicate(true)}
			return
	_topics.append({"id": topic_id, "name": topic_label, "question_count": questions.size(), "questions": questions.duplicate(true)})


func world_name(topic_id: String) -> String:
	for t in _topics:
		if str(t.get("id", "")) == topic_id:
			return str(t.get("name", topic_id))
	return ""

## Houses and gyms cleared in a world, for the worlds list.
func topic_progress(topic_id: String) -> Dictionary:
	var gyms := 0
	for t in RUN_TYPES:
		gyms += 1 if is_gym_cleared(topic_id, t) else 0
	return {"houses": houses_cleared(topic_id), "gyms": gyms, "gyms_total": RUN_TYPES.size(), "questions": _questions_for(topic_id).size()}

func _erase_prefixed(d: Dictionary, prefix: String) -> void:
	for k in d.keys():
		if str(k).begins_with(prefix):
			d.erase(k)

## Clears a world's cleared houses/gyms, mastery and Champion; its questions stay.
func reset_topic_progress(topic_id: String) -> void:
	var prefix := topic_id + ":"
	_erase_prefixed(_mastery, prefix)
	_erase_prefixed(_cleared_houses, prefix)
	_erase_prefixed(_cleared_gyms, prefix)
	for kind in RUN_QUOTAS:
		_erase_prefixed(_best_stars, kind + ":" + prefix)
	_champion_defeated.erase(topic_id)
	overworld_progress_changed.emit()
	mastery_changed.emit()
	SaveManager.save_progress()

func delete_topic(topic_id: String) -> void:
	reset_topic_progress(topic_id)
	for i in range(_topics.size() - 1, -1, -1):
		if str(_topics[i].get("id", "")) == topic_id:
			_topics.remove_at(i)
	if editing_topic_id == topic_id:
		editing_topic_id = ""
		pending_questions = []
	if current_topic_id == topic_id:
		current_topic_id = ""
	if GameState.active_region_id == topic_id:
		GameState.set_active_region("")
	topics_listed.emit(_topics.duplicate(true))
	SaveManager.save_progress()

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
						var d := normalize_question(q)
						if not d.has("confidence"):
							d["confidence"] = 0.7
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
	pending_questions = []
	for q in questions:
		pending_questions.append(normalize_question(q))

func add_question(text: String, qtype: String, answer: String = "", key_concepts: Array[String] = [], difficulty: String = "medium", distractors: Array = []) -> void:
	var id = "q_" + str(pending_questions.size() + 1) + "_" + str(randi() % 10000)
	pending_questions.append({"id": id, "text": text, "type": qtype.to_lower(), "difficulty": difficulty, "answer": answer, "distractors": distractors, "key_concepts": key_concepts, "confidence": 0.5})

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
	var topic_label := topic_name if topic_name != "" else editing_topic_id
	add_topic_to_history(editing_topic_id, topic_label, pending_questions)
	Api.save_topic(editing_topic_id, pending_questions)
	SaveManager.save_progress()
	topic_saved.emit(editing_topic_id)
	_enter_overworld(editing_topic_id)

func _enter_overworld(topic_id: String) -> void:
	region_generated.emit(topic_id, build_map_data(topic_id, pending_questions))

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

func get_pending_questions() -> Array[Dictionary]:
	return pending_questions.duplicate(true)

# --- Phase 6: houses, gyms and runs (contract: docs/systems/gameplay-structure.md) ---

## One entry per question type, in GymSlot order; empty until the topic has a question.
func get_gym_structure() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if pending_questions.is_empty():
		return out
	for t in RUN_TYPES:
		out.append({"type": t})
	return out

func is_house_cleared(topic_id: String, gym_type: String, house_id: String) -> bool:
	return _cleared_houses.has("%s:%s#%s" % [topic_id, gym_type, house_id])

## Houses cleared in a world, of one type or (type "") of all. A v13 key, which has no house id, still counts.
func houses_cleared(topic_id: String, gym_type := "") -> int:
	var n := 0
	var prefix := "%s:%s" % [topic_id, gym_type]
	for k: String in _cleared_houses:
		if (gym_type == "" and k.begins_with(prefix)) or k == prefix or k.begins_with(prefix + "#"):
			n += 1
	return n

func is_gym_cleared(topic_id: String, gym_type: String) -> bool:
	return _cleared_gyms.has("%s:%s" % [topic_id, gym_type])

## A gym opens once any Challenge House of its type is cleared.
func is_gym_open(topic_id: String, gym_type: String) -> bool:
	return houses_cleared(topic_id, gym_type) > 0

## How many items a run plays.
func run_items(kind: String, gym_type: String) -> int:
	var n := 0
	for seg: Array in RUN_QUOTAS[kind]:
		if kind == "champion" or str(seg[0]) == gym_type:
			n += int(seg[1])
	return n

## `run_key` is the type, or "type#house_id" for a house.
func best_stars(kind: String, topic_id: String, run_key: String) -> int:
	return int(_best_stars.get("%s:%s:%s" % [kind, topic_id, run_key], 0))

# --- Phase 7: runs ---
# A battle is a run: a fixed list of items fought against one foe. Contract: docs/systems/battle.md.

var battle_topic_id: String = ""
var battle_kind: String = ""
var battle_type: String = ""
## The Challenge House being played ("" for a gym or the Champion) and its number on the map.
var battle_house: String = ""
var battle_variant := 0
var battle_run: Array[Dictionary] = []

## Called by the overworld before it opens the battle scene. `variant` (a house's number) starts each
## house at a different point of the question pool, so two houses of one type do not play alike.
func begin_run(topic_id: String, kind: String, gym_type: String = "", house_id := "", variant := 0) -> bool:
	var items := build_run(topic_id, kind, gym_type, false, variant)
	if items.is_empty():
		return false
	battle_topic_id = topic_id
	battle_kind = kind
	battle_type = gym_type
	battle_house = house_id
	battle_variant = variant
	battle_run = items
	return true

## Rebuilds the active run with each segment shuffled (Try Again).
func reshuffle_run() -> void:
	battle_run = build_run(battle_topic_id, battle_kind, battle_type, true, battle_variant)

func _run_key() -> String:
	return battle_type + ("#" + battle_house if battle_house != "" else "")

## The items of a run: [{q_index, question}]. A segment takes the questions of its type nearest the run's
## tier first (Remaster, then New, then the rest), then questions convertible to the type, then cycles
## through them again so a short reviewer still fills the quota.
func build_run(topic_id: String, kind: String, gym_type: String, shuffle := false, variant := 0) -> Array[Dictionary]:
	var qs: Array = _questions_for(topic_id)
	var out: Array[Dictionary] = []
	if qs.is_empty() or not RUN_QUOTAS.has(kind):
		return out
	var target: int = DIFFICULTIES.find(RUN_TIER[kind])
	for seg: Array in RUN_QUOTAS[kind]:
		if kind != "champion" and str(seg[0]) != gym_type:
			continue
		out.append_array(_segment(topic_id, qs, str(seg[0]), int(seg[1]), target, shuffle, variant))
	return out

func _segment(topic_id: String, qs: Array, type: String, count: int, target: int, shuffle: bool, variant: int) -> Array[Dictionary]:
	var order: Array = range(qs.size())
	var mastery_rank := [Mastery.REMASTER, Mastery.NEW, Mastery.LEARNING, Mastery.MASTERED]
	order.sort_custom(func(a: int, b: int) -> bool:
		var ka := [0 if str(qs[a].get("type", "")) == type else 1, absi(_tier_rank(qs[a]) - target), mastery_rank.find(get_mastery_state(topic_id, a)), a]
		var kb := [0 if str(qs[b].get("type", "")) == type else 1, absi(_tier_rank(qs[b]) - target), mastery_rank.find(get_mastery_state(topic_id, b)), b]
		return ka < kb)
	# Items played as the segment's type come first; only when no question can be, the run falls back to
	# the forms the questions can take, so every house and gym can always be entered.
	var pool: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	for i: int in order:
		var q := _as_type(qs[i], type, qs)
		(pool if str(q["type"]) == type else fallback).append({"q_index": i, "question": q})
	if pool.is_empty():
		pool = fallback
	var out: Array[Dictionary] = []
	if pool.is_empty():
		return out
	var start := (variant * count) % pool.size()
	for n in count:
		out.append((pool[(start + n) % pool.size()] as Dictionary).duplicate(true))
	if shuffle:
		out.shuffle()
	return out

## `q` rewritten as `type` when it has what that type needs, else `q` as it is (always playable).
## The correct answer is the answer key, or else the first key idea. Identification needs one; Multiple
## Choice needs one plus wrong options (its own, then other questions' answers and key ideas), and
## without wrong options is played as Identification; Essay takes its key ideas from the answer.
func _as_type(q: Dictionary, type: String, qs: Array) -> Dictionary:
	var d := q.duplicate(true)
	if str(d.get("type", "")) == type:
		return d
	var answer := str(d.get("answer", "")).strip_edges()
	var ideas: Array = d.get("key_concepts", [])
	if answer == "" and not ideas.is_empty():
		answer = str(ideas[0]).strip_edges()
	match type:
		"identification":
			if answer == "":
				return d
			d["answer"] = answer
		"multiple_choice":
			if answer == "":
				return d
			d["answer"] = answer
			var wrong: Array = []
			for x in d.get("distractors", []):
				wrong.append(str(x))
			for other: Dictionary in qs:
				var options: Array = [other.get("answer", "")]
				options.append_array(other.get("key_concepts", []))
				for o in options:
					var s := str(o).strip_edges()
					if wrong.size() < 3 and s != "" and s.to_lower() != answer.to_lower() and not wrong.has(s):
						wrong.append(s)
			if wrong.is_empty():
				d["type"] = "identification"
				return d
			d["distractors"] = wrong
		"essay":
			if ideas.is_empty() and answer != "":
				d["key_concepts"] = [answer]
			d["text"] = "Explain: " + str(d.get("text", ""))
	d["type"] = type
	return d

## Rank of a question's tier, Easy 0 to Hard 2 (unknown tiers count as medium).
func _tier_rank(q: Dictionary) -> int:
	return maxi(0, DIFFICULTIES.find(str(q.get("difficulty", "medium"))))

## Stars for an accuracy (0..3).
func stars_for(accuracy: float) -> int:
	var stars := 0
	for need in STAR_ACCURACY:
		if accuracy >= need:
			stars += 1
	return stars

## Settles a finished run: marks the house / gym / Champion cleared on a win, pays crystals and XP
## (replays pay REPLAY_RATE, a defeat DEFEAT_RATE of the per-item pay) and charges Kuiz the effort.
## Returns {stars, coins, xp, first, replay} for the results panel.
func report_run(won: bool, correct: int, total: int, best_streak: int) -> Dictionary:
	var pay: Dictionary = RUN_REWARDS[battle_kind]
	var first := false
	match battle_kind:
		"house":
			first = not is_house_cleared(battle_topic_id, battle_type, battle_house)
		"gym":
			first = not is_gym_cleared(battle_topic_id, battle_type)
		"champion":
			first = not is_champion_defeated(battle_topic_id)
	var replay := won and not first
	var stars := stars_for(float(correct) / maxf(1.0, float(total)))
	var coins := float(correct * int(pay["coin"]))
	var xp := float(correct * int(pay["xp"]))
	if won:
		coins += best_streak / 5
		if first:
			coins += int(pay["clear_coin"])
			xp += int(pay["clear_xp"])
		coins *= STAR_MULT[stars]
		xp *= STAR_MULT[stars]
		if replay:
			coins *= REPLAY_RATE
			xp *= REPLAY_RATE
	else:
		coins *= DEFEAT_RATE
		xp *= DEFEAT_RATE
	var coins_won := roundi(coins * CompanionState.crystal_mult())
	var xp_won := roundi(xp * CompanionState.xp_mult())
	GameState.add_crystals(coins_won)
	CompanionState.add_xp(xp_won)
	if won:
		_mark_run_cleared(stars)
	SaveManager.save_progress()
	return {"stars": stars, "coins": coins_won, "xp": xp_won, "first": first, "replay": replay}

func _mark_run_cleared(stars: int) -> void:
	var k := "%s:%s" % [battle_topic_id, battle_type]
	match battle_kind:
		"house":
			_cleared_houses["%s:%s" % [battle_topic_id, _run_key()]] = true
		"gym":
			_cleared_gyms[k] = true
		"champion":
			_champion_defeated[battle_topic_id] = true
			champion_defeated.emit(battle_topic_id)
	var sk := "%s:%s:%s" % [battle_kind, battle_topic_id, _run_key()]
	_best_stars[sk] = maxi(int(_best_stars.get(sk, 0)), stars)
	overworld_progress_changed.emit()

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
			# Gold/amber is perceptually distinct for colorblind users
			return {"emoji": "🟡", "color": Color(1.0, 0.82, 0.2), "name": "Learning"}
		Mastery.REMASTER:
			# Orange is distinct from both New gray and Mastered blue
			return {"emoji": "🟠", "color": Color(1.0, 0.55, 0.1), "name": "Remaster"}
		Mastery.MASTERED:
			# Blue hue (not green) for Mastered - colorblind-safe: blue vs gray/new
			return {"emoji": "🔵", "color": Color(0.2, 0.65, 1.0), "name": "Mastered"}
	return {"emoji": "⚪", "color": Color(0.75, 0.75, 0.8), "name": "New"}

# --- Phase 9: Data-Driven AI Insights ---
# Rule-based trigger system: condition -> line pool mappings.
# Conditions reference mastery data without LLM calls.
# Editable via the INSIGHT_TRIGGERS dict below; no code changes needed to add new triggers.

# Writers edit the dict below (states + thresholds -> line pool) without touching code.
# states uses Mastery enum ints: 0=NEW, 1=LEARNING, 2=REMASTER, 3=MASTERED.
const INSIGHT_TRIGGERS: Dictionary = {
	# Subject failure: NEW/LEARNING question with >= 3 attempts and no mastery yet.
	"topic_failed_repeatedly": {
		"states": [0, 1],
		"min_attempts": 3,
		"needs_just_mastered": false,
		"lines": [
			"Keep trying! You're close to mastering this.",
			"Don't give up on this subject yet.",
			"Every expert was once a beginner."
		],
	},
	# Mastery milestone: question just reached MASTERED.
	"question_mastered": {
		"states": [3],
		"min_attempts": 0,
		"needs_just_mastered": true,
		"lines": [
			"Nice work! You've mastered this topic.",
			"Great job retaining what you studied.",
			"This one's locked in your memory."
		],
	},
	# Long-term retention risk: decayed back to REMASTER.
	"retention_risk": {
		"states": [2],
		"min_attempts": 0,
		"needs_just_mastered": false,
		"lines": [
			"Remember, you can bring this back with practice.",
			"Spaced repetition helps retention — try again soon.",
			"This topic needs a quick review."
		],
	},
}

signal insight_triggered(topic_id: String, q_idx: int, text: String)
var last_insight: String = ""

func _check_insight_triggers(topic_id: String, q_idx: int, won: bool, prev_state: int = -1) -> String:
	# No LLM calls — pure rule check off _mastery state. prev_state lets
	# the 'question_mastered' trigger fire only on the transition into MASTERED,
	# not on every subsequent win while already mastered.
	var mastery_state: int = get_mastery_state(topic_id, q_idx)
	var k := _mastery_key(topic_id, q_idx)
	var rec: Dictionary = _mastery.get(k, {"state": mastery_state, "attempts": 0, "correct": 0, "last_correct": 0})
	var attempts: int = int(rec.get("attempts", 0))
	# Priority order: mastered milestone first, then retention, then struggle
	var priority: Array[String] = ["question_mastered", "retention_risk", "topic_failed_repeatedly"]
	for trigger_name in priority:
		if not INSIGHT_TRIGGERS.has(trigger_name):
			continue
		var trigger_data: Dictionary = INSIGHT_TRIGGERS[trigger_name]
		var allowed: Array = trigger_data.get("states", [])
		if mastery_state not in allowed:
			continue
		var min_attempts: int = int(trigger_data.get("min_attempts", 0))
		if attempts < min_attempts:
			continue
		var needs_just: bool = bool(trigger_data.get("needs_just_mastered", false))
		if needs_just:
			if not won or mastery_state != Mastery.MASTERED:
				continue
			if prev_state != -1 and prev_state == Mastery.MASTERED:
				continue
		if trigger_name == "topic_failed_repeatedly" and won:
			continue
		var lines: Array = trigger_data.get("lines", [])
		if lines.is_empty():
			continue
		return str(lines[randi() % lines.size()])
	return ""

func record_battle_outcome(topic_id: String, q_idx: int, won: bool) -> void:
	var k := _mastery_key(topic_id, q_idx)
	var rec: Dictionary = _mastery.get(k, {"state": Mastery.NEW, "attempts": 0, "correct": 0, "last_correct": 0})
	var prev_st: int = int(rec.get("state", Mastery.NEW))
	var st: int = prev_st
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
	# Phase 9: rule-based companion insight after every battle (mock and real)
	var insight := _check_insight_triggers(topic_id, q_idx, won, prev_st)
	if insight != "":
		last_insight = insight
		insight_triggered.emit(topic_id, q_idx, insight)

func _questions_for(topic_id: String) -> Array:
	if topic_id == editing_topic_id or topic_id == current_topic_id:
		return pending_questions
	for t in _topics:
		if str(t.get("id", "")) == topic_id:
			return t.get("questions", [])
	return []

# --- Phase 4: Flashcard Sanctuary (contract: docs/systems/gameplay-structure.md §3.4) ---

## Where the sanctuary's Back button returns to; its callers set it.
var flashcards_return: String = "res://scenes/ui/session_list.tscn"

## Card order for a review: Remaster, then New, Learning, Mastered; ties in question order.
func flashcard_deck(topic_id: String) -> Array:
	var order := [Mastery.REMASTER, Mastery.NEW, Mastery.LEARNING, Mastery.MASTERED]
	var deck: Array = range(_questions_for(topic_id).size())
	deck.sort_custom(func(a: int, b: int) -> bool:
		var ra := order.find(get_mastery_state(topic_id, a))
		var rb := order.find(get_mastery_state(topic_id, b))
		return ra < rb or (ra == rb and a < b))
	return deck

## "Easy" in review lifts New or Remaster to Learning; Mastered is earned only in battle.
## True when the card moved.
func promote_from_review(topic_id: String, q_idx: int) -> bool:
	var st := get_mastery_state(topic_id, q_idx)
	if st != Mastery.NEW and st != Mastery.REMASTER:
		return false
	var k := _mastery_key(topic_id, q_idx)
	var rec: Dictionary = _mastery.get(k, {"state": Mastery.NEW, "attempts": 0, "correct": 0, "last_correct": 0})
	rec["state"] = Mastery.LEARNING
	_mastery[k] = rec
	mastery_changed.emit()
	return true

# --- Phase 8: Champion ---

## The Champion opens once every gym is cleared.
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

func to_dict() -> Dictionary:
	return {
		"mastery": _mastery.duplicate(true),
		"cleared_houses": _cleared_houses.keys(),
		"cleared_gyms": _cleared_gyms.keys(),
		"best_stars": _best_stars.duplicate(),
		"champion_defeated": _champion_defeated.keys(),
		"topics": _topics.duplicate(true),
	}

func from_dict(data: Dictionary) -> void:
	_mastery = (data.get("mastery", {}) as Dictionary).duplicate(true)
	_cleared_gyms = {}
	for k in data.get("cleared_gyms", []):
		_cleared_gyms[str(k)] = true
	# v13: a gym cleared before houses existed counts as a house of its type cleared.
	_cleared_houses = _cleared_gyms.duplicate()
	for k in data.get("cleared_houses", []):
		_cleared_houses[str(k)] = true
	_best_stars = {}
	var stars: Dictionary = data.get("best_stars", {})
	for k in stars:
		_best_stars[str(k)] = int(stars[k])
	_champion_defeated = {}
	for k in data.get("champion_defeated", []):
		_champion_defeated[str(k)] = true
	_topics = []
	for t in data.get("topics", []):
		if t is Dictionary:
			var topic: Dictionary = (t as Dictionary).duplicate(true)
			var qs: Array = []
			for q in topic.get("questions", []):
				qs.append(normalize_question(q) if q is Dictionary else q)
			topic["questions"] = qs
			_topics.append(topic)
	overworld_progress_changed.emit()
	mastery_changed.emit()
