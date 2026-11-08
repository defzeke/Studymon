class_name ConfirmModal
extends Control
## Animated confirm / notice pop-up: the screen dims, the card pops in, a button or Esc closes it.
## ConfirmModal.open(self, "Delete?", "…", "Delete", on_confirm, true); an empty cancel_text makes a notice.
## Its look is confirm_modal.tscn; this fills the text. Contract: docs/ui-and-assets.md §2 Pop-ups.

const SCENE := "res://scenes/ui/widgets/confirm_modal.tscn"

@onready var _dim: ColorRect = %Dim
@onready var _card: PanelContainer = %Card
var _closing := false

## Shows the modal over `host`; `on_confirm` runs after the card has closed.
static func open(host: Node, title: String, message: String, confirm_text := "OK",
		on_confirm := Callable(), danger := false, cancel_text := "Cancel") -> Control:
	var m: ConfirmModal = (load(SCENE) as PackedScene).instantiate()
	host.add_child(m)
	m._fill(title, message, confirm_text, on_confirm, danger, cancel_text)
	return m

func _fill(title: String, message: String, confirm_text: String, on_confirm: Callable,
		danger: bool, cancel_text: String) -> void:
	%Title.text = title
	if danger:
		%Title.add_theme_color_override("font_color", Palette.CORAL)
		tint_danger(%Confirm)
	%Body.text = message
	var cancel: Button = %Cancel
	cancel.visible = cancel_text != ""
	cancel.text = cancel_text
	cancel.pressed.connect(_close.bind(Callable()))
	%Confirm.text = confirm_text
	%Confirm.pressed.connect(_close.bind(on_confirm))
	(cancel if cancel.visible else %Confirm as Button).grab_focus()
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.85, 0.85)
	_pop_in.call_deferred()

## Soft Coral version of the theme's button, so the dangerous choice reads as one.
static func tint_danger(b: Button) -> void:
	b.theme_type_variation = &"MenuDanger"

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
