extends Node
## Phase 0: Global game state. Holds companion stats, XP/level, campaign gate.

signal stats_changed
signal xp_changed(current_xp: int, level: int)
signal leveled_up(new_level: int)
signal tidbit_unlocked(level: int, text: String)

const MAX_LEVEL := 5
const XP_PER_LEVEL := [0, 20, 45, 75, 110, 150] # cumulative thresholds; Lv5 unlocks campaign
const STAT_MAX := 100.0
const STAT_DECAY_PER_SEC := 0.15 # slow drain so care matters, not punishing in prototype

var level: int = 1
var xp: int = 0
var energy: float = 80.0
var focus: float = 70.0
var mood: float = 75.0
var campaign_unlocked: bool = false
var codex_entries: Array[String] = []

# GDD §4.3.1 curriculum: level -> tidbit text
const CURRICULUM := {
	1: "I start out knowing NOTHING — like a baby! I need training to learn. (AI starts blank)",
	2: "Feed me examples! That's called TRAINING DATA — I learn from examples, not instinct.",
	3: "When you Pet me for a good answer, that's FEEDBACK — I repeat what gets rewarded.",
	4: "Playing is PRACTICE — I get smarter by trying, failing, and trying again! I can use it on new stuff soon...",
	5: "I can GENERALIZE now! Show me your PDF reviewer and I'll turn it into gym battles!",
}

func _ready() -> void:
	unlock_tidbit(1)

func _process(delta: float) -> void:
	var drain := STAT_DECAY_PER_SEC * delta
	energy = maxf(0.0, energy - drain)
	focus = maxf(0.0, focus - drain * 0.8)
	mood = maxf(0.0, mood - drain * 0.6)
	# Throttle signal: only emit when visible change matters; companion UI polls anyway.

func add_xp(amount: int) -> void:
	if campaign_unlocked and level >= MAX_LEVEL:
		return
	xp += amount
	_check_level_up()
	xp_changed.emit(xp, level)

func _check_level_up() -> void:
	while level < MAX_LEVEL and xp >= int(XP_PER_LEVEL[level]):
		level += 1
		unlock_tidbit(level)
		leveled_up.emit(level)
		if level >= MAX_LEVEL:
			campaign_unlocked = true

func unlock_tidbit(lv: int) -> void:
	if CURRICULUM.has(lv):
		var text: String = CURRICULUM[lv]
		if not codex_entries.has(text):
			codex_entries.append(text)
			tidbit_unlocked.emit(lv, text)

func care(action: String) -> Dictionary:
	# Returns {xp, stat_deltas, tidbit} so UI can animate.
	var gained := 1
	var deltas := {}
	match action:
		"feed":
			energy = minf(STAT_MAX, energy + 8.0)
			deltas = {"energy": 8.0}
			gained = 2
		"pet":
			mood = minf(STAT_MAX, mood + 8.0)
			deltas = {"mood": 8.0}
			gained = 1
		"play":
			focus = minf(STAT_MAX, focus + 8.0)
			energy = maxf(0.0, energy - 2.0)
			deltas = {"focus": 8.0, "energy": -2.0}
			gained = 2
	add_xp(gained)
	stats_changed.emit()
	return {"xp": gained, "deltas": deltas}

func xp_for_next_level() -> int:
	if level >= MAX_LEVEL:
		return -1
	return int(XP_PER_LEVEL[level]) - xp
