extends "res://scripts/ui/minigames/minigame.gd"
## Kuiz Keeper, Pou-style penalty shots: swipe the ball up at the goal and Kuiz, in goal, dives for
## it. The swipe's direction aims, its speed lifts the shot (the fastest sail over the bar). Ten
## shots a round; every goal makes Kuiz a little quicker. Contract: docs/ui-and-assets.md §2 Minigames.
##
## Smoothness: the ball flies at a steady speed in depth, so on screen it slows and shrinks into the
## distance (scale = 1 / depth) with a shadow on the grass; Kuiz steers with capped acceleration and
## eases to a stop; the next ball rolls in onto the spot instead of appearing there.

const SHOTS := 10
const CRYSTALS_PER_GOAL := 1
# The goal mouth (inside the posts), the penalty spot and Kuiz's head, in the backdrop's art
# (rooms/soccer_field.svg).
const GOAL_LEFT := 161.0
const GOAL_RIGHT := 559.0
const GOAL_TOP := 311.0
const GOAL_BASE := 526.0
const SPOT := Vector2(360, 1040)
const KEEPER_Y := 440.0
## Kuiz's stage scale on a 720-wide screen.
const KEEPER_SCALE := 0.3
const FLIGHT_TIME := 0.6
## The ball's scale as it reaches the goal (so the goal sits 1 / BALL_FAR times deeper than the
## spot), and how high its arc rises at the spot's depth (art px).
const BALL_FAR := 0.36
const ARC := 150.0
## Swipe speeds (px/s): slower is not a shot; at the top the ball clears the bar.
const MIN_SWIPE := 500.0
const MAX_SWIPE := 4500.0
## A press this far from the ball's centre (in ball radii) still picks it up; a flick this long
## (px) shoots before the finger lifts. The swipe speed is read over the last SWIPE_WINDOW seconds.
const GRAB_RADII := 1.8
const FLICK_LENGTH := 170.0
const SWIPE_WINDOW := 0.08
## Kuiz's top speed (art px/s), how hard it can speed up or brake, and how fast it leans.
const KEEPER_SPEED := 240.0
const SPEED_PER_GOAL := 20.0
const KEEPER_ACCEL := 2600.0
const LEAN := 0.0013
const LEAN_RATE := 12.0
const REACTION := Vector2(0.08, 0.26)
const SWAY := 0.3
const RESULT_TIME := 1.1
const ENTER_TIME := 0.38

@onready var ball: TextureRect = %SoccerBall
@onready var label: Label = %SoccerLabel
@onready var quit_btn: BaseButton = %SoccerQuit

var _shots := 0
var _goals := 0
var _best := 0
var _speed := KEEPER_SPEED
# enter (next ball rolling in), aim (on the spot), drag (finger on it), flight, result
var _state := "aim"
var _trail: Array = []
var _press := Vector2.ZERO
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0
var _react := 0.0
var _keeper := Vector2.ZERO
var _keeper_vel := Vector2.ZERO
var _keeper_target := Vector2.ZERO
var _sway := 0.0
var _spin := 0.0
var _ball_fx: Tween
var _shadow: Panel

func _ready() -> void:
	super._ready()
	quit_btn.pressed.connect(quit)
	ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ball.pivot_offset = ball.size / 2.0
	# A soft oval on the grass under the ball; it stays on the ground while the ball arcs.
	_shadow = Panel.new()
	var oval := StyleBoxFlat.new()
	oval.bg_color = Color(0.1608, 0.2196, 0.2275, 0.28)
	oval.set_corner_radius_all(64)
	_shadow.add_theme_stylebox_override("panel", oval)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.size = Vector2(ball.size.x * 0.9, ball.size.x * 0.28)
	_shadow.pivot_offset = _shadow.size / 2.0
	add_child(_shadow)
	move_child(_shadow, ball.get_index())

func _begin() -> void:
	_shots = 0
	_goals = 0
	_speed = KEEPER_SPEED
	peek.show_room("SoccerField")
	peek.act("Idle")
	_keeper = _art(Vector2(360, KEEPER_Y))
	_keeper_vel = Vector2.ZERO
	_keeper_target = _keeper
	_reset_ball()
	_refresh()
	playing = true

func _refresh() -> void:
	label.text = "Goals %d · Shots %d" % [_goals, SHOTS - _shots]

# The next ball rolls up from below the screen onto the spot, spinning, and is ready once it lands.
func _reset_ball() -> void:
	# The last shot's fade can still be running; left alone it would hide the new ball.
	if _ball_fx:
		_ball_fx.kill()
	_state = "enter"
	var spot := _art(SPOT)
	ball.modulate.a = 1.0
	ball.scale = Vector2.ONE
	ball.rotation = 0.0
	ball.position = Vector2(spot.x, _view().y + ball.size.y) - ball.size / 2.0
	_put_shadow(Vector2(spot.x, _view().y + ball.size.y), 1.0)
	_shadow.modulate.a = 1.0
	peek.look_ahead()
	var t := create_tween().set_parallel()
	_ball_fx = t
	t.tween_property(ball, "position", spot - ball.size / 2.0, ENTER_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(ball, "rotation", -TAU, ENTER_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(func(y: float) -> void: _put_shadow(Vector2(spot.x, y), 1.0), _view().y + ball.size.y, spot.y, ENTER_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(func() -> void:
		if _state == "enter":
			_state = "aim")

func _put_shadow(ground: Vector2, size: float) -> void:
	_shadow.scale = Vector2.ONE * size
	_shadow.position = ground + Vector2(0, ball.size.y * 0.42 * size) - _shadow.size / 2.0

# The press only has to land near the ball; a long enough flick shoots before the finger lifts.
func _input(event: InputEvent) -> void:
	if not playing:
		return
	if _state == "aim" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.distance_to(ball.position + ball.size / 2.0) < ball.size.x / 2.0 * GRAB_RADII:
			_state = "drag"
			_press = event.position
			_trail = [[event.position, _now()]]
	elif _state == "drag":
		if event is InputEventMouseMotion:
			_trail.append([event.position, _now()])
			if _press.y - event.position.y > FLICK_LENGTH:
				_shoot()
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_trail.append([event.position, _now()])
			_shoot()

# The swipe's velocity over its last few samples (or the whole swipe, if it was quicker).
func _swipe_velocity() -> Vector2:
	var b: Array = _trail[-1]
	var a: Array = _trail[0]
	for s: Array in _trail:
		if float(b[1]) - float(s[1]) <= SWIPE_WINDOW:
			a = s
			break
	if a == b and _trail.size() > 1:
		a = _trail[-2]
	return ((b[0] as Vector2) - (a[0] as Vector2)) / maxf(0.016, float(b[1]) - float(a[1]))

func _shoot() -> void:
	var v := _swipe_velocity()
	if -v.y < MIN_SWIPE:
		_state = "aim"
		return
	_from = ball.position + ball.size / 2.0
	var top := _art(Vector2(0, GOAL_TOP)).y
	var base := _art(Vector2(0, GOAL_BASE)).y
	# Aim: the swipe line carried on to the goal; lift: a faster swipe flies higher.
	var x := _from.x + v.x / -v.y * (_from.y - (top + base) / 2.0)
	var lift := clampf((v.length() - MIN_SWIPE) / (MAX_SWIPE - MIN_SWIPE), 0.0, 1.0)
	_to = Vector2(x, base - ball.size.y * BALL_FAR / 2.0 - lift * (base - top) * 1.1)
	_t = 0.0
	_spin = clampf(v.x / 120.0, -10.0, 10.0) + 16.0
	_shots += 1
	_state = "flight"
	_react = randf_range(REACTION.x, REACTION.y)
	# Kuiz guesses where the ball will cross, but only within the goal.
	var left := _art(Vector2(GOAL_LEFT, 0)).x
	var right := _art(Vector2(GOAL_RIGHT, 0)).x
	_keeper_target = Vector2(clampf(_to.x, left, right), clampf(_to.y, top + peek.head_radius() * 0.8, _art(Vector2(0, KEEPER_Y)).y))
	peek.voice.play("land", 0.8)
	_refresh()

# Where the ball is `k` of the way through its flight. It travels at a steady speed in depth, so
# on screen it covers less and less ground and shrinks as 1 / depth; the arc shrinks with it.
func _flight(k: float) -> Dictionary:
	var depth := lerpf(1.0, 1.0 / BALL_FAR, k)
	var near := (1.0 - 1.0 / depth) / (1.0 - BALL_FAR)
	var ground := _from.lerp(Vector2(_to.x, _art(Vector2(0, GOAL_BASE)).y), near)
	var line := _from.lerp(_to, near)
	var arc := 4.0 * k * (1.0 - k) * ARC * _art_scale() / depth
	return {"pos": line - Vector2(0, arc), "ground": ground, "scale": 1.0 / depth}

func _process(delta: float) -> void:
	if not visible:
		return
	var view_k := _art_scale()
	var goal := _keeper
	match _state:
		"enter", "aim", "drag":
			# Kuiz sways across the goal while it waits.
			_sway += delta
			goal = _art(Vector2(360 + sin(_sway * 1.4) * (GOAL_RIGHT - GOAL_LEFT) / 2.0 * SWAY, KEEPER_Y))
			_steer(goal, _speed * 0.5 * view_k, delta)
		"flight":
			_t += delta / FLIGHT_TIME
			var k := minf(_t, 1.0)
			var f := _flight(k)
			ball.scale = Vector2.ONE * f["scale"]
			ball.rotation += delta * _spin * f["scale"]
			ball.position = (f["pos"] as Vector2) - ball.size / 2.0
			_put_shadow(f["ground"], f["scale"])
			peek.look_at_point(f["pos"])
			if _t * FLIGHT_TIME > _react:
				_steer(_keeper_target, _speed * view_k, delta)
			else:
				_steer(_keeper, 0.0, delta)
			if k >= 1.0:
				_resolve()
		"result":
			_steer(_keeper, 0.0, delta)
	# Kuiz leans into its own motion, easing in and out (frame-rate independent).
	var lean := clampf(_keeper_vel.x * LEAN / view_k, -0.35, 0.35)
	peek.stage.rotation.z = lerpf(peek.stage.rotation.z, -lean, 1.0 - exp(-LEAN_RATE * delta))
	peek.place(_keeper, _kuiz_scale(KEEPER_SCALE))

# Arrive steering: head for `target` at up to `top_speed`, speeding up and braking at KEEPER_ACCEL,
# so Kuiz never starts or stops dead.
func _steer(target: Vector2, top_speed: float, delta: float) -> void:
	var accel := KEEPER_ACCEL * _art_scale()
	var to := target - _keeper
	var dist := to.length()
	var want := Vector2.ZERO
	if dist > 0.5:
		want = to / dist * minf(top_speed, sqrt(2.0 * accel * dist))
	_keeper_vel = _keeper_vel.move_toward(want, accel * delta)
	_keeper += _keeper_vel * delta

func _resolve() -> void:
	_state = "result"
	var r := ball.size.x * BALL_FAR / 2.0
	var left := _art(Vector2(GOAL_LEFT, 0)).x
	var right := _art(Vector2(GOAL_RIGHT, 0)).x
	var top := _art(Vector2(0, GOAL_TOP)).y
	var base := _art(Vector2(0, GOAL_BASE)).y
	var inside := _to.x > left + r and _to.x < right - r and _to.y > top + r
	var saved: bool = inside and _to.distance_to(peek.head_point()) < peek.head_radius() + r
	var t := create_tween()
	_ball_fx = t
	if saved:
		label.text = "Saved!"
		peek.act("Happy")
		# Punched away: out and down to the grass, bouncing once, growing as it comes closer.
		var away: Vector2 = _to + (_to - peek.head_point()).normalized() * 150.0 * _art_scale()
		var land := Vector2(away.x, base + 160.0 * _art_scale())
		t.set_parallel()
		t.tween_property(ball, "position:x", land.x - ball.size.x / 2.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(ball, "position:y", land.y - ball.size.y / 2.0, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.tween_property(ball, "scale", Vector2.ONE * 0.55, 0.55).set_trans(Tween.TRANS_SINE)
		t.tween_property(ball, "rotation", ball.rotation - TAU, 0.55).set_ease(Tween.EASE_OUT)
		t.tween_method(func(x: float) -> void: _put_shadow(Vector2(x, land.y), 0.55), _to.x, land.x, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	elif inside:
		_goals += 1
		_speed += SPEED_PER_GOAL
		label.text = "GOAL!"
		peek.act("Sad")
		peek.voice.play("confetti")
		# Into the net: it sinks back a little, then drops to the goal line and settles.
		t.set_parallel()
		t.tween_property(ball, "scale", Vector2.ONE * BALL_FAR * 0.85, 0.2).set_ease(Tween.EASE_OUT)
		t.tween_property(ball, "position:y", base - ball.size.y / 2.0 - r * 0.85, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.tween_property(ball, "rotation", ball.rotation + PI, 0.5).set_ease(Tween.EASE_OUT)
	else:
		label.text = "Missed!"
		peek.act("Happy")
		# Wide or over: it keeps going the way it flew, shrinking away.
		var dir := (_to - _from).normalized()
		t.set_parallel()
		t.tween_property(ball, "position", ball.position + dir * 140.0 * _art_scale(), 0.45).set_ease(Tween.EASE_OUT)
		t.tween_property(ball, "scale", Vector2.ONE * BALL_FAR * 0.7, 0.45).set_ease(Tween.EASE_OUT)
		t.tween_property(ball, "rotation", ball.rotation + TAU, 0.45).set_ease(Tween.EASE_OUT)
		t.tween_property(_shadow, "modulate:a", 0.0, 0.3)
	t.tween_property(ball, "modulate:a", 0.0, 0.35).set_delay(RESULT_TIME - 0.4).set_trans(Tween.TRANS_SINE)
	t.tween_property(_shadow, "modulate:a", 0.0, 0.35).set_delay(RESULT_TIME - 0.4)
	await get_tree().create_timer(RESULT_TIME).timeout
	if not playing:
		return
	if _shots >= SHOTS:
		_best = maxi(_best, _goals)
		_game_over("Great shooting!" if _goals * 2 >= SHOTS else "Nice try!",
			"%d of %d shots went in.\nBest this session: %d." % [_goals, SHOTS, _best], _goals * CRYSTALS_PER_GOAL)
		return
	_refresh()
	_reset_ball()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
