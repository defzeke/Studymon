extends Node
## CompanionState — persistent companion data (Phase 2+)

signal stats_changed
signal xp_changed(current_xp: int, level: int)
signal leveled_up(new_level: int)
signal codex_entry_added(text: String)
signal pomodoro_phase_changed(mode: String)

# Levels never cap. See xp_to_reach().
# Each level costs 5 XP more than the one before: Lv1->2=20, 2->3=25, 3->4=30, 4->5=35, 5->6=40...
# At 1-2 XP per tap (feed 2, pet 1, play 2; avg ~1.66 cycling), ~65 taps to Lv5, a few minutes;
# meets GDD "minutes, not hours" for Levels 1-5.
const FIRST_LEVEL_XP := 20
const LEVEL_XP_STEP := 5
# Reaching a level pays this many crystals (flat, so care alone cannot outpace studying).
const LEVEL_CRYSTALS := 25
const STAT_MAX := 100.0
const STAT_DECAY_PER_SEC := 0.15
# The clock decay announces itself this often (issue #13); care actions announce at once.
const DECAY_EMIT_SEC := 0.2
const DAILY_CAP_BASE_XP := 10  # per action per hour before diminishing returns
# Past this many taps of one action in an hour it pays no XP at all, so care cannot be farmed forever.
const HOURLY_HARD_CAP := 30
# Home care (docs/systems/companion-care.md): food fills hunger, a fix restores health, a ball
# throw lifts mood, and charging refills energy over time.
const FEED_HUNGER := 12.0
const FIX_HEALTH := 25.0
const PLAY_MOOD := 8.0
const CHARGE_PER_SEC := 6.0
# Dirt builds up slowly (and a little with each meal and throw); the towel scrubs it off.
const DIRT_PER_SEC := 0.06
const MESS := 3.0
const CLEAN_MOOD := 5.0
# Battery health wears like a phone's: every point of energy charged costs BATTERY_WEAR health, and
# a worn battery drains faster (energy drain x 1 + (100 - health) / BATTERY_DRAIN_SPAN, so x2 at 50%).
# A new battery (crystals, the check-up tablet) restores 100%.
const BATTERY_WEAR := 0.02
const BATTERY_DRAIN_SPAN := 50.0
const BATTERY_PRICE := 30
# Playing a battle run moves the stats item by item instead of by the clock (decay is paused meanwhile).
# Contract: docs/systems/battle.md §3.
const PLAY_ENERGY := 0.5
const PLAY_HUNGER := 0.4
const PLAY_MOOD_RIGHT := 1.5
const PLAY_MOOD_WRONG := 0.3
# Each point of counter damage Kuiz takes costs this much health, never below HURT_FLOOR.
const HURT_HEALTH := 0.3
const HURT_FLOOR := 10.0

# Pomodoro (Phase 4)
const POMODORO_FOCUS_SEC := 25 * 60
const POMODORO_REST_SEC := 5 * 60
const MISSED_REST_ENERGY_PENALTY := 5.0
const MISSED_REST_MOOD_PENALTY := 3.0
const REST_COMPLETE_ENERGY_BONUS := 6.0
const REST_COMPLETE_MOOD_BONUS := 6.0
# A full 25-minute focus session sharpens Kuiz: focus is what forgives the first miss in a run.
const POMODORO_FOCUS_BONUS := 25.0

var level: int = 1
var xp: int = 0
var energy: float = 80.0
var focus: float = 70.0
var mood: float = 75.0
var hunger: float = 80.0
var health: float = 100.0
## 0 = spotless, 100 = filthy: shown as spots and scratches on Kuiz, cleaned with the towel.
var dirt: float = 0.0
## The battery's capacity left, 100 = new; lower drains energy faster.
var battery_health: float = 100.0
var bond: int = 0
## True while a battle run is on; the clock decay is paused.
var in_run := false
var _decay_emit_wait := 0.0
var codex: Array[String] = []

# XP diminishing returns tracking
var _action_tap_counts: Dictionary = {"feed": 0, "pet": 0, "play": 0, "fix": 0, "clean": 0}
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
	3: "When you Pet me for a good answer, that's FEEDBACK — I repeat what gets rewarded.",
	4: "Playing is PRACTICE — I get smarter by trying, failing, and trying again! I can use it on new stuff soon...",
	5: "I can GENERALIZE now! Show me your PDF reviewer and I'll turn it into gym battles!",
}

func _ready() -> void:
	_last_hour_reset = int(Time.get_unix_time_from_system())
	_unlock_tidbit(1)

func _process(delta: float) -> void:
	if in_run:
		dirt = minf(STAT_MAX, dirt + DIRT_PER_SEC * delta)
		return
	var drain := STAT_DECAY_PER_SEC * delta
	energy = maxf(0.0, energy - drain * battery_drain())
	focus = maxf(0.0, focus - drain * 0.8)
	mood = maxf(0.0, mood - drain * 0.6)
	hunger = maxf(0.0, hunger - drain * 0.7)
	health = maxf(0.0, health - drain * 0.2)
	dirt = minf(STAT_MAX, dirt + DIRT_PER_SEC * delta)
	_decay_emit_wait -= delta
	if _decay_emit_wait <= 0.0:
		_decay_emit_wait = DECAY_EMIT_SEC
		stats_changed.emit()
	_maybe_reset_hourly_cap()

func _maybe_reset_hourly_cap() -> void:
	var now := int(Time.get_unix_time_from_system())
	if now - _last_hour_reset >= 3600:
		_action_tap_counts = {"feed": 0, "pet": 0, "play": 0, "fix": 0, "clean": 0}
		_last_hour_reset = now

func add_xp(amount: int) -> void:
	xp += amount
	_check_level_up()
	xp_changed.emit(xp, level)

## Flashcard review (docs/systems/gameplay-structure.md §3.4): a card lifted a mastery step,
## and a finished deck. Each card pays once, so reviewing the same cards cannot farm XP.
func reward_card_banked() -> void:
	focus = minf(STAT_MAX, focus + 2.0)
	add_xp(1)

func reward_deck_done() -> void:
	mood = minf(STAT_MAX, mood + 3.0)

func _check_level_up() -> void:
	while xp >= xp_to_reach(level + 1):
		level += 1
		GameState.add_crystals(LEVEL_CRYSTALS)
		_unlock_tidbit(level)
		leveled_up.emit(level)

## Cumulative XP at which `lv` is reached (Lv1 = 0, Lv2 = 20, Lv5 = 110, Lv6 = 150...).
static func xp_to_reach(lv: int) -> int:
	var n := lv - 1
	return FIRST_LEVEL_XP * n + LEVEL_XP_STEP * n * (n - 1) / 2

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
			hunger = minf(STAT_MAX, hunger + FEED_HUNGER)
			deltas = {"hunger": FEED_HUNGER}
			gained = maxi(1, roundi(2 * xp_mult))
		"pet":
			mood = minf(STAT_MAX, mood + 8.0)
			deltas = {"mood": 8.0}
			gained = maxi(1, roundi(1 * xp_mult))
		"play":
			mood = minf(STAT_MAX, mood + PLAY_MOOD)
			energy = maxf(0.0, energy - 2.0)
			deltas = {"mood": PLAY_MOOD, "energy": -2.0}
			gained = maxi(1, roundi(2 * xp_mult))
		"fix":
			health = minf(STAT_MAX, health + FIX_HEALTH)
			deltas = {"health": FIX_HEALTH}
			gained = maxi(1, roundi(2 * xp_mult))
		"clean":
			# A finished scrub (the towel already took the dirt off): a happy, fresh Kuiz.
			mood = minf(STAT_MAX, mood + CLEAN_MOOD)
			deltas = {"mood": CLEAN_MOOD}
			gained = maxi(1, roundi(2 * xp_mult))

	if count >= HOURLY_HARD_CAP:
		gained = 0
	add_xp(gained)
	stats_changed.emit()
	bond += 1
	return {"xp": gained, "deltas": deltas, "action": action, "tap_count": count + 1}

## Home's Charge toggle: energy refills while Kuiz sleeps on the charger.
## The towel: scrubbing takes dirt off a little at a time.
func scrub(amount: float) -> void:
	dirt = maxf(0.0, dirt - amount)

## Meals and play leave a little mess.
func soil(amount := MESS) -> void:
	dirt = minf(STAT_MAX, dirt + amount)

func recharge(delta: float) -> void:
	var gained := minf(STAT_MAX - energy, CHARGE_PER_SEC * delta)
	energy += gained
	battery_health = maxf(0.0, battery_health - gained * BATTERY_WEAR)

## Battle readiness: each care stat has one job in a run. Contract: docs/systems/battle.md §Stats.
## Health sets Kuiz's battle HP.
func battle_max_hp() -> int:
	return roundi(lerpf(70.0, 120.0, health / STAT_MAX))

## Energy scales the XP a run pays.
func xp_mult() -> float:
	return lerpf(0.8, 1.2, energy / STAT_MAX)

## Mood scales the crystals a run pays.
func crystal_mult() -> float:
	return lerpf(0.8, 1.2, mood / STAT_MAX)

## Hunger softens the enemy's counters, by up to 20%.
func counter_mult() -> float:
	return 1.0 - 0.2 * hunger / STAT_MAX

## Focus 50+ forgives the first miss of a run: it does not break the streak.
func has_streak_shield() -> bool:
	return focus >= 50.0

## The four home stats averaged, 0 to 100.
func readiness() -> float:
	return (hunger + energy + mood + health) / 4.0

## One battle item played: it tires and hungers Kuiz a little, and the fun lifts its mood (more when right).
func play_item(correct: bool) -> void:
	energy = maxf(0.0, energy - PLAY_ENERGY)
	hunger = maxf(0.0, hunger - PLAY_HUNGER)
	mood = minf(STAT_MAX, mood + (PLAY_MOOD_RIGHT if correct else PLAY_MOOD_WRONG))
	stats_changed.emit()

## Kuiz took a counter in battle: its health drops, but a battle never takes it below HURT_FLOOR.
func hurt(counter: float) -> void:
	health = maxf(minf(health, HURT_FLOOR), health - counter * HURT_HEALTH)
	stats_changed.emit()

## How much faster than new the battery drains (1 at 100% health).
func battery_drain() -> float:
	return 1.0 + (STAT_MAX - battery_health) / BATTERY_DRAIN_SPAN

## The check-up tablet's battery swap: false (nothing spent) without enough crystals.
func replace_battery() -> bool:
	if GameState.crystals < BATTERY_PRICE:
		return false
	GameState.add_crystals(-BATTERY_PRICE)
	battery_health = STAT_MAX
	stats_changed.emit()
	return true

func xp_for_next_level() -> int:
	return xp_to_reach(level + 1) - xp

func to_dict() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"energy": energy,
		"focus": focus,
		"mood": mood,
		"hunger": hunger,
		"health": health,
		"dirt": dirt,
		"battery_health": battery_health,
		"bond": bond,
		"codex": codex,
	}

func from_dict(data: Dictionary) -> void:
	level = int(data.get("level", 1))
	xp = int(data.get("xp", 0))
	energy = float(data.get("energy", 80.0))
	focus = float(data.get("focus", 70.0))
	mood = float(data.get("mood", 75.0))
	hunger = float(data.get("hunger", 80.0))
	health = float(data.get("health", 100.0))
	dirt = float(data.get("dirt", 0.0))
	battery_health = float(data.get("battery_health", 100.0))
	bond = int(data.get("bond", 0))
	codex.clear()
	for e in data.get("codex", []):
		codex.append(str(e))
	# Backfill: fresh games and older saves may miss early tidbits.
	for lv in range(1, level + 1):
		_unlock_tidbit(lv)
	# Saves from the capped curve (Lv5 max) may hold XP past Lv5: catch the levels up silently.
	while xp >= xp_to_reach(level + 1):
		level += 1
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
			focus = minf(STAT_MAX, focus + POMODORO_FOCUS_BONUS)
			_pomodoro_mode = "rest"
			_pomodoro_remaining = POMODORO_REST_SEC
			_rest_missed = false
			stats_changed.emit()
			pomodoro_phase_changed.emit("rest")
		else:
			# Rest ended naturally -> cycle complete, companion feels rested
			energy = minf(STAT_MAX, energy + REST_COMPLETE_ENERGY_BONUS)
			mood = minf(STAT_MAX, mood + REST_COMPLETE_MOOD_BONUS)
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
		mood = maxf(0.0, mood - 2.0)
		stats_changed.emit()
		pomodoro_phase_changed.emit("rest")
	elif _pomodoro_mode == "rest":
		# Skipping rest: apply missed-rest penalty
		_apply_missed_rest_penalty()
		_stop_pomodoro()
		pomodoro_phase_changed.emit("")

func _apply_missed_rest_penalty() -> void:
	energy = maxf(0.0, energy - MISSED_REST_ENERGY_PENALTY)
	mood = maxf(0.0, mood - MISSED_REST_MOOD_PENALTY)
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