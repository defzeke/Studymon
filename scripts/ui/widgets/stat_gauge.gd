@tool
extends Control
## One of home's top stat gauges: an icon on an off-white disc, ringed by an arc that fills
## clockwise from the top. A low stat turns the ring coral and pulses it.
## Contract: docs/ui-and-assets.md §2 Home HUD.

const OFF := Color("F7F5EF")
const SLATE := Color("29383A")
const CORAL := Color("C97970")
const TRACK := Color(0.1608, 0.2196, 0.2275, 0.15)
const RING := 7.0
const LOW := 0.25

@export var icon: Texture2D
@export var color := Color("4F8F89")
@export_range(0.0, 1.0) var value := 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if absf(v - value) > 0.002:
			value = v
			queue_redraw()

func _process(_delta: float) -> void:
	if value < LOW:
		queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	draw_circle(c + Vector2(0, 3), r, Color(SLATE, 0.2))
	draw_circle(c, r, OFF)
	var ring_r := r - RING / 2.0 - 1.5
	draw_arc(c, ring_r, 0.0, TAU, 48, TRACK, RING, true)
	if value > 0.0:
		var ring := color
		if value < LOW:
			ring = CORAL.lerp(OFF, 0.35 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)))
		draw_arc(c, ring_r, -PI / 2.0, -PI / 2.0 + TAU * value, 48, ring, RING, true)
	draw_arc(c, r, 0.0, TAU, 48, SLATE, 3.0, true)
	if icon:
		var s := (r - RING - 4.0) * 1.55
		draw_texture_rect(icon, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false)
