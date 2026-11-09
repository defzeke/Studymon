extends PanelContainer
## The top-left minimap: the whole island seen from straight above, with dots for the explorer, the
## trainers, the gyms and the Champion. A tap opens it large over the map; X or a tap outside closes
## it. Contract: docs/systems/overworld.md §3 Minimap.
## The island is rendered once into a SubViewport that shares the map's World3D, large enough for the
## big view; its camera only sees MINIMAP_LAYER, which the Map's meshes are added to, so the explorer,
## labels and weather stay out of the picture. The dots are drawn in 2D every frame on top.

const MINIMAP_LAYER := 1 << 10
## Meshes wider than this (world units) are sea, not island.
const HORIZON := 150.0
## The big view's dots are this much larger, and its opening and closing take this long.
const BIG_DOTS := 1.7
const OPEN_TIME := 0.28
const DIM_ALPHA := 0.6
const SMALL_SCALE := 0.3

@onready var map: Node3D = %Map
@onready var player: Node3D = %Player
@onready var trainers: Node3D = %Trainers
@onready var gyms: Node3D = %Gyms
@onready var viewport: SubViewport = %MinimapViewport
@onready var camera: Camera3D = %MinimapCamera
@onready var dots: Control = %MinimapDots
@onready var overlay: ColorRect = %MapOverlay
@onready var big_card: Control = %MapCard
@onready var big_dots: Control = %BigDots

var _moving := false

func _ready() -> void:
	var box := AABB()
	var first := true
	for n in map.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		vi.layers |= MINIMAP_LAYER
		var b := vi.global_transform * vi.get_aabb()
		# The water and seabed planes run to the horizon: drawn, but left out of the framing.
		if maxf(b.size.x, b.size.z) > HORIZON:
			continue
		box = b if first else box.merge(b)
		first = false
	camera.cull_mask = MINIMAP_LAYER
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(box.size.x, box.size.z) * 1.04
	camera.far = box.size.y + 100.0
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)),
		box.get_center() + Vector3.UP * (box.size.y + 50.0))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	%MiniPicture.texture = viewport.get_texture()
	%BigPicture.texture = viewport.get_texture()
	dots.draw.connect(_draw_dots.bind(dots, 1.0))
	big_dots.draw.connect(_draw_dots.bind(big_dots, BIG_DOTS))
	%MapClose.pressed.connect(_close)
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if _tapped(event):
			_close())

func _tapped(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT

func _gui_input(event: InputEvent) -> void:
	if _tapped(event):
		accept_event()
		_open()

# Not over an encounter panel or the explorer picker, which lock the explorer too.
func _open() -> void:
	if player.locked or _moving:
		return
	_moving = true
	player.locked = true
	overlay.color.a = 0.0
	big_card.modulate.a = 0.0
	overlay.show()
	# The card has no size until the container lays it out.
	await get_tree().process_frame
	big_card.pivot_offset = get_global_rect().get_center() - big_card.global_position
	var t := create_tween().set_parallel()
	t.tween_property(overlay, "color:a", DIM_ALPHA, OPEN_TIME)
	t.tween_property(big_card, "modulate:a", 1.0, OPEN_TIME * 0.6)
	t.tween_property(big_card, "scale", Vector2.ONE, OPEN_TIME).from(Vector2.ONE * SMALL_SCALE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	_moving = false

func _close() -> void:
	if _moving:
		return
	_moving = true
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(overlay, "color:a", 0.0, OPEN_TIME)
	t.tween_property(big_card, "modulate:a", 0.0, OPEN_TIME)
	t.tween_property(big_card, "scale", Vector2.ONE * SMALL_SCALE, OPEN_TIME)
	await t.finished
	overlay.hide()
	player.locked = false
	_moving = false

func _process(_delta: float) -> void:
	dots.queue_redraw()
	if overlay.visible:
		big_dots.queue_redraw()

func _draw_dots(on: Control, k: float) -> void:
	for t in trainers.get_children():
		var at_t := _to_dots(t.global_position, on)
		on.draw_circle(at_t, 4.0 * k, Palette.SLATE)
		on.draw_circle(at_t, 2.5 * k, Palette.OFF_WHITE)
	for g in gyms.get_children():
		var champ := str(g.get("text")).begins_with("CHAMPION")
		var at := _to_dots(g.global_position, on)
		on.draw_circle(at, 7.0 * k, Palette.SLATE)
		on.draw_circle(at, 5.0 * k, Palette.CORAL if champ else Palette.AMBER)
	var me := _to_dots(player.global_position, on)
	on.draw_circle(me, 8.0 * k, Palette.OFF_WHITE)
	on.draw_circle(me, 5.5 * k, Palette.TEAL)

func _to_dots(world: Vector3, on: Control) -> Vector2:
	return camera.unproject_position(world) * on.size / Vector2(viewport.size)
