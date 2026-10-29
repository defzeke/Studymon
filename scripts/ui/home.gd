extends CanvasLayer
## The home loop after the tutorial: the top arrows walk Kuiz between the four rooms, and each room
## has its own care action in the bottom bar. Study Room: charge (lights off) / play (opens the Worlds hub) / settings.
## Maintenance Bay: the tablet's check-up (and a new battery for crystals), the screwdriver (hold it over Kuiz to tighten its frame)
## and the towel (scrub the dirt off). Data Kitchen: drag food in stock to Kuiz; the fridge restocks
## it. Playroom: drag the ball out of the dock and fling it (it rolls back once it settles), the
## closet dresses Kuiz up, and Games opens the two minigames. Anywhere: hold or stroke Kuiz to pet
## it. The top HUD shows level, the four care stats and crystals, and a low stat shows on Kuiz as a
## mood. Contract: docs/ui-and-assets.md §2 Home.

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
const TOWEL: Texture2D = preload("res://assets/sprites/props/towel.svg")
const BOLD: Font = preload("res://assets/fonts/JosefinSans-Bold.ttf")
const CHARGE_SFX: AudioStream = preload("res://assets/audio/sfx/sfx_charge.wav")
const CHARGED_SFX: AudioStream = preload("res://assets/audio/sfx/sfx_charged.wav")
const SETTINGS_SCENE := "res://scenes/ui/settings.tscn"
const WORLDS_SCENE := "res://scenes/ui/session_list.tscn"
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
const TABLE_BACK := 34.0
# A stat below this share shows on Kuiz (the gauges turn coral at the same point); the first low
# one in this order wins.
const LOW_STAT := 0.25
const MOODS := [["health", "State_Sick"], ["hunger", "State_Hungry"], ["energy", "State_Tired"], ["mood", "State_Sad"]]
const MOOD_CHECK := 0.5
# A tired Kuiz only dozes in the Study Room (by its charger) and stays there while it does; a tap
# wakes it for this long.
const AWAKE_TIME := 20.0
const SLEEP_ROOM := "StudyRoom"
const TOAST_TIME := 2.2
# A tap on the level pill or a stat gauge shows its numbers in a card below it for this long (or
# until tapped again).
const LEVEL_INFO_TIME := 3.0
const STAT_NAMES :={"hunger": "Hunger", "energy": "Energy", "mood": "Mood", "health": "Health"}
const STAT_HINTS := {
	"hunger": "Feed Kuiz in the Data Kitchen",
	"energy": "Charge Kuiz in the Study Room",
	"mood": "Pet Kuiz or play in the Playroom",
	"health": "Tighten its screws in the Bay",
}
# Petting: hold Kuiz this long, or stroke it this far (px), and it plays Pet; pet care counts at
# most once per PET_GAP seconds.
const PET_HOLD := 0.35
const PET_STROKE := 70.0
const PET_GAP := 3.0
# A ball throw counts as play care at most once per FLING_GAP seconds.
const FLING_GAP := 3.0
# The towel takes this much dirt off per pixel scrubbed over Kuiz.
const SCRUB_PER_PX := 0.06
# The check-up's rows: [label, stat, inverted (dirt reads as cleanliness)]. The battery row is its
# health (capacity), not its charge; the Energy gauge shows the charge.
const CHECKS := [["Battery health", "battery_health", false], ["Frame", "health", false], ["Clean", "dirt", true], ["Fuel", "hunger", false]]
const CHECK_HINTS := {
	"battery_health": "Battery worn out: it drains fast. Fit a new one below.",
	"health": "Screws loose: tighten them with the screwdriver.",
	"dirt": "Dusty and scuffed: scrub Kuiz with the towel.",
	"hunger": "Running on empty: feed Kuiz in the Data Kitchen.",
}

@onready var peek: Node3D = owner as Node3D
@onready var tutorial: CanvasLayer = %Tutorial
@onready var bar: Control = %Bar
@onready var prev_btn: BaseButton = %RoomPrev
@onready var next_btn: BaseButton = %RoomNext
@onready var room_sign: Control = %RoomSign
@onready var level_label: Label = %Number
@onready var xp_bar: ProgressBar = %Xp
@onready var level_info: Control = %LevelInfo
@onready var stat_info: Control = %StatInfo
@onready var crystal_label: Label = %CrystalLabel
@onready var gauges := {"hunger": %Hunger, "energy": %Energy, "mood": %Mood, "health": %Health}
# Room name (the Rooms/<Name> node in peek.tscn) -> the bar section shown in that room.
@onready var groups := {
	"StudyRoom": %Study,
	"MaintenanceBay": %Bay,
	"DataKitchen": %Kitchen,
	"Playroom": %PlayBar,
}
@onready var charge_btn: Button = %Charge
@onready var play_btn: Button = %Play
@onready var settings_btn: Button = %Settings
@onready var tool_slot: TextureRect = %Tool
@onready var towel_slot: TextureRect = %Towel
@onready var check_panel: Control = %CheckPanel
@onready var check_rows: VBoxContainer = %CheckRows
@onready var check_hint: Label = %CheckHint
@onready var new_battery_btn: Button = %NewBattery
@onready var wardrobe: Control = %Wardrobe
@onready var wardrobe_tabs: HBoxContainer = %WardrobeTabs
@onready var wardrobe_grid: GridContainer = %WardrobeGrid
@onready var look: Node = %Look
@onready var food_prev_btn: BaseButton = %FoodPrev
@onready var food_next_btn: BaseButton = %FoodNext
@onready var food_icon: TextureRect = %FoodIcon
@onready var food_label: Label = %FoodLabel
@onready var fridge: BaseButton = %Fridge
@onready var shop: Control = %Shop
@onready var shop_list: VBoxContainer = %ShopList
@onready var shop_close_btn: BaseButton = %Close
@onready var buy_template: Button = %BuyTemplate
@onready var ball: TextureRect = %Ball
@onready var ball_slot: TextureRect = %BallSlot
@onready var held: TextureRect = %Held
@onready var games_btn: BaseButton = %Games
@onready var toast: Control = %Toast
@onready var toast_label: Label = %ToastLabel
@onready var picker: Control = %Picker
@onready var top_layer: CanvasLayer = $"../Top"
@onready var games := {%PlaySoccer: $"../Soccer", %PlayJump: $"../SkyJumpHud"}

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
var _ball_returning := false
var _surprised_at := -10.0
var _charge_pulse: Tween
var _game: CanvasLayer
var _mood_wait := 0.0
var _awake_until := -100.0
var _toast_fx: Tween
var _info_fx: Tween
var _info_stat := ""
var _pet_down := false
var _pet_since := 0.0
var _pet_stroke := 0.0
var _pet_last := Vector2.ZERO
var _petting := false
var _pet_cared := -100.0
var _fling_cared := -100.0
var _held_last := Vector2.ZERO
var _was_dirty := false
var _closet_slot := "head"

func _ready() -> void:
	visible = false
	for food in FOODS:
		GameState.food_stock.get_or_add(food["id"], food["start"])
	prev_btn.pressed.connect(_go.bind(-1))
	next_btn.pressed.connect(_go.bind(1))
	charge_btn.toggled.connect(_on_charge)
	play_btn.pressed.connect(_on_play)
	settings_btn.pressed.connect(func() -> void:
		if not _busy:
			get_tree().change_scene_to_file(SETTINGS_SCENE))
	food_prev_btn.pressed.connect(_pick_food.bind(-1))
	food_next_btn.pressed.connect(_pick_food.bind(1))
	food_icon.gui_input.connect(_on_slot_input.bind("food"))
	tool_slot.gui_input.connect(_on_slot_input.bind("tool"))
	towel_slot.gui_input.connect(_on_slot_input.bind("towel"))
	%Checkup.pressed.connect(_open_checkup)
	%CheckClose.pressed.connect(check_panel.hide)
	new_battery_btn.text = "New battery  %d" % CompanionState.BATTERY_PRICE
	new_battery_btn.pressed.connect(_buy_battery)
	%Closet.pressed.connect(_open_wardrobe)
	%WardrobeClose.pressed.connect(wardrobe.hide)
	ball.gui_input.connect(_on_ball_input)
	ball_slot.gui_input.connect(_on_ball_slot_input)
	fridge.pressed.connect(_open_shop)
	shop_close_btn.pressed.connect(func() -> void: shop.hide())
	games_btn.pressed.connect(picker.show)
	%PickerClose.pressed.connect(picker.hide)
	for btn: BaseButton in games:
		btn.pressed.connect(_play_game.bind(games[btn]))
		games[btn].played.connect(_care.bind("play"))
		games[btn].played.connect(CompanionState.soil.bind(4.0))
	_build_shop()
	_pick_food(0)
	CompanionState.stats_changed.connect(_refresh_stats)
	CompanionState.xp_changed.connect(func(_xp: int, _level: int) -> void: _refresh_level())
	%Level.gui_input.connect(_on_level_input)
	for stat: String in gauges:
		gauges[stat].gui_input.connect(_on_gauge_input.bind(stat))
	GameState.crystals_changed.connect(func(amount: int) -> void: crystal_label.text = str(amount))
	if GameState.tutorial_done:
		start.call_deferred()
	else:
		tutorial.finished.connect(start)

## Shows the HUD and bar in the Study Room; the save is read the first time home opens this session.
func start() -> void:
	SaveManager.load_once()
	visible = true
	_room_i = 0
	_show_room_props(ROOMS[0])
	_refresh_stats()
	_refresh_level()
	crystal_label.text = str(GameState.crystals)
	for c: CanvasItem in get_children():
		c.modulate.a = 0.0
		create_tween().tween_property(c, "modulate:a", 1.0, FADE_TIME)
	await peek.to_room_pose()

func _go(step: int) -> void:
	if _busy:
		return
	if _dozing():
		_toast("Shh… Kuiz is sleeping. Tap Kuiz to wake it up.")
		return
	# Only the arrows lock during the walk; the room's items keep their look (_busy ignores them).
	_busy = true
	_set_arrows_enabled(false)
	_drop_held()
	_room_i = wrapi(_room_i + step, 0, ROOMS.size())
	await peek.walk(_enter.bind(ROOMS[_room_i]), step)
	_set_arrows_enabled(true)
	_busy = false

func _enter(room_name: String) -> void:
	peek.show_room(room_name)
	_show_room_props(room_name)

func _show_room_props(room_name: String) -> void:
	for key: String in groups:
		groups[key].visible = key == room_name
	# The ball waits in the dock until it is dragged out.
	ball.visible = false
	ball_slot.modulate.a = 1.0
	_ball_grabbed = false
	_ball_returning = false
	for panel: Control in [shop, picker, check_panel, wardrobe]:
		panel.hide()
	_fix = 0.0
	peek.look_ahead()
	_ball_vel = Vector2.ZERO
	_ball_resting = true

func _refresh_stats() -> void:
	for stat: String in gauges:
		gauges[stat].value = CompanionState.get(stat) / CompanionState.STAT_MAX
	if stat_info.visible:
		%StatValue.text = "%d / %d" % [roundi(CompanionState.get(_info_stat)), CompanionState.STAT_MAX]

func _refresh_level() -> void:
	var lv := CompanionState.level
	level_label.text = str(lv)
	var floor_xp := CompanionState.xp_to_reach(lv)
	var next_xp := CompanionState.xp_to_reach(lv + 1)
	xp_bar.value = float(CompanionState.xp - floor_xp) / (next_xp - floor_xp)
	%LevelName.text = "Level %d" % lv
	%LevelXp.text = "%d / %d XP" % [CompanionState.xp - floor_xp, next_xp - floor_xp]
	%LevelNext.text = "%d XP to Level %d" % [next_xp - CompanionState.xp, lv + 1]

# The level pill toggles a card below it with the level, XP into it and XP to the next one.
func _on_level_input(event: InputEvent) -> void:
	if _tapped(event):
		_refresh_level()
		_toggle_info(level_info, "level")

# A stat gauge toggles a card below it with the stat's value and where to raise it.
func _on_gauge_input(event: InputEvent, stat: String) -> void:
	if not _tapped(event):
		return
	_info_stat = stat
	%StatName.text = STAT_NAMES[stat]
	%StatHint.text = STAT_HINTS[stat]
	_refresh_stats()
	%StatValue.text = "%d / %d" % [roundi(CompanionState.get(stat)), CompanionState.STAT_MAX]
	stat_info.reset_size()
	var under: Rect2 = gauges[stat].get_global_rect()
	stat_info.position.x = clampf(under.get_center().x - stat_info.size.x / 2.0, 16.0, _view().x - stat_info.size.x - 16.0)
	_toggle_info(stat_info, stat)

func _tapped(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT

# One info card at a time: a second tap on the same one closes it; it fades after LEVEL_INFO_TIME.
func _toggle_info(card: Control, key: String) -> void:
	if _info_fx:
		_info_fx.kill()
	var open_again: bool = card.visible and card.get_meta("key", "") == key
	level_info.hide()
	stat_info.hide()
	if open_again:
		return
	card.set_meta("key", key)
	card.show()
	_info_fx = create_tween()
	_info_fx.tween_property(card, "modulate:a", 1.0, 0.15).from(0.0)
	_info_fx.tween_interval(LEVEL_INFO_TIME)
	_info_fx.tween_property(card, "modulate:a", 0.0, 0.3)
	_info_fx.tween_callback(card.hide)

## A care action raises its stat and XP (CompanionState.care) and saves.
func _care(action: String) -> void:
	CompanionState.care(action)
	SaveManager.save_progress()

# The resting clip follows the stats: the first low one shows as a mood, otherwise Idle. Tiredness
# is dozing, which only happens in the Study Room, and a Kuiz just woken up stays awake for a while
# however tired it is.
func _mood_clip() -> String:
	var can_doze := ROOMS[_room_i] == SLEEP_ROOM and _now() >= _awake_until
	for pair: Array in MOODS:
		if CompanionState.get(pair[0]) < CompanionState.STAT_MAX * LOW_STAT:
			if pair[1] == "State_Tired" and not can_doze:
				continue
			return pair[1]
	return "Idle"

func _dozing() -> bool:
	return peek.rest == "State_Tired"

# Taps on Kuiz: a dozing Kuiz wakes up; otherwise holding or stroking it pets it (see _pet()).
func _unhandled_input(event: InputEvent) -> void:
	if _game != null or not visible or charge_btn.button_pressed or _held_kind != "" or _ball_grabbed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and peek.hits(event.position):
			if _dozing():
				_awake_until = _now() + AWAKE_TIME
				peek.set_rest(_mood_clip())
				peek.act("Wake_Up")
				return
			_pet_down = true
			_pet_since = _now()
			_pet_stroke = 0.0
			_pet_last = event.position
		elif not event.pressed:
			_pet_down = false
			_petting = false
			peek.look_ahead()
	elif event is InputEventMouseMotion and _pet_down:
		if peek.hits(event.position):
			_pet_stroke += event.position.distance_to(_pet_last)
		_pet_last = event.position

# Held long enough or stroked far enough, Kuiz plays Pet, and keeps playing it while the hand stays.
func _pet() -> void:
	if not _pet_down:
		return
	peek.look_at_point(_pet_last)
	if not _petting and _now() - _pet_since < PET_HOLD and _pet_stroke < PET_STROKE:
		return
	_petting = true
	if peek.anim.current_animation != "Pet":
		peek.act("Pet")
		if _now() - _pet_cared > PET_GAP:
			_pet_cared = _now()
			_care("pet")

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _toast(text: String) -> void:
	toast_label.text = text
	toast.show()
	if _toast_fx:
		_toast_fx.kill()
	_toast_fx = create_tween()
	_toast_fx.tween_property(toast, "modulate:a", 1.0, 0.15).from(0.0)
	_toast_fx.tween_interval(TOAST_TIME)
	_toast_fx.tween_property(toast, "modulate:a", 0.0, 0.3)
	_toast_fx.tween_callback(toast.hide)

func _set_bar_enabled(on: bool) -> void:
	_set_arrows_enabled(on)
	for b: BaseButton in [play_btn, settings_btn]:
		b.disabled = not on

func _set_arrows_enabled(on: bool) -> void:
	for b: BaseButton in [prev_btn, next_btn]:
		b.disabled = not on

# --- Study Room ---

func _on_charge(charging: bool) -> void:
	peek.set_lights(not charging)
	_set_bar_enabled(not charging)
	if _charge_pulse:
		_charge_pulse.kill()
	charge_btn.pivot_offset = charge_btn.size / 2.0
	charge_btn.scale = Vector2.ONE
	if charging:
		peek.act("State_Charging")
		MusicManager.play_sfx_chain([CHARGE_SFX, CHARGED_SFX])
		# A bare icon has no lit state, so the bolt pulses while Kuiz charges.
		_charge_pulse = create_tween().set_loops()
		_charge_pulse.tween_property(charge_btn, "scale", Vector2.ONE * 1.12, 0.5).set_trans(Tween.TRANS_SINE)
		_charge_pulse.tween_property(charge_btn, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	else:
		peek.act("Wake_Up")

func _on_play() -> void:
	if not _busy:
		get_tree().change_scene_to_file(WORLDS_SCENE)

# --- Maintenance Bay ---

# Scrubbing takes dirt off; getting Kuiz spotless in one scrub counts as clean care.
func _scrub(px: float) -> void:
	if CompanionState.dirt <= 0.0:
		return
	CompanionState.scrub(px * SCRUB_PER_PX)
	if CompanionState.dirt <= 0.0 and _was_dirty:
		_was_dirty = false
		_care("clean")
		peek.act("Celebrate")
		_toast("Squeaky clean!")

func _open_checkup() -> void:
	if check_rows.get_child_count() == 0:
		for spec: Array in CHECKS:
			check_rows.add_child(_check_row(spec[0]))
	_refresh_checkup()
	check_panel.show()

func _check_row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = title
	name_label.custom_minimum_size = Vector2(186, 0)
	var meter := ProgressBar.new()
	meter.custom_minimum_size = Vector2(0, 26)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.show_percentage = false
	meter.max_value = 100.0
	var back := StyleBoxFlat.new()
	back.bg_color = Color("29383A", 0.35)
	back.set_corner_radius_all(13)
	meter.add_theme_stylebox_override("background", back)
	meter.add_theme_stylebox_override("fill", back.duplicate())
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(70, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for l: Label in [name_label, pct]:
		l.add_theme_color_override("font_color", Color("F7F5EF"))
		l.add_theme_font_override("font", BOLD)
		l.add_theme_font_size_override("font_size", 22)
	row.add_child(name_label)
	row.add_child(meter)
	row.add_child(pct)
	return row

# Each row shows its stat (dirt as cleanliness): off-white when fine, amber below half, coral when
# low; the hint names the most urgent fix.
func _refresh_checkup() -> void:
	var worst := ""
	var worst_value := 101.0
	for i in CHECKS.size():
		var spec: Array = CHECKS[i]
		var value: float = CompanionState.get(spec[1])
		if spec[2]:
			value = CompanionState.STAT_MAX - value
		var row := check_rows.get_child(i)
		var meter := row.get_child(1) as ProgressBar
		meter.value = value
		var fill := meter.get_theme_stylebox("fill") as StyleBoxFlat
		fill.bg_color = Color("C97970") if value < 25.0 else (Color("D6A85F") if value < 50.0 else Color("F7F5EF"))
		(row.get_child(2) as Label).text = "%d%%" % roundi(value)
		if value < worst_value:
			worst_value = value
			worst = spec[1]
	check_hint.text = CHECK_HINTS[worst] if worst_value < 50.0 else "All systems good!"
	new_battery_btn.disabled = CompanionState.battery_health >= CompanionState.STAT_MAX - 0.5

# A new battery costs crystals and puts its health back to 100%.
func _buy_battery() -> void:
	if not CompanionState.replace_battery():
		_toast("Not enough crystals. Win minigames in the Playroom to earn them.")
		return
	SaveManager.save_progress()
	peek.act("Celebrate")
	_toast("New battery fitted: 100% health!")

# --- Data Kitchen ---

# The arrows only step through foods in stock (-1 when none are); the fridge lists all of them.
# step 0 keeps the current food if it is still in stock, else finds the next one.
func _pick_food(step: int) -> void:
	if step == 0 and _food_i >= 0 and _stock(_food_i) > 0:
		_refresh_food()
		return
	var from := maxi(_food_i, 0)
	var dir := step if step != 0 else 1
	_food_i = -1
	for k in range(0 if step == 0 else 1, FOODS.size() + 1):
		var i := wrapi(from + dir * k, 0, FOODS.size())
		if _stock(i) > 0:
			_food_i = i
			break
	_refresh_food()

func _stock(i: int) -> int:
	return GameState.food_stock[FOODS[i]["id"]]

func _refresh_food() -> void:
	var stocked := 0
	for i in FOODS.size():
		stocked += 1 if _stock(i) > 0 else 0
	for b: CanvasItem in [food_prev_btn, food_next_btn]:
		b.modulate.a = 1.0 if stocked > 1 else 0.35
	if _food_i < 0:
		food_icon.texture = null
		food_label.text = "Empty! Check the fridge"
		return
	var food: Dictionary = FOODS[_food_i]
	food_icon.texture = food["icon"]
	food_icon.modulate.a = 1.0
	food_label.text = "%s ×%d" % [food["name"], _stock(_food_i)]

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
		var buy: Button = buy_template.duplicate()
		buy.show()
		# shortcut: buying is free until the currency exists; then charge its price here.
		buy.pressed.connect(func() -> void:
			GameState.food_stock[food["id"]] += 1
			SaveManager.save_progress()
			_refresh_shop()
			_pick_food(0))
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
	SaveManager.save_progress()
	_refresh_food()
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(held, "position", peek.head_point() - held.size / 2.0, 0.25)
	t.tween_property(held, "scale", Vector2.ZERO, 0.25)
	await t.finished
	held.hide()
	held.scale = Vector2.ONE
	_care("feed")
	CompanionState.soil()
	peek.act("Pet" if food["id"] == FAVORITE_FOOD else "Happy")

# --- Dragging food and the screwdriver ---

func _on_slot_input(event: InputEvent, kind: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _busy or _held_kind != "":
		return
	if kind == "food" and (_food_i < 0 or _stock(_food_i) <= 0):
		return
	_held_kind = kind
	_over_kuiz = false
	held.texture = {"tool": SCREWDRIVER, "towel": TOWEL}.get(kind, FOODS[maxi(_food_i, 0)]["icon"])
	_held_last = event.global_position
	_was_dirty = CompanionState.dirt > 1.0
	held.size = HELD_SIZE
	held.pivot_offset = HELD_SIZE / 2.0
	held.rotation = 0.0
	held.show()
	({"tool": tool_slot, "towel": towel_slot}.get(kind, food_icon) as CanvasItem).modulate.a = 0.0
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
		match _held_kind:
			"food":
				peek.act("Surprised")
			"tool":
				peek.act("State_Sick")
			"towel":
				peek.act("Pet")
	elif _over_kuiz and not over and _held_kind != "food":
		peek.act("Idle")
	_over_kuiz = over
	if _held_kind == "towel" and over:
		_scrub(pos.distance_to(_held_last))
	_held_last = pos

func _release_held(pos: Vector2) -> void:
	var kind := _held_kind
	_held_kind = ""
	peek.look_ahead()
	if kind == "food" and peek.hits(pos):
		await _eat(FOODS[_food_i])
		# The last one eaten: move on to the next food in stock.
		_pick_food(0)
		return
	if kind != "food" and _over_kuiz:
		peek.act("Idle")
	_drop_held()

func _drop_held() -> void:
	_held_kind = ""
	held.hide()
	tool_slot.modulate.a = 1.0
	towel_slot.modulate.a = 1.0
	_pick_food(0)

func _process(delta: float) -> void:
	if _game != null:
		return
	_mood_wait -= delta
	if _mood_wait <= 0.0:
		_mood_wait = MOOD_CHECK
		peek.set_rest(_mood_clip())
		# Room arrows dim while Kuiz sleeps (dozing or charging).
		var asleep := _dozing() or charge_btn.button_pressed
		for b: CanvasItem in [prev_btn, next_btn]:
			b.modulate.a = 0.45 if asleep else 1.0
	# The arrows hug the room sign, whose width follows the room name.
	var sign_rect := room_sign.get_global_rect()
	prev_btn.position.x = sign_rect.position.x - prev_btn.size.x - 6.0
	next_btn.position.x = sign_rect.end.x + 6.0
	if charge_btn.button_pressed:
		CompanionState.recharge(delta)
	_pet()
	if check_panel.visible:
		_refresh_checkup()
	if _held_kind == "tool" and _over_kuiz:
		_fix += delta
		held.rotation = sin(_fix * 14.0) * TWIST
		if _fix >= FIX_TIME:
			_fix = 0.0
			_over_kuiz = false
			_drop_held()
			peek.look_ahead()
			_care("fix")
			peek.act("Celebrate")
	if ball.visible and not _ball_grabbed and not _ball_resting:
		_step_ball(delta)

# --- Playroom ---

## A minigame takes the whole screen: home and the room sign hide until the player leaves it.
func _play_game(game: CanvasLayer) -> void:
	picker.hide()
	_drop_held()
	_game = game
	visible = false
	top_layer.visible = false
	peek.set_rest("Idle")
	game.start()
	await game.finished
	_game = null
	peek.home_pose()
	peek.show_room("Playroom")
	_show_room_props("Playroom")
	top_layer.visible = true
	visible = true

# The closet: a tab per slot (Head, Face, Body), and a grid of that slot's costumes plus "None".
# A tap wears it at once (one costume per slot) and saves.
func _open_wardrobe() -> void:
	if wardrobe_tabs.get_child_count() == 0:
		for slot: Array in look.SLOTS:
			var tab := _closet_button(slot[1])
			tab.custom_minimum_size = Vector2(0, 64)
			tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tab.set_meta("slot", slot[0])
			tab.pressed.connect(_show_closet_slot.bind(slot[0]))
			wardrobe_tabs.add_child(tab)
	_show_closet_slot(_closet_slot)
	wardrobe.show()

func _show_closet_slot(slot: String) -> void:
	_closet_slot = slot
	for b in wardrobe_grid.get_children():
		b.queue_free()
		wardrobe_grid.remove_child(b)
	wardrobe_grid.add_child(_costume_button("", "None", null))
	for id: String in look.COSTUMES:
		var c: Array = look.COSTUMES[id]
		if c[5] == slot:
			wardrobe_grid.add_child(_costume_button(id, c[0], c[1]))
	_refresh_wardrobe()

func _closet_button(title: String) -> Button:
	var b: Button = buy_template.duplicate()
	b.show()
	b.text = title
	b.add_theme_font_size_override("font_size", 22)
	return b

func _costume_button(id: String, title: String, icon: Texture2D) -> Button:
	var b := _closet_button(title)
	b.icon = icon
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size = Vector2(170, 170)
	b.set_meta("costume", id)
	b.pressed.connect(func() -> void:
		if id == "":
			GameState.outfit.erase(_closet_slot)
		else:
			GameState.outfit[_closet_slot] = id
		SaveManager.save_progress()
		peek.act("Happy")
		_refresh_wardrobe())
	return b

# The open tab and the costume worn in it show as pressed buttons.
func _refresh_wardrobe() -> void:
	var worn: String = GameState.outfit.get(_closet_slot, "")
	for b: Button in wardrobe_tabs.get_children():
		_press_look(b, b.get_meta("slot") == _closet_slot)
	for b: Button in wardrobe_grid.get_children():
		_press_look(b, b.get_meta("costume") == worn)

func _press_look(b: Button, on: bool) -> void:
	b.add_theme_stylebox_override("normal", buy_template.get_theme_stylebox("pressed" if on else "normal"))

# Pressing the ball in the dock takes the real ball out under the finger.
func _on_ball_slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _busy and not ball.visible:
		ball.visible = true
		ball.rotation = 0.0
		ball.scale = Vector2.ONE
		ball_slot.modulate.a = 0.0
		_ball_grabbed = true
		_ball_resting = false
		_ball_trail.clear()
		_ball_to(event.global_position)

# Once it settles, the ball rolls back into its dock slot.
func _return_ball() -> void:
	_ball_returning = true
	ball.pivot_offset = ball.size / 2.0
	var slot := ball_slot.get_global_rect()
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	t.tween_property(ball, "position", slot.get_center() - ball.size / 2.0, 0.45)
	t.tween_property(ball, "scale", Vector2.ONE * minf(1.0, slot.size.y / ball.size.y), 0.45)
	t.tween_property(ball, "rotation", ball.rotation + TAU, 0.45)
	await t.finished
	if not _ball_returning:
		return
	_ball_returning = false
	ball.visible = false
	ball.scale = Vector2.ONE
	ball_slot.modulate.a = 1.0

func _on_ball_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _busy and not _ball_returning:
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
		if _now() - _fling_cared > FLING_GAP:
			_fling_cared = _now()
			_care("play")
			CompanionState.soil(1.5)

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
			_return_ball.call_deferred()
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

# The ball settles on the tabletop's back edge (dock_table.svg: the top face starts 34 px down).
func _floor_y() -> float:
	return bar.get_global_rect().position.y + TABLE_BACK - ball.size.y + 6.0

func _view() -> Vector2:
	return get_viewport().get_visible_rect().size
