extends CanvasLayer
## "Turn your phone" card shown when the game switches orientation (into and out of the landscape
## region map). It lives on the root, so it survives the scene change, shows a phone turning the
## way to hold it, and fades away after a moment or on a tap. Callers preload this script.
## Contract: docs/ui-and-assets.md §2 region_map.tscn.

const PHONE: Texture2D = preload("res://assets/sprites/ui/icon_phone.svg")
const TURN: Texture2D = preload("res://assets/sprites/ui/icon_turn.svg")
const BOLD: Font = preload("res://assets/fonts/JosefinSans-Bold.ttf")
const OFF := Color("F7F5EF")
const SLATE := Color("29383A")
const SHOW_TIME := 2.2

var _landscape := true
var _closing := false
var _root: Control

## Shows the card for holding the phone sideways (`landscape`) or upright; deferred, so it can be
## called while a scene is leaving the tree.
static func open(tree: SceneTree, landscape: bool) -> void:
	var prompt := new()
	prompt._landscape = landscape
	tree.root.add_child.call_deferred(prompt)

func _ready() -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(SLATE, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	var turn := _icon(TURN, Vector2(150, 75))
	box.add_child(turn)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(200, 200)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(holder)
	var phone := _icon(PHONE, Vector2(200, 200))
	phone.pivot_offset = Vector2(100, 100)
	holder.add_child(phone)
	var label := Label.new()
	label.text = "Turn your phone sideways" if _landscape else "Turn your phone upright"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BOLD)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", OFF)
	box.add_child(label)
	# The phone turns a quarter clockwise, from how it is held now to how to hold it.
	var from := 0.0 if _landscape else PI / 2.0
	phone.rotation = from
	turn.flip_h = not _landscape
	var t := create_tween().set_loops(2)
	t.tween_interval(0.25)
	t.tween_property(phone, "rotation", PI / 2.0 - from, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.35)
	t.tween_callback(func() -> void: phone.rotation = from)
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.2)
	get_tree().create_timer(SHOW_TIME).timeout.connect(_close)

func _icon(tex: Texture2D, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = size
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _close() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.25)
	t.tween_callback(queue_free)
