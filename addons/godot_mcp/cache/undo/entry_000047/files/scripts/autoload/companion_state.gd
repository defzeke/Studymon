extends Node
## CompanionState — persistent companion data (Phase 2+)

signal stats_changed
signal xp_changed(current_xp: int, level: int)
signal leveled_up(new_level: int)
signal codex_entry_added(text: String)
signal campaign_gate_ready

const MAX_LEVEL := 5
const XP_PER_LEVEL := [0, 20, 45, 75, 110, 150]  # cumulative
const STAT_MAX := 100.0
const STAT_DECAY_PER_SEC := 0.15
const DAILY_CAP_BASE_XP := 10  # per action per hour before diminishing returns

var level: int = 1
var xp: int = 0
var energy: float = 80.0
var focus: float = 70.0
var mood: float = 75.0
var bond: int = 0
var campaign_ready: bool = false
var codex: Array[String] = []

# XP diminishing returns tracking
var _action_tap_counts: Dictionary = {"feed": 0, "pet": 0, "play": 0}
var _last_hour_reset: int = 0

# GDD §4.3.1 curriculum
const CURRICULUM := {
	1: "I start out knowing NOTHING — like a baby! I need training to learn. (AI starts blank)",
	2: "Feed me examples! That's called TRAINING DATA — I learn from examples, not instinct.",
	3: "When you Pet me for a good answer, that's FEEDBACK — I repeat what gets rewarded.",
	4: "Playing is PRACTICE — I get smarter by trying, failing, and trying again! I can use it on new stuff soon...",
	5: "I can GENERALIZE now! Show me your PDF reviewer and I'll turn it into gym battles!",
}

func _ready() -> void:
	_last_hour_reset = Time.get_unix_time_from_system()

func _process(delta: float) -> void:
	var drain := STAT_DECAY_PER_SEC * delta
	energy = maxf(0.0, energy - drain)
	focus = maxf(0.0, focus - drain * 0.8)
	mood = maxf(0.0, mood - drain * 0.6)
	stats_changed.emit()
	_maybe_reset_hourly_cap()

func _maybe_reset_hourly_cap() -> void:
	var now = Time.get_unix_time_from_system()
	if now - _last_hour_reset >= 3600:
		_action_tap_counts = {"feed": 0, "pet": 0, "play": 0}
		_last_hour_reset = now

func add_xp(amount: int) -> void:
	if campaign_ready and level >= MAX_LEVEL:
		return
	xp += amount
	_check_level_up()
	xp_changed.emit(xp, level)

func _check_level_up() -> void:
	while level < MAX_LEVEL and xp >= XP_PER_LEVEL[level]:
		level += 1
		_unlock_tidbit(level)
		leveled_up.emit(level)
		if level >= MAX_LEVEL:
			campaign_ready = true
			campaign_gate_ready.emit()

func _unlock_tidbit(lv: int) -> void:
	if CURRICULUM.has(lv):
		var text = CURRICULUM[lv]
		if not codex.has(text):
			codex.append(text)
			codex_entry_added.emit(text)

func care(action: String) -> Dictionary:
	var gained := 1
	var deltas := {}
	
	# Diminishing returns after DAILY_CAP_BASE_XP taps of same action this hour
	var count = _action_tap_counts.get(action, 0)
	_action_tap_counts[action] = count + 1
	
	var xp_mult = 1.0
	if count >= DAILY_CAP_BASE_XP:
		xp_mult = 0.3  # 30% XP after cap

	match action:
		"feed":
			energy = minf(STAT_MAX, energy + 8.0)
			deltas = {"energy": 8.0}
			gained = int(2 * xp_mult)
		"pet":
			mood = minf(STAT_MAX, mood + 8.0)
			deltas = {"mood": 8.0}
			gained = int(1 * xp_mult)
		"play":
			focus = minf(STAT_MAX, focus + 8.0)
			energy = maxf(0.0, energy - 2.0)
			deltas = {"focus": 8.0, "energy": -2.0}
			gained = int(2 * xp_mult)

	add_xp(gained)
	stats_changed.emit()
	bond += 1
	return {"xp": gained, "deltas": deltas, "action": action, "tap_count": count + 1}

func xp_for_next_level() -> int:
	if level >= MAX_LEVEL:
		return -1
	return XP_PER_LEVEL[level] - xp

func to_dict() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"energy": energy,
		"focus": focus,
		"mood": mood,
		"bond": bond,
		"campaign_ready": campaign_ready,
		"codex": codex,
	}

func from_dict(data: Dictionary) -> void:
	level = int(data.get("level", 1))
	xp = int(data.get("xp", 0))
	energy = float(data.get("energy", 80.0))
	focus = float(data.get("focus", 70.0))
	mood = float(data.get("mood", 75.0))
	bond = int(data.get("bond", 0))
	campaign_ready = bool(data.get("campaign_ready", false))
	codex.clear()
	for e in data.get("codex", []):
		codex.append(str(e))
	stats_changed.emit()
	xp_changed.emit(xp, level)