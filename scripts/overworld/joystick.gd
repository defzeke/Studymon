extends Control
## On-screen thumbstick for the overworld. `output` is the stick vector, length 0..1 (screen axes:
## +x right, +y down). Touch arrives as emulated mouse events, so one finger drives it.

const BASE_RADIUS := 120.0
const KNOB_RADIUS := 52.0
const DEAD_ZONE := 0.15
const BASE_FILL := Color(0.1608, 0.2196, 0.2275, 0.35)
const BASE_RING := Color(0.9686, 0.9608, 0.9373, 0.8)
const KNOB_FILL := Color(0.9686, 0.9608, 0.9373, 0.95)
const KNOB_RING := Color(0.3098, 0.5608, 0.5373, 1)

var output := Vector2.ZERO
var _knob := Vector2.ZERO
var _held := false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_held = event.pressed
		_drag(event.position if _held else size / 2.0)
		accept_event()
	elif event is InputEventMouseMotion and _held:
		_drag(event.position)
		accept_event()

func _drag(pos: Vector2) -> void:
	_knob = (pos - size / 2.0).limit_length(BASE_RADIUS)
	var v := _knob / BASE_RADIUS
	output = v if v.length() > DEAD_ZONE else Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	draw_circle(c, BASE_RADIUS, BASE_FILL)
	draw_arc(c, BASE_RADIUS, 0.0, TAU, 64, BASE_RING, 4.0, true)
	draw_circle(c + _knob, KNOB_RADIUS, KNOB_FILL)
	draw_arc(c + _knob, KNOB_RADIUS, 0.0, TAU, 48, KNOB_RING, 5.0, true)
