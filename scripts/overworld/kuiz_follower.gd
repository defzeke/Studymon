extends Node3D
## Kuiz following the explorer around the island, like a partner in a Pokémon game: it floats a
## little behind, on the path the explorer actually walked (so it rounds corners instead of cutting
## through walls), bobs while it hovers, faces where it goes, and turns to the explorer when they
## stop. Contract: docs/systems/overworld.md §3 Kuiz.

const KUIZ: PackedScene = preload("res://assets/models/kuiz.glb")
## Kuiz's height on the island (the glb is ~2.35 units tall, ears included).
const HEIGHT := 0.6
const MODEL_HEIGHT := 2.35
## The glb's outline widths are sized for Kuiz filling the home screen; this small it needs them
## thicker to read.
const OUTLINE_BOOST := 2.5
## How far back along the explorer's path Kuiz stays, and how high it floats over the ground.
const FOLLOW_DISTANCE := 0.85
const HOVER := 0.32
const BOB := 0.05
const BOB_SPEED := 2.6
## How quickly it catches up with its spot and turns (per second, exponential).
const CATCH_UP := 6.0
const TURN := 8.0
## A breadcrumb is dropped each time the explorer has moved this far.
const CRUMB := 0.08
# The same look Kuiz has at home and in battle (arena_stage.gd _dress): an ink outline, vertex
# colours, self-lit parts.
const INK := Color("29383A")
const FLAT_SELF_LIT := 0.85

@export var player: Node3D

var _model: Node3D
var _anim: AnimationPlayer
var _trail: Array[Vector3] = []
var _time := 0.0

func _ready() -> void:
	_model = KUIZ.instantiate()
	_model.scale = Vector3.ONE * HEIGHT / MODEL_HEIGHT
	add_child(_model)
	_dress(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	# The forehead gem rides the Antenna bones, which every clip swings; keep them at rest (peek.gd).
	var idle := _anim.get_animation("Idle")
	for t in idle.get_track_count():
		if str(idle.track_get_path(t)).contains(":Antenna_"):
			idle.track_set_enabled(t, false)
	idle.loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")
	place_behind()

## Starts Kuiz just behind the explorer (on entering the map, or after the explorer is moved).
func place_behind() -> void:
	var at := player.global_position
	_trail = [at + Vector3(0, 0, FOLLOW_DISTANCE), at]
	global_position = _trail[0] + Vector3.UP * HOVER

func _physics_process(delta: float) -> void:
	_time += delta
	var at := player.global_position
	if at.distance_to(_trail[-1]) >= CRUMB:
		_trail.append(at)
	var target := _spot_behind()
	var bob := sin(_time * BOB_SPEED) * BOB
	var goal := target + Vector3.UP * (HOVER + bob)
	var step := goal - global_position
	global_position += step * minf(1.0, CATCH_UP * delta)
	var flat := Vector2(step.x, step.z)
	var face: float
	if flat.length() > 0.02:
		face = atan2(step.x, step.z)
	else:
		var to_player := at - global_position
		face = atan2(to_player.x, to_player.z)
	rotation.y = lerp_angle(rotation.y, face, minf(1.0, TURN * delta))

# The point FOLLOW_DISTANCE back along the trail from the explorer.
func _spot_behind() -> Vector3:
	var left := FOLLOW_DISTANCE
	var i := _trail.size() - 1
	var point := _trail[i]
	while i > 0:
		var seg := _trail[i - 1] - _trail[i]
		var length := seg.length()
		if length >= left:
			point = _trail[i] + seg / length * left
			break
		left -= length
		point = _trail[i - 1]
		i -= 1
	# Crumbs behind that point are never needed again.
	if i > 1:
		_trail = _trail.slice(i - 1)
	return point

func _dress(model: Node3D) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var outline := float(mi.get_meta("extras", {}).get("outline", 0.0))
		if outline > 0.0:
			var ink := StandardMaterial3D.new()
			ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ink.cull_mode = BaseMaterial3D.CULL_FRONT
			ink.grow = true
			ink.grow_amount = outline * OUTLINE_BOOST
			ink.albedo_color = INK
			mi.material_overlay = ink
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var extras: Dictionary = mat.get_meta("extras", {})
			mat.vertex_color_use_as_albedo = true
			if float(extras.get("selfLit", 0.0)) >= FLAT_SELF_LIT:
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if str(extras.get("blend", "")) == "additive":
				mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
