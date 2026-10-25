extends "res://scripts/ui/minigames/minigame.gd"
## Sky Jump, Pou-style: Kuiz bounces on its own from platform to platform; hold or drag left and
## right (or the arrow keys) to steer, and walking off one side brings Kuiz in from the other. The
## view climbs with Kuiz; falling off the bottom ends the round. Higher up the sky mixes in moving
## platforms, timed platforms that drop a moment after Kuiz lands on them, trampolines that launch
## Kuiz extra high, and rockets that carry it up for a while. The climb passes through zones (Sky,
## Space, Galaxy, Deep Space), each with its own backdrop and platforms; it gets harder with height
## and from Space up meteors knock Kuiz down. Contract: docs/ui-and-assets.md §2 Minigames.

const PLATFORM_TIMED: Texture2D = preload("res://assets/sprites/props/platform_timed.svg")
const TRAMPOLINE: Texture2D = preload("res://assets/sprites/props/trampoline.svg")
const ROCKET: Texture2D = preload("res://assets/sprites/props/rocket.svg")
const METEOR: Texture2D = preload("res://assets/sprites/props/meteor.svg")
const STARS: Texture2D = preload("res://assets/sprites/props/stars.svg")
## The zones, by the height (m) they start at. Sky's backdrop is the scene's own Sky node.
const ZONES := [
	{"from": 0, "name": "Sky", "platform": preload("res://assets/sprites/props/platform.svg"), "backdrop": null},
	{"from": 300, "name": "Space!", "platform": preload("res://assets/sprites/props/platform_space.svg"), "backdrop": preload("res://assets/sprites/rooms/sky_space.svg")},
	{"from": 900, "name": "Galaxy!", "platform": preload("res://assets/sprites/props/platform_galaxy.svg"), "backdrop": preload("res://assets/sprites/rooms/sky_galaxy.svg")},
	{"from": 1800, "name": "Deep Space!", "platform": preload("res://assets/sprites/props/platform_deep.svg"), "backdrop": preload("res://assets/sprites/rooms/sky_deep.svg")},
]
const ZONE_FADE := 1.2
const BANNER_TIME := 1.4
## The star layer scrolls at this share of the world's speed, so it reads as far away.
const STAR_PARALLAX := 0.25
## Kuiz's stage scale; the world is in screen pixels, y down.
const KUIZ_SCALE := 0.24
const GRAVITY := 2300.0
const JUMP := 1320.0
const STEER := 1000.0
## Platform art is 220x70 with its walkable top at y 8 (the timed one at 14); platforms keep that
## shape as they narrow.
const PLATFORM_ART := Vector2(220, 70)
const TOP_SHARE := 8.0 / 70.0
const TIMED_TOP_SHARE := 14.0 / 70.0
const GROUND_ART := Vector2(720, 400)
const GROUND_TOP := 154.0
## Difficulty grows over the first HARD_AT metres, then holds.
const HARD_AT := 2000.0
const WIDTH := Vector2(180, 120)
## Vertical gap between platforms: both ends widen with height, always under a jump's apex
## (1320² / (2·2300) ≈ 378 px), so every next platform stays reachable.
const GAP_MIN := Vector2(150, 215)
const GAP_START := 240.0
const GAP_CAP := 330.0
const GAP_PER_M := 0.08
## Kuiz is kept at or below this share of the screen height; the world scrolls instead.
const CAMERA_LINE := 0.42
const PX_PER_M := 10.0
## A round pays one crystal per this many metres climbed.
const METRES_PER_CRYSTAL := 50
## Specials: the height (m) each starts at and its chance per platform (easy -> hard).
const MOVING_FROM := 30
const MOVING_CHANCE := Vector2(0.22, 0.4)
const MOVING_SPEED := Vector2(110, 210)
const TIMED_FROM := 15
const TIMED_CHANCE := 0.22
## A timed platform shakes for this long after Kuiz first lands on it, then drops (easy -> hard).
const TIMED_LIFE := Vector2(0.9, 0.5)
const TRAMPOLINE_FROM := 5
const TRAMPOLINE_CHANCE := 0.14
const TRAMPOLINE_SIZE := Vector2(76, 44)
const TRAMPOLINE_JUMP := 2250.0
const ROCKET_FROM := 40
const ROCKET_CHANCE := Vector2(0.05, 0.08)
const ROCKET_SIZE := Vector2(50, 80)
const ROCKET_TIME := 1.7
const ROCKET_SPEED := 1900.0
## Meteors (from Space up): seconds between them (easy -> hard), size, speed, and the knock-down.
const METEOR_FROM := 300
const METEOR_EVERY := Vector2(3.2, 1.5)
const METEOR_SIZE := Vector2(96, 96)
const METEOR_VX := Vector2(120, 260)
const METEOR_VY := Vector2(420, 560)
const KNOCK_VY := 500.0
const KNOCK_VX := 380.0
const STUN_TIME := 0.8

@onready var world: Control = %JumpWorld
@onready var ground: TextureRect = %Ground
@onready var label: Label = %JumpLabel
@onready var quit_btn: BaseButton = %JumpQuit

var _pos := Vector2.ZERO
var _vel := Vector2.ZERO
var _scroll := 0.0
# Each platform is a TextureRect; its metadata says what kind it is: "kind" (plain, moving, timed),
# "top" (walkable top below its rect top), "vx" for moving ones, "life_total" / "life" for a timed
# one (counting once landed on), "vy" once it falls, and "spring" for the trampoline on it.
var _platforms: Array[TextureRect] = []
var _rockets: Array[TextureRect] = []
# Meteors carry their velocity in the "v" metadata.
var _meteors: Array[TextureRect] = []
var _top_y := 0.0
var _start_y := 0.0
var _height := 0
var _best := 0
var _finger := -1.0
var _rocket_left := 0.0
var _flame: TextureRect
var _zone := 0
var _backdrops: Array[TextureRect] = []
var _stars: Array[TextureRect] = []
var _banner := ""
var _banner_left := 0.0
var _meteor_wait := 0.0
var _stun_left := 0.0

func _ready() -> void:
	super._ready()
	quit_btn.pressed.connect(quit)
	_flame = TextureRect.new()
	_flame.texture = ROCKET
	_flame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flame.size = ROCKET_SIZE * 1.4
	_flame.visible = false
	# Over the platforms (still behind the 3D Kuiz, since the whole world is behind it).
	_flame.z_index = 1
	world.add_child(_flame)
	# The zone backdrops and the star layer sit in the SkyJump backdrop between Sky and the world;
	# a later zone draws over an earlier one, so each fades in on top.
	var backdrop := world.get_parent()
	for zone: Dictionary in ZONES.slice(1):
		var b := TextureRect.new()
		b.texture = zone["backdrop"]
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.modulate.a = 0.0
		backdrop.add_child(b)
		backdrop.move_child(b, world.get_index())
		_backdrops.append(b)
	for i in 2:
		var s := TextureRect.new()
		s.texture = STARS
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.modulate.a = 0.0
		backdrop.add_child(s)
		backdrop.move_child(s, world.get_index())
		_stars.append(s)

func _begin() -> void:
	for p in _platforms + _rockets + _meteors:
		p.queue_free()
	_platforms.clear()
	_rockets.clear()
	_meteors.clear()
	var view := _view()
	_scroll = 0.0
	world.position = Vector2.ZERO
	ground.size = Vector2(view.x, view.x * GROUND_ART.y / GROUND_ART.x)
	ground.position = Vector2(0, view.y - ground.size.y * 0.8)
	_top_y = _ground_top()
	_zone = 0
	for b in _backdrops:
		b.modulate.a = 0.0
	for s in _stars:
		s.size = Vector2(view.x, view.x * STARS.get_height() / STARS.get_width())
		s.modulate.a = 0.0
	_banner_left = 0.0
	_meteor_wait = METEOR_EVERY.x
	_stun_left = 0.0
	peek.show_room("SkyJump")
	peek.shadow.visible = false
	peek.look_ahead()
	peek.act("Idle")
	peek.place(Vector2(view.x / 2.0, _top_y), KUIZ_SCALE)
	_pos = Vector2(view.x / 2.0, _top_y - _feet())
	_start_y = _pos.y
	_vel = Vector2(0, -JUMP)
	_height = 0
	_finger = -1.0
	_rocket_left = 0.0
	_flame.visible = false
	while _top_y > -view.y:
		_spawn()
	_refresh()
	playing = true

func _refresh() -> void:
	label.text = _banner if _banner_left > 0.0 else "%d m" % _height

func _ground_top() -> float:
	return ground.position.y + GROUND_TOP * ground.size.x / GROUND_ART.x

# From Kuiz's head centre down to where it lands.
func _feet() -> float:
	return peek.head_radius() * 0.82

# The height (m) a world y sits at, for choosing what spawns there.
func _metres(y: float) -> int:
	return int((_start_y - y) / PX_PER_M)

# 0 at the start, 1 from HARD_AT metres up.
func _hard(m: float) -> float:
	return clampf(m / HARD_AT, 0.0, 1.0)

func _zone_at(m: int) -> int:
	var z := 0
	for i in ZONES.size():
		if m >= ZONES[i]["from"]:
			z = i
	return z

func _spawn() -> void:
	var view := _view()
	var hard := _hard(_metres(_top_y))
	var gap := minf(GAP_CAP, GAP_START + _metres(_top_y) * GAP_PER_M)
	_top_y -= randf_range(lerpf(GAP_MIN.x, GAP_MIN.y, hard), maxf(gap, GAP_MIN.y))
	var m := _metres(_top_y)
	hard = _hard(m)
	var kind := "plain"
	var roll := randf()
	if m >= TIMED_FROM and roll < TIMED_CHANCE:
		kind = "timed"
	elif m >= MOVING_FROM and roll < TIMED_CHANCE + lerpf(MOVING_CHANCE.x, MOVING_CHANCE.y, hard):
		kind = "moving"
	var w := lerpf(WIDTH.x, WIDTH.y, hard)
	var size := Vector2(w, w * PLATFORM_ART.y / PLATFORM_ART.x)
	var top := size.y * (TIMED_TOP_SHARE if kind == "timed" else TOP_SHARE)
	var p := _sprite(PLATFORM_TIMED if kind == "timed" else ZONES[_zone_at(m)]["platform"], size)
	p.position = Vector2(randf_range(12.0, view.x - size.x - 12.0), _top_y - top)
	p.pivot_offset = size / 2.0
	p.set_meta("kind", kind)
	p.set_meta("top", top)
	if kind == "moving":
		var speed := randf_range(MOVING_SPEED.x, MOVING_SPEED.y) * (1.0 + hard)
		p.set_meta("vx", speed * (1.0 if randf() < 0.5 else -1.0))
	elif kind == "timed":
		p.set_meta("life_total", lerpf(TIMED_LIFE.x, TIMED_LIFE.y, hard))
	world.add_child(p)
	_platforms.append(p)
	if kind != "timed" and m >= TRAMPOLINE_FROM and randf() < TRAMPOLINE_CHANCE:
		var spring := _sprite(TRAMPOLINE, TRAMPOLINE_SIZE)
		spring.position = Vector2(randf_range(6.0, maxf(6.0, size.x - TRAMPOLINE_SIZE.x - 6.0)), top - TRAMPOLINE_SIZE.y + 8.0)
		spring.pivot_offset = Vector2(TRAMPOLINE_SIZE.x / 2.0, TRAMPOLINE_SIZE.y)
		p.add_child(spring)
		p.set_meta("spring", spring)
	elif m >= ROCKET_FROM and randf() < lerpf(ROCKET_CHANCE.x, ROCKET_CHANCE.y, hard):
		var r := _sprite(ROCKET, ROCKET_SIZE)
		r.position = p.position + Vector2(size.x / 2.0 - ROCKET_SIZE.x / 2.0, -ROCKET_SIZE.y - 40.0)
		world.add_child(r)
		_rockets.append(r)

func _sprite(tex: Texture2D, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size = size
	return t

func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_finger = event.position.x if event.pressed else -1.0
	elif event is InputEventMouseMotion and _finger >= 0.0:
		_finger = event.position.x

func _process(delta: float) -> void:
	if not visible or not playing:
		return
	var view := _view()
	_steer(delta, view)
	var feet := _feet()
	if _rocket_left > 0.0:
		_rocket_left -= delta
		_vel.y = -ROCKET_SPEED
		_pos.y += _vel.y * delta
		if _rocket_left <= 0.0:
			_flame.visible = false
			_vel.y = -JUMP * 0.6
	else:
		var was := _pos.y + feet
		_vel.y += GRAVITY * delta
		_pos.y += _vel.y * delta
		if _vel.y > 0.0:
			_land(was, _pos.y + feet, feet)
	_stun_left -= delta
	_banner_left -= delta
	_move_platforms(delta, view)
	_pick_rockets(feet)
	_height = maxi(_height, _metres(_pos.y))
	_update_zone()
	_scroll = maxf(_scroll, view.y * CAMERA_LINE - _pos.y)
	world.position.y = _scroll
	_move_stars()
	_meteors_step(delta, view, feet)
	while _top_y + _scroll > -PLATFORM_ART.y:
		_spawn()
	for p in _platforms.duplicate():
		if p.position.y + _scroll > view.y + PLATFORM_ART.y:
			_platforms.erase(p)
			p.queue_free()
	for r in _rockets.duplicate():
		if r.position.y + _scroll > view.y + ROCKET_SIZE.y:
			_rockets.erase(r)
			r.queue_free()
	var screen := Vector2(_pos.x, _pos.y + _scroll)
	peek.stage.rotation.z = lerpf(peek.stage.rotation.z, -_vel.x * 0.00035, minf(1.0, 10.0 * delta))
	peek.place(screen, KUIZ_SCALE)
	if _flame.visible:
		_flame.position = _pos + Vector2(-_flame.size.x / 2.0, feet * 0.45)
	_refresh()
	if screen.y - feet > view.y:
		_best = maxi(_best, _height)
		peek.act("Sad")
		_game_over("Kuiz fell!", "Kuiz reached %d m.\nBest this session: %d m." % [_height, _best], _height / METRES_PER_CRYSTAL)

# Climbing into a new zone fades its backdrop in over the last one and names it on the HUD pill.
func _update_zone() -> void:
	var z := _zone_at(_height)
	if z <= _zone:
		return
	_zone = z
	var t := create_tween().set_parallel()
	t.tween_property(_backdrops[z - 1], "modulate:a", 1.0, ZONE_FADE)
	for s in _stars:
		t.tween_property(s, "modulate:a", 1.0, ZONE_FADE)
	_banner = ZONES[z]["name"]
	_banner_left = BANNER_TIME
	peek.voice.play("shimmer")

# Two copies of the star tile, stacked, wrap as the world climbs.
func _move_stars() -> void:
	var h := _stars[0].size.y
	var y := fposmod(_scroll * STAR_PARALLAX, h)
	_stars[0].position = Vector2(0, y - h)
	_stars[1].position = Vector2(0, y)

func _steer(delta: float, view: Vector2) -> void:
	var axis := Input.get_axis("ui_left", "ui_right")
	if axis != 0.0:
		_vel.x = axis * STEER * 0.7
	elif _finger >= 0.0:
		_vel.x = clampf((_finger - _pos.x) * 8.0, -STEER, STEER)
	else:
		_vel.x = move_toward(_vel.x, 0.0, 3000.0 * delta)
	_pos.x = wrapf(_pos.x + _vel.x * delta, 0.0, view.x)

# From Space up, meteors enter at the top and cross the screen diagonally. One that touches Kuiz
# knocks it down (not out); a rocket smashes them instead.
func _meteors_step(delta: float, view: Vector2, feet: float) -> void:
	if _height >= METEOR_FROM:
		_meteor_wait -= delta
		if _meteor_wait <= 0.0:
			var hard := clampf(float(_height - METEOR_FROM) / (HARD_AT - METEOR_FROM), 0.0, 1.0)
			_meteor_wait = lerpf(METEOR_EVERY.x, METEOR_EVERY.y, hard) * randf_range(0.7, 1.3)
			_spawn_meteor(view)
	for m: TextureRect in _meteors.duplicate():
		var v: Vector2 = m.get_meta("v")
		m.position += v * delta
		m.rotation += delta * 2.0
		var centre := m.position + m.size / 2.0
		var screen_y := centre.y + _scroll
		if screen_y > view.y + m.size.y or centre.x < -m.size.x * 2.0 or centre.x > view.x + m.size.x * 2.0:
			_meteors.erase(m)
			m.queue_free()
			continue
		if centre.distance_to(_pos) < feet * 0.8 + m.size.x * 0.3:
			if _rocket_left > 0.0:
				_meteors.erase(m)
				m.queue_free()
				peek.voice.play("land")
			elif _stun_left <= 0.0:
				_stun_left = STUN_TIME
				_vel.y = KNOCK_VY
				_vel.x = KNOCK_VX * signf(v.x)
				peek.act("Surprised")
				peek.voice.play("glitch")
				var t := create_tween()
				t.tween_property(m, "modulate:a", 0.0, 0.3)
				t.tween_callback(func() -> void:
					_meteors.erase(m)
					m.queue_free())

func _spawn_meteor(view: Vector2) -> void:
	var m := _sprite(METEOR, METEOR_SIZE)
	m.pivot_offset = METEOR_SIZE / 2.0
	var x := randf_range(0.0, view.x)
	var dir := 1.0 if x < view.x / 2.0 else -1.0
	# The art falls down and to the right; mirrored for the other way.
	m.flip_h = dir < 0.0
	m.position = Vector2(x - METEOR_SIZE.x / 2.0, -_scroll - METEOR_SIZE.y * 1.5)
	m.set_meta("v", Vector2(randf_range(METEOR_VX.x, METEOR_VX.y) * dir, randf_range(METEOR_VY.x, METEOR_VY.y)))
	m.z_index = 1
	world.add_child(m)
	_meteors.append(m)

# Moving platforms slide between the screen edges; a timed one counts down once landed on, shakes,
# then drops and fades.
func _move_platforms(delta: float, view: Vector2) -> void:
	for p in _platforms:
		if p.has_meta("vx"):
			var vx: float = p.get_meta("vx")
			p.position.x += vx * delta
			if p.position.x < 0.0 or p.position.x > view.x - p.size.x:
				p.position.x = clampf(p.position.x, 0.0, view.x - p.size.x)
				p.set_meta("vx", -vx)
		if p.has_meta("vy"):
			var vy: float = p.get_meta("vy") + GRAVITY * 0.6 * delta
			p.set_meta("vy", vy)
			p.position.y += vy * delta
			p.modulate.a = maxf(0.0, p.modulate.a - delta * 1.5)
		elif p.has_meta("life"):
			var life: float = p.get_meta("life") - delta
			p.set_meta("life", life)
			p.rotation = sin(life * 60.0) * 0.05
			if life <= 0.0:
				p.rotation = 0.0
				p.set_meta("vy", 0.0)
				peek.voice.play("glitch", 0.5)

func _pick_rockets(feet: float) -> void:
	for r: TextureRect in _rockets.duplicate():
		var centre := r.position + r.size / 2.0
		if centre.distance_to(_pos) < feet + r.size.y * 0.4:
			_rockets.erase(r)
			r.queue_free()
			_rocket_left = ROCKET_TIME
			_flame.visible = true
			peek.act("Celebrate")
			peek.voice.play("powerup")

# Falling Kuiz bounces off the first top it passed this frame (the ground counts until it scrolls
# away); a trampoline under it launches it higher, and a timed platform starts counting down.
func _land(was: float, now: float, feet: float) -> void:
	var reach := feet * 0.5
	var ground_top := _ground_top()
	if was <= ground_top and now >= ground_top:
		_bounce(ground_top, feet, JUMP)
		return
	for p in _platforms:
		if p.has_meta("vy"):
			continue
		var top: float = p.position.y + p.get_meta("top")
		if was <= top and now >= top and _pos.x > p.position.x - reach and _pos.x < p.position.x + p.size.x + reach:
			var spring: TextureRect = p.get_meta("spring") if p.has_meta("spring") else null
			if spring != null and _pos.x > p.position.x + spring.position.x - reach and _pos.x < p.position.x + spring.position.x + spring.size.x + reach:
				_bounce(top, feet, TRAMPOLINE_JUMP)
				peek.voice.play("boing")
				peek.act("Happy")
				var t := create_tween()
				t.tween_property(spring, "scale", Vector2(1.15, 0.6), 0.06)
				t.tween_property(spring, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				return
			if p.get_meta("kind") == "timed" and not p.has_meta("life"):
				p.set_meta("life", p.get_meta("life_total"))
				peek.voice.play("tick")
			_bounce(top, feet, JUMP)
			return

func _bounce(top: float, feet: float, speed: float) -> void:
	_pos.y = top - feet
	_vel.y = -speed
	peek.voice.play("hop", 0.7)
