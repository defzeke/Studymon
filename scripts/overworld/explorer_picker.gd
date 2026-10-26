extends CanvasLayer
## "Choose your explorer": shown over the region map before playing. Each card is a live 3D preview
## of an explorer (its own small world, idling; the chosen one cheers). "Let's go!" emits `picked`
## with the id from player.gd's EXPLORERS. Contract: docs/systems/overworld.md §3 Explorer.

signal picked(id: String)

const Player := preload("res://scripts/overworld/player.gd")
const BOLD: Font = preload("res://assets/fonts/JosefinSans-Bold.ttf")
const NAMES := {"boy": "Boy", "girl": "Girl"}
const OFF := Color("F7F5EF")
const SLATE := Color("29383A")
const TEAL := Color("4F8F89")
const GRAY := Color("687778")
const SAGE := Color("E8F0EA")
const CARD := Vector2(250, 330)

var _choice := ""
var _cards := {}
var _anims := {}

func _ready() -> void:
	layer = 20
	_choice = GameState.explorer if Player.EXPLORERS.has(GameState.explorer) else "boy"
	var dim := ColorRect.new()
	dim.color = Color(SLATE, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(OFF, SLATE, 3, 32, 28))
	centre.add_child(panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 18)
	panel.add_child(list)
	list.add_child(_label("Choose your explorer", 36, SLATE))
	list.add_child(_label("Who walks the island with Kuiz?", 22, GRAY))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	list.add_child(row)
	for id: String in Player.EXPLORERS:
		row.add_child(_card(id))
	var go := Button.new()
	go.text = "Let's go!"
	go.custom_minimum_size = Vector2(0, 72)
	go.add_theme_font_override("font", BOLD)
	go.add_theme_font_size_override("font_size", 30)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		go.add_theme_color_override(state, OFF)
	go.add_theme_stylebox_override("normal", _box(TEAL, SLATE, 3, 24, 0))
	go.add_theme_stylebox_override("hover", _box(TEAL, SLATE, 3, 24, 0))
	go.add_theme_stylebox_override("pressed", _box(TEAL.darkened(0.15), SLATE, 3, 24, 0))
	go.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	go.pressed.connect(_go)
	list.add_child(go)
	_select(_choice)
	panel.modulate.a = 0.0
	panel.scale = Vector2.ONE * 0.92
	panel.pivot_offset = panel.get_combined_minimum_size() / 2.0
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "modulate:a", 1.0, 0.25)
	t.tween_property(panel, "scale", Vector2.ONE, 0.3)

func _card(id: String) -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select(id))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var view := SubViewportContainer.new()
	view.custom_minimum_size = CARD
	view.stretch = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	view.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = env
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(sun)
	var model: Node3D = Player.EXPLORERS[id].instantiate()
	model.rotation_degrees.y = -18.0
	vp.add_child(model)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0.62, 2.3)
	cam.rotation_degrees.x = -4.0
	vp.add_child(cam)
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
	anim.play("Idle")
	anim.animation_finished.connect(func(_c: StringName) -> void: anim.play("Idle", 0.2))
	_anims[id] = anim
	var name_label := _label(NAMES.get(id, id.capitalize()), 28, SLATE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	_cards[id] = card
	return card

# The chosen card gets a thick teal border and cheers; the other is plain.
func _select(id: String) -> void:
	_choice = id
	for key: String in _cards:
		var on: bool = key == id
		_cards[key].add_theme_stylebox_override("panel", _box(SAGE if on else OFF, TEAL if on else Color(SLATE, 0.35), 6 if on else 3, 24, 10))
	if _anims[id].current_animation != "Celebrate":
		_anims[id].play("Celebrate", 0.2)

func _go() -> void:
	picked.emit(_choice)
	var t := create_tween()
	for c in get_children():
		if c is CanvasItem:
			t.parallel().tween_property(c, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", BOLD)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _box(fill: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	return b
