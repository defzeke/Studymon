extends Node
## Kuiz's care stats, XP and level, and the focus timer. Contract: docs/systems/companion-care.md.

signal stats_changed
signal xp_changed(current_xp: int, level: int)
signal pomodoro_phase_changed(mode: String)

# Levels never cap. See xp_to_reach().
# Each level costs 5 XP more than the one before: Lv1->2=20, 2->3=25, 3->4=30, 4->5=35, 5->6=40...
# At 1-2 XP per tap (feed 2, pet 1, play 2; avg ~1.66 cycling), ~65 taps to Lv5, a few minutes;
# Levels 1-5 take minutes, not hours.
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

# The focus timer. The player's choice of lengths (minutes): the defaults, and what the timer panel allows.
const POMODORO_FOCUS_MIN := 25
const POMODORO_REST_MIN := 5
const POMODORO_FOCUS_RANGE := Vector3i(5, 60, 5)
const POMODORO_REST_RANGE := Vector3i(1, 30, 1)
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
## True while a battle run is on; the clock decay is paused.
var in_run := false
var _decay_emit_wait := 0.0

# Taps of each care action this hour, for the XP caps.
var _action_tap_counts: Dictionary = {"feed": 0, "pet": 0, "play": 0, "fix": 0, "clean": 0}
var _last_hour_reset: int = 0

var _pomodoro_mode: String = ""  # "focus", "rest", ""
var _pomodoro_remaining: int = 0
var _pomodoro_timer: Timer
var _pomodoro_last_tick := 0
## Saved: the length the next focus and break run for, in minutes.
var focus_minutes := POMODORO_FOCUS_MIN
var rest_minutes := POMODORO_REST_MIN

func _ready() -> void:
	_last_hour_reset = int(Time.get_unix_time_from_system())

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

## Cumulative XP at which `lv` is reached (Lv1 = 0, Lv2 = 20, Lv5 = 110, Lv6 = 150...).
static func xp_to_reach(lv: int) -> int:
	var n := lv - 1
	return FIRST_LEVEL_XP * n + LEVEL_XP_STEP * n * (n - 1) / 2

## A care action raises its stat and pays XP. `food` (feed only) is the meal eaten; without one a
## meal fills FEED_HUNGER.
func care(action: String, food: FoodItem = null) -> void:
	var gained := 1
	# Past DAILY_CAP_BASE_XP taps of one action this hour it pays 30 % XP.
	var count: int = _action_tap_counts.get(action, 0)
	_action_tap_counts[action] = count + 1
	var xp_mult := 0.3 if count >= DAILY_CAP_BASE_XP else 1.0
	match action:
		"feed":
			hunger = minf(STAT_MAX, hunger + (food.hunger if food else FEED_HUNGER))
			if food:
				mood = minf(STAT_MAX, mood + food.mood)
				focus = minf(STAT_MAX, focus + food.focus)
			gained = maxi(1, roundi(2 * xp_mult))
		"pet":
			mood = minf(STAT_MAX, mood + 8.0)
			gained = maxi(1, roundi(1 * xp_mult))
		"play":
			mood = minf(STAT_MAX, mood + PLAY_MOOD)
			energy = maxf(0.0, energy - 2.0)
			gained = maxi(1, roundi(2 * xp_mult))
		"fix":
			health = minf(STAT_MAX, health + FIX_HEALTH)
			gained = maxi(1, roundi(2 * xp_mult))
		"clean":
			# A finished scrub (the towel already took the dirt off): a happy, fresh Kuiz.
			mood = minf(STAT_MAX, mood + CLEAN_MOOD)
			gained = maxi(1, roundi(2 * xp_mult))
	if count >= HOURLY_HARD_CAP:
		gained = 0
	add_xp(gained)
	stats_changed.emit()

## The towel: scrubbing takes dirt off a little at a time.
func scrub(amount: float) -> void:
	dirt = maxf(0.0, dirt - amount)

## Meals and play leave a little mess.
func soil(amount := MESS) -> void:
	dirt = minf(STAT_MAX, dirt + amount)

## Home's Charge toggle: energy refills while Kuiz sleeps on the charger, wearing the battery.
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
		"focus_minutes": focus_minutes,
		"rest_minutes": rest_minutes,
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
	focus_minutes = _stepped(int(data.get("focus_minutes", POMODORO_FOCUS_MIN)), POMODORO_FOCUS_RANGE)
	rest_minutes = _stepped(int(data.get("rest_minutes", POMODORO_REST_MIN)), POMODORO_REST_RANGE)
	# Saves from the capped curve (Lv5 max) may hold XP past Lv5: catch the levels up silently.
	while xp >= xp_to_reach(level + 1):
		level += 1
	stats_changed.emit()
	xp_changed.emit(xp, level)

## Moves the next focus or break length by `steps`, staying on the panel's range (x min, y max, z step).
func step_focus_minutes(steps: int) -> void:
	focus_minutes = _stepped(focus_minutes + steps * POMODORO_FOCUS_RANGE.z, POMODORO_FOCUS_RANGE)

func step_rest_minutes(steps: int) -> void:
	rest_minutes = _stepped(rest_minutes + steps * POMODORO_REST_RANGE.z, POMODORO_REST_RANGE)

func _stepped(minutes: int, range_: Vector3i) -> int:
	return clampi(snappedi(minutes, range_.z), range_.x, range_.y)

func start_pomodoro() -> void:
	if _pomodoro_mode != "":
		return
	_pomodoro_mode = "focus"
	_pomodoro_remaining = focus_minutes * 60
	_pomodoro_last_tick = int(Time.get_unix_time_from_system())
	_pomodoro_timer = Timer.new()
	_pomodoro_timer.wait_time = 1.0
	_pomodoro_timer.autostart = true
	_pomodoro_timer.one_shot = false
	_pomodoro_timer.timeout.connect(_on_pomodoro_tick)
	add_child(_pomodoro_timer)
	_pomodoro_timer.start()
	stats_changed.emit()
	pomodoro_phase_changed.emit("focus")

# shortcut: time away counts toward the current phase only, carry it into the next if a full cycle while locked matters
func _on_pomodoro_tick() -> void:
	# A locked phone stops the Timer, so count from the clock.
	var now := int(Time.get_unix_time_from_system())
	_pomodoro_remaining -= maxi(1, now - _pomodoro_last_tick)
	_pomodoro_last_tick = now
	if _pomodoro_remaining <= 0:
		if _pomodoro_mode == "focus":
			# Focus ended -> rest begins
			# Rewards scale with the chosen length, so short sessions cannot farm them.
			focus = minf(STAT_MAX, focus + POMODORO_FOCUS_BONUS * focus_minutes / POMODORO_FOCUS_MIN)
			_pomodoro_mode = "rest"
			_pomodoro_remaining = rest_minutes * 60
			stats_changed.emit()
			pomodoro_phase_changed.emit("rest")
		else:
			# Rest ended naturally -> cycle complete, companion feels rested
			var rested := minf(1.0, float(rest_minutes) / POMODORO_REST_MIN)
			energy = minf(STAT_MAX, energy + REST_COMPLETE_ENERGY_BONUS * rested)
			mood = minf(STAT_MAX, mood + REST_COMPLETE_MOOD_BONUS * rested)
			_stop_pomodoro()
			stats_changed.emit()
			pomodoro_phase_changed.emit("done")

func _stop_pomodoro() -> void:
	if is_instance_valid(_pomodoro_timer):
		_pomodoro_timer.stop()
		_pomodoro_timer.queue_free()
	_pomodoro_mode = ""
	_pomodoro_remaining = 0
	stats_changed.emit()

func skip_pomodoro() -> void:
	if _pomodoro_mode == "focus":
		# Skipping focus: soft penalty, go to rest
		_pomodoro_mode = "rest"
		_pomodoro_remaining = rest_minutes * 60
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

func get_pomodoro_state() -> Dictionary:
	return {
		"mode": _pomodoro_mode,
		"remaining": _pomodoro_remaining,
		"focus_total": focus_minutes * 60,
		"rest_total": rest_minutes * 60,
	}