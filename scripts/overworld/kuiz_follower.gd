extends Node3D
## Kuiz following the explorer around the island, like a partner in a Pokémon game: it stays a
## little behind, on the path the explorer actually walked (so it rounds corners instead of cutting
## through walls), hops along while moving, hovers and bobs when still, faces where it goes, and
## turns to the explorer when they stop. Contract: docs/systems/overworld.md §3 Kuiz.

const KUIZ: PackedScene = preload("res://assets/models/kuiz.glb")
const INK_OUTLINE: StandardMaterial3D = preload("res://assets/materials/ink_outline.tres")
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
## Moving, it waddles above HOP_FROM u/s, blending at HOP_BLEND: one hop per HOP_LENGTH travelled, from
## the ground (GROUND_GAP under its hover) up by HOP_HEIGHT, landing on alternate sides WADDLE_WIDTH
## off its path, leaning WADDLE_ROLL and toeing out WADDLE_TURN (radians) that way, and squashing by up
## to SQUASH. Lengths are for HEIGHT; waddle() scales them to Kuiz's size.
const HOP_LENGTH := 0.7
const HOP_HEIGHT := 0.14
const GROUND_GAP := 0.08
const WADDLE_WIDTH := 0.13
const WADDLE_ROLL := 0.3
const WADDLE_TURN := 0.25
const SQUASH := 0.16
const HOP_FROM := 0.4
const HOP_BLEND := 6.0
## How quickly it catches up with its spot and turns (per second, exponential).
const CATCH_UP := 6.0
const TURN := 8.0
## A breadcrumb is dropped each time the explorer has moved this far.
const CRUMB := 0.08
# The same look Kuiz has at home and in battle (arena_stage.gd _dress): an ink outline, vertex
# colours, self-lit parts.
const FLAT_SELF_LIT := 0.85

@export var player: Node3D

var _model: Node3D
var _anim: AnimationPlayer
var _trail: Array[Vector3] = []
var _time := 0.0
var _hop_phase := 0.0
var _hop_blend := 0.0

func _ready() -> void:
	_model = KUIZ.instantiate()
	add_child(_model)
	dress(_model, OUTLINE_BOOST)
	_anim = _model.find_child("AnimationPlayer", true, false)
	_anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")
	waddle(_model, 0.0, 0.0, HEIGHT)
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
	var bob := sin(_time * BOB_SPEED) * BOB * (1.0 - _hop_blend)
	var goal := target + Vector3.UP * (HOVER + bob)
	var step := goal - global_position
	global_position += step * minf(1.0, CATCH_UP * delta)
	var flat := Vector2(step.x, step.z)
	var moved := flat.length() * minf(1.0, CATCH_UP * delta)
	_hop_phase += moved / HOP_LENGTH * PI
	_hop_blend = move_toward(_hop_blend, 1.0 if moved / delta > HOP_FROM else 0.0, HOP_BLEND * delta)
	waddle(_model, _hop_phase, _hop_blend, HEIGHT)
	var face: float
	if flat.length() > 0.02:
		face = atan2(step.x, step.z)
	else:
		var to_player := at - global_position
		face = atan2(to_player.x, to_player.z)
	rotation.y = lerp_angle(rotation.y, face, minf(1.0, TURN * delta))

## Poses a dressed kuiz.glb at `size` tall mid-waddle: `phase` advances PI per hop, `blend` 0 is its
## plain hover. It moves the model, not its parent, whose smoothing would flatten the hop.
static func waddle(model: Node3D, phase: float, blend: float, size: float) -> void:
	var height := absf(sin(phase))
	var side := cos(phase) * blend
	var squash := blend * pow(1.0 - height, 3.0) * SQUASH
	var ratio := size / HEIGHT
	model.position = Vector3(side * WADDLE_WIDTH, blend * (height * HOP_HEIGHT - GROUND_GAP), 0.0) * ratio
	model.rotation = Vector3(0.0, side * WADDLE_TURN, -side * WADDLE_ROLL)
	model.scale = Vector3(1.0 + squash, 1.0 - squash, 1.0 + squash) * size / MODEL_HEIGHT

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

## Gives a kuiz.glb instance its look; `outline_boost` thickens the ink for a small Kuiz.
static func dress(model: Node3D, outline_boost: float) -> void:
	# The forehead gem rides the Antenna bones, which every clip swings; keep them at rest (peek.gd).
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	for clip in anim.get_animation_list():
		var a := anim.get_animation(clip)
		for t in a.get_track_count():
			if str(a.track_get_path(t)).contains(":Antenna_"):
				a.track_set_enabled(t, false)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var outline := float(mi.get_meta("extras", {}).get("outline", 0.0))
		if outline > 0.0:
			var ink := INK_OUTLINE.duplicate() as StandardMaterial3D
			ink.grow_amount = outline * outline_boost
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
