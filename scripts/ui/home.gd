extends CanvasLayer
## The home loop after the tutorial: the bottom bar walks Kuiz between the four rooms, and each room
## has its own care action. Study Room: charge (lights off) / play (upload a reviewer) / settings.
## Maintenance Bay: hold the screwdriver over Kuiz to tighten its frame. Data Kitchen: drag food to
## Kuiz; the fridge restocks it. Playroom: fling the ball; Kuiz watches it.
## No stats or currency yet. Contract: docs/ui-and-assets.md §2 Home.

const ROOMS: Array[String] = ["StudyRoom", "MaintenanceBay", "DataKitchen", "Playroom"]
const FOODS: Array[Dictionary] = [
	{"id": "data_chips", "name": "Data Chips", "icon": preload("res://assets/sprites/props/data_chips.svg"), "start": 3},
	{"id": "spicy_chips", "name": "Spicy Memory Chips", "icon": preload("res://assets/sprites/props/spicy_chips.svg"), "start": 1},
	{"id": "cache_cookie", "name": "Cache Cookie", "icon": preload("res://assets/sprites/props/cache_cookie.svg"), "start": 2},
	{"id": "pi_pie", "name": "Pi Pie", "icon": preload("res://assets/sprites/props/pi_pie.svg"), "start": 1},
	{"id": "byte_burger", "name": "Byte Burger", "icon": preload("res://assets/sprites/props/byte_burger.svg"), "start": 1},
	{"id": "java_juice", "name": "Java Juice", "icon": preload("res://assets/sprites/props/java_juice.svg"), "start": 2},
]
const FAVORITE_FOOD := "spicy_chips"
const SCREWDRIVER: Texture2D = preload("res://assets/sprites/props/screwdriver.svg")
const CHARGE_SFX: AudioStream = preload("res://assets/audio/charge.mp3")
const CHARGED_SFX: AudioStream = preload("res://assets/audio/charged.mp3")
const UPLOAD_SCENE := "res://scenes/review_session/categorizer.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings.tscn"
const FADE_TIME := 0.35
const HELD_SIZE := Vector2(120, 120)
# Screwdriver: seconds of holding it over Kuiz to finish a tune-up, and its twist while working.
const FIX_TIME := 2.0
const TWIST := 0.35
# Ball physics in screen pixels: gravity, bounce keep, floor friction, fling cap, rest speed.
const GRAVITY := 1800.0
const BOUNCE := 0.6
const FRICTION := 0.85
const MAX_FLING := 2600.0
const REST_SPEED := 40.0
const SURPRISE_COOLDOWN := 1.0

@onready var peek: Node3D = get_parent()
@onready var bar: Control = $Bar
@onready var prev_btn: BaseButton = $Bar/Row/Prev
@onready var next_btn: BaseButton = $Bar/Row/Next
@onready var groups := {
	"StudyRoom": $Bar/Row/Study,
	"MaintenanceBay": $Bar/Row/Bay,
	"DataKitchen": $Bar/Row/Kitchen,
	"Playroom": $Bar/Row/Play,
}
@onready var charge_btn: Button = $Bar/Row/Study/Charge
@onready var play_btn: Button = $Bar/Row/Study/Play
@onready var settings_btn: Button = $Bar/Row/Study/Settings
@onready var tool_slot: TextureRect = $Bar/Row/Bay/Tool
@onready var food_icon: TextureRect = $Bar/Row/Kitchen/Food/Icon
@onready var food_label: Label = $Bar/Row/Kitchen/Food/Label
@onready var fridge: BaseButton = $Fridge
@onready var shop: Control = $Shop
@onready var shop_list: VBoxContainer = $Shop/Body/List
@onready var ball: TextureRect = $Ball
@onready var held: TextureRect = $Held

var _room_i := 0
var _busy := false
var _food_i := 0
var _held_kind := ""
var _over_kuiz := false
var _fix := 0.0
var _ball_vel := Vector2.ZERO
var _ball_grabbed := false
var _ball_trail: Array = []
var _ball_resting := true
var _surprised_at := -10.0

func _ready() -> void:
	visible = false
	for food in FOODS:
		GameState.food_stock.get_or_add(food["id"], food["start"])
	prev_btn.pressed.connect(_go.bind(-1))
	next_btn.pressed.connect(_go.bind(1))
	charge_btn.toggled.connect(_on_charge)
	play_btn.pressed.connect(_on_play)
	settings_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file(SETTINGS_SCENE))
	$Bar/Row/Kitchen/FoodPrev.pressed.connect(_pick_food.bind(-1))
	$Bar/Row/Kitchen/FoodNext.pressed.connect(_pick_food.bind(1))
	food_icon.gui_input.connect(_on_slot_input.bind("food"))
	tool_slot.gui_input.connect(_on_slot_input.bind("tool"))
	ball.gui_input.connect(_on_ball_input)
	fridge.pressed.connect(_open_shop)
	$Shop/Body/Close.pressed.connect(func() -> void: shop.hide())
	_build_shop()
	_pick_food(0)
	if GameState.tutorial_done:
		start.call_deferred()
	else:
		$"../Tutorial".finished.connect(start)

## Shows the bar in the Study Room; the save is read the first time home opens this session.
func start() -> void:
	SaveManager.load_once()
	visible = true
	_room_i = 0
	_show_room_props(ROOMS[0])
	bar.modulate.a = 0.0
	create_tween().tween_property(bar, "modulate:a", 1.0, FADE_TIME)
	await peek.to_room_pose()

func _go(step: int) -> void:
	if _busy:
		return
	_busy = true
	_set_bar_enabled(false)
	_drop_held()
	_room_i = wrapi(_room_i + step, 0, ROOMS.size())
	await peek.walk(_enter.bind(ROOMS[_room_i]), step)
	_set_bar_enabled(true)
	_busy = false

func _enter(room_name: String) -> void:
	peek.show_room(room_name)
	_show_room_props(room_name)

func _show_room_props(room_name: String) -> void:
	for key: String in groups:
		groups[key].visible = key == room_name
	fridge.visible = room_name == "DataKitchen"
	ball.visible = room_name == "Playroom"
	shop.hide()
	_fix = 0.0
	peek.look_ahead()
	if ball.visible:
		_ball_vel = Vector2.ZERO
		_ball_resting = true
		ball.position = Vector2(_view().x / 2.0 - ball.size.x / 2.0, _floor_y())

func _set_bar_enabled(on: bool) -> void:
	for b: BaseButton in [prev_btn, next_btn, play_btn, settings_btn]:
		b.disabled = not on

# --- Study Room ---

func _on_charge(charging: bool) -> void:
	peek.set_lights(not charging)
	_set_bar_enabled(not charging)
	if charging:
		peek.act("State_Charging")
		MusicManager.play_sfx_chain([CHARGE_SFX, CHARGED_SFX])
	else:
		peek.act("Wake_Up")

func _on_play() -> void:
	SessionManager.editing_topic_id = "topic_%d" % (int(Time.get_unix_time_from_system()) % 100000)
	get_tree().change_scene_to_file(UPLOAD_SCENE)

# --- Data Kitchen ---

func _pick_food(step: int) -> void:
	_food_i = wrapi(_food_i + step, 0, FOODS.size())
	_refresh_food()

func _refresh_food() -> void:
	var food: Dictionary = FOODS[_food_i]
	var count: int = GameState.food_stock[food["id"]]
	food_icon.texture = food["icon"]
	food_icon.modulate.a = 1.0 if count > 0 else 0.35
	food_label.text = "%s ×%d" % [food["name"], count]

func _build_shop() -> void:
	for food in FOODS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var icon := TextureRect.new()
		icon.texture = food["icon"]
		icon.custom_minimum_size = Vector2(72, 72)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color("29383A"))
		var buy: Button = $Shop/Body/BuyTemplate.duplicate()
		buy.show()
		# shortcut: buying is free until the currency exists; then charge its price here.
		buy.pressed.connect(func() -> void:
			GameState.food_stock[food["id"]] += 1
			_refresh_shop()
			_refresh_food())
		row.add_child(icon)
		row.add_child(label)
		row.add_child(buy)
		row.set_meta("food", food)
		shop_list.add_child(row)

func _open_shop() -> void:
	_refresh_shop()
	shop.show()

func _refresh_shop() -> void:
	for row in shop_list.get_children():
		var food: Dictionary = row.get_meta("food")
		(row.get_child(1) as Label).text = "%s\nYou have %d" % [food["name"], GameState.food_stock[food["id"]]]

func _eat(food: Dictionary) -> void:
	GameState.food_stock[food["id"]] -= 1
	_refresh_food()
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(held, "position", peek.head_point() - held.size / 2.0, 0.25)
	t.tween_property(held, "scale", Vector2.ZERO, 0.25)
	await t.finished
	held.hide()
	held.scale = Vector2.ONE
	peek.act("Pet" if food["id"] == FAVORITE_FOOD else "Happy")

# --- Dragging food and the screwdriver ---

func _on_slot_input(event: InputEvent, kind: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _busy or _held_kind != "":
		return
	if kind == "food" and GameState.food_stock[FOODS[_food_i]["id"]] <= 0:
		return
	_held_kind = kind
	_over_kuiz = false
	held.texture = SCREWDRIVER if kind == "tool" else FOODS[_food_i]["icon"]
	held.size = HELD_SIZE
	held.pivot_offset = HELD_SIZE / 2.0
	held.rotation = 0.0
	held.show()
	(tool_slot if kind == "tool" else food_icon).modulate.a = 0.0
	_move_held(event.global_position)

func _input(event: InputEvent) -> void:
	if _held_kind != "":
		if event is InputEventMouseMotion:
			_move_held(event.position)
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_release_held(event.position)
	elif _ball_grabbed:
		if event is InputEventMouseMotion:
			_ball_to(event.position)
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_fling_ball()

func _move_held(pos: Vector2) -> void:
	held.position = pos - held.size / 2.0
	peek.look_at_point(pos)
	var over: bool = peek.hits(pos)
	if over and not _over_kuiz:
		if _held_kind == "food":
			peek.act("Surprised")
		else:
			peek.act("State_Sick")
	elif _over_kuiz and not over and _held_kind == "tool":
		peek.act("Idle")
	_over_kuiz = over

func _release_held(pos: Vector2) -> void:
	var kind := _held_kind
	_held_kind = ""
	peek.look_ahead()
	if kind == "food" and peek.hits(pos):
		await _eat(FOODS[_food_i])
		food_icon.modulate.a = 1.0 if GameState.food_stock[FOODS[_food_i]["id"]] > 0 else 0.35
		return
	if kind == "tool" and _over_kuiz:
		peek.act("Idle")
	_drop_held()

func _drop_held() -> void:
	_held_kind = ""
	held.hide()
	tool_slot.modulate.a = 1.0
	_refresh_food()

func _process(delta: float) -> void:
	if _held_kind == "tool" and _over_kuiz:
		_fix += delta
		held.rotation = sin(_fix * 14.0) * TWIST
		if _fix >= FIX_TIME:
			_fix = 0.0
			_over_kuiz = false
			_drop_held()
			peek.look_ahead()
			peek.act("Celebrate")
	if ball.visible and not _ball_grabbed and not _ball_resting:
		_step_ball(delta)

# --- Playroom ---

func _on_ball_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _busy:
		_ball_grabbed = true
		_ball_resting = false
		_ball_trail.clear()
		_ball_to(event.global_position)

func _ball_to(pos: Vector2) -> void:
	ball.position = pos - ball.size / 2.0
	_ball_trail.append([pos, Time.get_ticks_msec() / 1000.0])
	if _ball_trail.size() > 5:
		_ball_trail.pop_front()
	peek.look_at_point(pos)

func _fling_ball() -> void:
	_ball_grabbed = false
	_ball_vel = Vector2.ZERO
	if _ball_trail.size() >= 2:
		var a: Array = _ball_trail[0]
		var b: Array = _ball_trail[-1]
		var dt := maxf(0.016, float(b[1]) - float(a[1]))
		_ball_vel = ((b[0] as Vector2) - (a[0] as Vector2)) / dt
	_ball_vel = _ball_vel.limit_length(MAX_FLING)
	if _ball_vel.length() > 300.0:
		peek.act("Happy")

func _step_ball(delta: float) -> void:
	var view := _view()
	_ball_vel.y += GRAVITY * delta
	var pos := ball.position + _ball_vel * delta
	var floor_y := _floor_y()
	if pos.x < 0.0 or pos.x > view.x - ball.size.x:
		pos.x = clampf(pos.x, 0.0, view.x - ball.size.x)
		_ball_vel.x *= -BOUNCE
	if pos.y < 0.0:
		pos.y = 0.0
		_ball_vel.y *= -BOUNCE
	if pos.y > floor_y:
		pos.y = floor_y
		_ball_vel.y *= -BOUNCE
		_ball_vel.x *= FRICTION
		if absf(_ball_vel.y) < REST_SPEED * 4.0 and absf(_ball_vel.x) < REST_SPEED:
			_ball_vel = Vector2.ZERO
			_ball_resting = true
			peek.look_ahead()
	# Bounce off Kuiz's head (and startle it).
	var centre := pos + ball.size / 2.0
	var head: Vector2 = peek.head_point()
	var reach: float = peek.head_radius() + ball.size.x / 2.0
	var away := centre - head
	if away.length() < reach and _ball_vel.dot(away) < 0.0:
		var n := away.normalized()
		_ball_vel = _ball_vel.bounce(n) * BOUNCE
		pos = head + n * reach - ball.size / 2.0
		var now := Time.get_ticks_msec() / 1000.0
		if now - _surprised_at > SURPRISE_COOLDOWN:
			_surprised_at = now
			peek.act("Surprised")
	ball.position = pos
	ball.rotation += _ball_vel.x * delta / (ball.size.x / 2.0)
	if not _ball_resting:
		peek.look_at_point(centre)

func _floor_y() -> float:
	return bar.get_global_rect().position.y - ball.size.y + 6.0

func _view() -> Vector2:
	return get_viewport().get_visible_rect().size
