extends Node
## CompanionState — persistent companion data (Phase 2+)

signal stats_changed
signal xp_changed(current_xp: int, level: int)
signal leveled_up(new_level: int)
signal codex_entry_added(text: String)
signal campaign_gate_ready
signal pomodoro_phase_changed(mode: String)

const CAMPAIGN_UNLOCK_LEVEL := 5  # campaign gate stays here; levels themselves are unbounded.
# Cumulative XP to advance past `lvl` (threshold for level lvl+1).
# Matches verified pacing to Lv5 (deltas 20/25/30/35/40), then +5 XP/level forever.
static func xp_threshold(lvl: int) -> int:
	return 15 * lvl + 5 * lvl * (lvl + 1) / 2
const STAT_MAX := 100.0
const STAT_DECAY_PER_SEC := 0.15
const DAILY_CAP_BASE_XP := 10  # per action per hour before diminishing returns

# Pomodoro (Phase 4)
const POMODORO_FOCUS_SEC := 25 * 60
const POMODORO_REST_SEC := 5 * 60
const MISSED_REST_ENERGY_PENALTY := 5.0
const REST_COMPLETE_ENERGY_BONUS := 6.0

var level: int = 1
var xp: int = 0
var energy: float = 80.0  # Battery: drains over time, refilled by charging.
var focus: float = 70.0  # Cleanliness: gets dusty, cleaned with wipe/spray.
var integrity: float = 75.0  # Health: slow wear, fixed with repair tool.
var bond: int = 0
var campaign_ready: bool = false
var codex: Array[String] = []

# XP diminishing returns tracking
var _action_tap_counts: Dictionary = {"charge": 0, "wipe": 0, "spray": 0, "repair": 0}
var _last_hour_reset: int = 0

# Pomodoro state (Phase 4)
var _pomodoro_mode: String = ""  # "focus", "rest", ""
var _pomodoro_remaining: int = 0
var _pomodoro_timer: Timer
var _rest_missed: bool = false

# GDD §4.3.1 curriculum
const CURRICULUM := {
	1: "I start out knowing NOTHING — like a baby! I need training to learn. (AI starts blank)",
	2: "Feed me examples! That's called TRAINING DATA — I learn from examples, not instinct.",
	3: "Good care is FEEDBACK — keep my batteries up and I repeat what works.",
	4: "Training is PRACTICE — I get smarter by trying, failing, and trying again! I can use it on new stuff soon...",
	5: "I can GENERALIZE now! Show me your PDF reviewer and I'll turn it into gym battles!",
}

func _ready() -> void:
	_last_hour_reset = int(Time.get_unix_time_from_system())
	_unlock_tidbit(1)

func _process(delta: float) -> void:
	var drain := STAT_DECAY_PER_SEC * delta
	energy = maxf(0.0, energy - drain)
	focus = maxf(0.0, focus - drain * 0.8)
	integrity = maxf(0.0, integrity - drain * 0.3)
	stats_changed.emit()
	_maybe_reset_hourly_cap()

func _maybe_reset_hourly_cap() -> void:
	var now := int(Time.get_unix_time_from_system())
	if now - _last_hour_reset >= 3600:
		_action_tap_counts = {"charge": 0, "wipe": 0, "spray": 0, "repair": 0}
		_last_hour_reset = now

func add_xp(amount: int) -> void:
	xp += amount
	_check_level_up()
	xp_changed.emit(xp, level)

func _check_level_up() -> void:
	while xp >= xp_threshold(level):
		level += 1
		_unlock_tidbit(level)
		leveled_up.emit(level)
		if level >= CAMPAIGN_UNLOCK_LEVEL and not campaign_ready:
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
		"charge":
			energy = minf(STAT_MAX, energy + 12.0)
			deltas = {"energy": 12.0}
			gained = int(2 * xp_mult)
		"wipe":
			focus = minf(STAT_MAX, focus + 8.0)
			deltas = {"focus": 8.0}
			gained = int(1 * xp_mult)
		"spray":
			focus = minf(STAT_MAX, focus + 14.0)
			deltas = {"focus": 14.0}
			gained = int(2 * xp_mult)
		"repair":
			integrity = minf(STAT_MAX, integrity + 12.0)
			deltas = {"integrity": 12.0}
			gained = int(2 * xp_mult)

	add_xp(gained)
	stats_changed.emit()
	bond += 1
	return {"xp": gained, "deltas": deltas, "action": action, "tap_count": count + 1}

func xp_for_next_level() -> int:
	return xp_threshold(level) - xp

func to_dict() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"energy": energy,
		"focus": focus,
		"integrity": integrity,
		"bond": bond,
		"campaign_ready": campaign_ready,
		"codex": codex,
	}

func from_dict(data: Dictionary) -> void:
	level = int(data.get("level", 1))
	xp = int(data.get("xp", 0))
	energy = float(data.get("energy", 80.0))
	focus = float(data.get("focus", 70.0))
	integrity = float(data.get("integrity", 75.0))
	bond = int(data.get("bond", 0))
	campaign_ready = bool(data.get("campaign_ready", false))
	codex.clear()
	for e in data.get("codex", []):
		codex.append(str(e))
	# Backfill: fresh games and older saves may miss early tidbits.
	for lv in range(1, level + 1):
		_unlock_tidbit(lv)
	# Reconcile: saves written at max level (or by older versions) may lack the flag.
	if level >= CAMPAIGN_UNLOCK_LEVEL and not campaign_ready:
		campaign_ready = true
	stats_changed.emit()
	xp_changed.emit(xp, level)

# --- Pomodoro (Phase 4) ---
func start_pomodoro() -> void:
	if _pomodoro_mode != "":
		return
	_pomodoro_mode = "focus"
	_pomodoro_remaining = POMODORO_FOCUS_SEC
	_pomodoro_timer = Timer.new()
	_pomodoro_timer.wait_time = 1.0
	_pomodoro_timer.autostart = true
	_pomodoro_timer.one_shot = false
	_pomodoro_timer.timeout.connect(_on_pomodoro_tick)
	add_child(_pomodoro_timer)
	_pomodoro_timer.start()
	_rest_missed = false
	stats_changed.emit()
	pomodoro_phase_changed.emit("focus")

func _on_pomodoro_tick() -> void:
	_pomodoro_remaining -= 1
	if _pomodoro_remaining <= 0:
		if _pomodoro_mode == "focus":
			# Focus ended -> rest begins
			_pomodoro_mode = "rest"
			_pomodoro_remaining = POMODORO_REST_SEC
			_rest_missed = false
			stats_changed.emit()
			pomodoro_phase_changed.emit("rest")
		else:
			# Rest ended naturally -> cycle complete, companion feels rested
			energy = minf(STAT_MAX, energy + REST_COMPLETE_ENERGY_BONUS)
			_stop_pomodoro()
			stats_changed.emit()
			pomodoro_phase_changed.emit("done")

func _stop_pomodoro() -> void:
	if is_instance_valid(_pomodoro_timer):
		_pomodoro_timer.stop()
		_pomodoro_timer.queue_free()
	_pomodoro_mode = ""
	_pomodoro_remaining = 0
	_rest_missed = false
	stats_changed.emit()

func skip_pomodoro() -> void:
	if _pomodoro_mode == "focus":
		# Skipping focus: soft penalty, go to rest
		_pomodoro_mode = "rest"
		_pomodoro_remaining = POMODORO_REST_SEC
		energy = maxf(0.0, energy - 3.0)
		stats_changed.emit()
		pomodoro_phase_changed.emit("rest")
	elif _pomodoro_mode == "rest":
		# Skipping rest: apply missed-rest penalty
		_apply_missed_rest_penalty()
		_stop_pomodoro()
		pomodoro_phase_changed.emit("")

func _apply_missed_rest_penalty() -> void:
	energy = maxf(0.0, energy - MISSED_REST_ENERGY_PENALTY)
	_rest_missed = true

func get_pomodoro_state() -> Dictionary:
	return {
		"mode": _pomodoro_mode,
		"remaining": _pomodoro_remaining,
		"focus_total": POMODORO_FOCUS_SEC,
		"rest_total": POMODORO_REST_SEC,
	}

func is_in_rest() -> bool:
	return _pomodoro_mode == "rest"