class_name ButtonJuice
extends RefCounted
## One-line hover-big / press-small feedback for Buttons.
## Usage: ButtonJuice.wire(my_button)
## Disabled buttons never pop. Tween lives on the button itself (no manager).

const TWEEN_KEY := "_juice_tween"
const TWEEN_TIME := 0.1

static func wire(b: Button, hover_scale := 1.06, press_scale := 0.96) -> void:
	b.mouse_entered.connect(_pop.bind(b, hover_scale))
	b.mouse_exited.connect(_pop.bind(b, 1.0))
	b.button_down.connect(_pop.bind(b, press_scale))
	b.button_up.connect(_on_up.bind(b, hover_scale))

static func _on_up(b: Button, hover_scale: float) -> void:
	if b.disabled or not b.is_hovered():
		_pop(b, 1.0)
	else:
		_pop(b, hover_scale)

static func _pop(b: Button, target: float) -> void:
	if not is_instance_valid(b):
		return
	if b.disabled:
		target = 1.0
	if b.has_meta(TWEEN_KEY):
		var old: Tween = b.get_meta(TWEEN_KEY) as Tween
		if is_instance_valid(old):
			old.kill()
	b.pivot_offset = b.size / 2.0
	var t := b.create_tween()
	b.set_meta(TWEEN_KEY, t)
	t.tween_property(b, "scale", Vector2(target, target), TWEEN_TIME)
