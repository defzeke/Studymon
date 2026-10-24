extends Control
## Animated confirm / notice pop-up: the screen dims, the card pops in, a button or Esc closes it.
## ConfirmModal.open(self, "Delete?", "…", "Delete", on_confirm, true); an empty cancel_text makes a notice.

const CORAL := Color("C97970")
const AMBER := Color("D6A85F")
const SLATE := Color("29383A")
const BOLD: Font = preload("res://assets/fonts/JosefinSans-Bold.ttf")
const THEME: Theme = preload("res://assets/theme/app_theme.tres")

var _dim: ColorRect
var _card: PanelContainer
var _closing := false

## Shows the modal over `host`; `on_confirm` runs after the card has closed.
static func open(host: Node, title: String, message: String, confirm_text := "OK",
		on_confirm := Callable(), danger := false, cancel_text := "Cancel") -> Control:
	var m := new()
	host.add_child(m)
	m._build(title, message, confirm_text, on_confirm, danger, cancel_text)
	return m

func _build(title: String, message: String, confirm_text: String, on_confirm: Callable,
		danger: bool, cancel_text: String) -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(SLATE, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(560, 0)
	center.add_child(_card)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	_card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	pad.add_child(box)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", BOLD)
	title_label.add_theme_font_size_override("font_size", 40)
	title_label.add_theme_color_override("font_color", CORAL if danger else AMBER)
	box.add_child(title_label)
	var body := Label.new()
	body.text = message
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(500, 0)
	box.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var cancel: Button = null
	if cancel_text != "":
		cancel = _button(cancel_text, row)
		cancel.pressed.connect(_close.bind(Callable()))
	var confirm := _button(confirm_text, row)
	confirm.pressed.connect(_close.bind(on_confirm))
	if danger:
		tint_danger(confirm)
	(cancel if cancel != null else confirm).grab_focus()
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.85, 0.85)
	_pop_in.call_deferred()

func _button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b

## Soft Coral version of the theme's button, so the dangerous choice reads as one.
static func tint_danger(b: Button) -> void:
	for s in ["normal", "hover", "pressed"]:
		var sb := THEME.get_stylebox(s, "Button").duplicate() as StyleBoxFlat
		sb.bg_color = CORAL.lightened(0.15) if s == "hover" else CORAL
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_color_override("font_pressed_color", THEME.get_color("font_color", "Button"))

func _pop_in() -> void:
	_card.pivot_offset = _card.size / 2.0
	var t := create_tween().set_parallel().set_ignore_time_scale(true)
	t.tween_property(_dim, "color:a", 0.72, 0.18)
	t.tween_property(_card, "modulate:a", 1.0, 0.18)
	t.tween_property(_card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _close(action: Callable) -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween().set_parallel().set_ignore_time_scale(true)
	t.tween_property(_dim, "color:a", 0.0, 0.14)
	t.tween_property(_card, "modulate:a", 0.0, 0.14)
	t.tween_property(_card, "scale", Vector2(0.92, 0.92), 0.14)
	await t.finished
	queue_free()
	if action.is_valid():
		action.call()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close(Callable())
