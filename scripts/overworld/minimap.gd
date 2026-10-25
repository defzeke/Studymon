extends PanelContainer
## The top-left minimap: the whole island seen from straight above, with dots for the explorer, the
## trainers, the gyms and the Champion. Contract: docs/systems/overworld.md §3 Minimap.
## The island is rendered once into a small SubViewport that shares the map's World3D; its camera
## only sees MINIMAP_LAYER, which the Map's meshes are added to, so the explorer, labels and weather
## stay out of the picture. The dots are drawn in 2D every frame on top.

const MINIMAP_LAYER := 1 << 10
## Meshes wider than this (world units) are sea, not island.
const HORIZON := 150.0
const OFF := Color("F7F5EF")
const SLATE := Color("29383A")
const TEAL := Color("4F8F89")
const AMBER := Color("D6A85F")
const CORAL := Color("C97970")

@onready var map: Node3D = %Map
@onready var player: Node3D = %Player
@onready var trainers: Node3D = %Trainers
@onready var gyms: Node3D = %Gyms
@onready var viewport: SubViewport = %MinimapViewport
@onready var camera: Camera3D = %MinimapCamera
@onready var dots: Control = %MinimapDots

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
	dots.draw.connect(_draw_dots)

func _process(_delta: float) -> void:
	dots.queue_redraw()

func _to_dots(world: Vector3) -> Vector2:
	return camera.unproject_position(world) * dots.size / Vector2(viewport.size)

func _draw_dots() -> void:
	for t in trainers.get_children():
		var at_t := _to_dots(t.global_position)
		dots.draw_circle(at_t, 4.0, SLATE)
		dots.draw_circle(at_t, 2.5, OFF)
	for g in gyms.get_children():
		var champ := str(g.get("text")).begins_with("CHAMPION")
		var at := _to_dots(g.global_position)
		dots.draw_circle(at, 7.0, SLATE)
		dots.draw_circle(at, 5.0, CORAL if champ else AMBER)
	var me := _to_dots(player.global_position)
	dots.draw_circle(me, 8.0, OFF)
	dots.draw_circle(me, 5.5, TEAL)
