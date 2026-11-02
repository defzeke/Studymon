extends CharacterBody3D
## Overworld explorer: walks where the joystick (or arrows/WASD) points, turns to face the way it
## goes, and plays Idle / Walk / Run. Contract: docs/systems/overworld.md §3.
## Moves flat against the obstacle layer; height comes from a ray onto the ground layer, so road
## curbs never stop it, and a step that would land below the waterline is refused.

const WALK_SPEED := 1.8
const RUN_SPEED := 2.8
# The clips were timed for 2.2 (walk) / 4.2 (run) u/s; they play slower by the same share so feet
# don't slide.
const WALK_PACE := WALK_SPEED / 2.2
const RUN_PACE := RUN_SPEED / 4.2
const RUN_FROM := 0.75
const TURN_SPEED := 12.0
const BLEND := 0.15
const WATERLINE := -0.05
const GROUND_LAYER := 1
## The playable explorers (a world's `explorer` id, SessionManager.world_explorer()); both share the same rig, size and clips.
const EXPLORERS := {
	"boy": preload("res://assets/models/boy_explorer.glb"),
	"girl": preload("res://assets/models/explorer_girl.glb"),
}

@export var joystick: Control

@onready var model: Node3D = %Explorer
# Inside the explorer glb, so found by type rather than by a path a re-export could change.
@onready var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)

## Set while an encounter panel (or the explorer picker) is open.
var locked := false
var _explorer := "boy"
# Set while walk_into() moves the explorer; the stick and the ground ray are ignored meanwhile.
var _scripted := false

func _ready() -> void:
	_start_clips()

## Swaps in the chosen explorer's model, facing the same way.
func set_explorer(id: String) -> void:
	if id == _explorer or not EXPLORERS.has(id):
		return
	_explorer = id
	var next: Node3D = EXPLORERS[id].instantiate()
	next.transform = model.transform
	model.queue_free()
	model.name = "Old"
	next.name = "Explorer"
	add_child(next)
	model = next
	anim = model.find_child("AnimationPlayer", true, false)
	_start_clips()

func _start_clips() -> void:
	for clip in ["Idle", "Walk", "Run"]:
		anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.play("Idle")

## Walks the explorer straight through a building's doorway to `target` (no collision), like stepping
## inside; the map fades out once it arrives.
func walk_into(target: Vector3, time := 0.55) -> void:
	_scripted = true
	var flat := Vector3(target.x, global_position.y, target.z)
	var to := flat - global_position
	if to.length() > 0.01:
		model.rotation.y = atan2(to.x, to.z)
	anim.play("Walk", BLEND)
	anim.speed_scale = WALK_PACE
	var t := create_tween()
	t.tween_property(self, "global_position", flat, time)
	await t.finished

## Turns the explorer to face `dir` (on arriving back outside a building).
func face(dir: Vector3) -> void:
	model.rotation.y = atan2(dir.x, dir.z)

func _physics_process(delta: float) -> void:
	if _scripted:
		return
	var stick: Vector2 = joystick.output if joystick else Vector2.ZERO
	if stick == Vector2.ZERO:
		stick = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if locked:
		stick = Vector2.ZERO
	var strength := stick.length()
	var dir := Vector3(stick.x, 0.0, stick.y).normalized()
	var before := global_position
	velocity = dir * (RUN_SPEED if strength >= RUN_FROM else WALK_SPEED)
	move_and_slide()
	var ground: float = _ground_y(global_position)
	if is_nan(ground) or ground < WATERLINE:
		global_position = before
	else:
		global_position.y = ground
	if strength > 0.0:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), minf(1.0, TURN_SPEED * delta))
	var clip := "Idle" if strength == 0.0 else ("Run" if strength >= RUN_FROM else "Walk")
	if anim.current_animation != clip:
		anim.play(clip, BLEND)
		anim.speed_scale = {"Idle": 1.0, "Walk": WALK_PACE, "Run": RUN_PACE}[clip]

func _ground_y(at: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at + Vector3.DOWN * 5.0, GROUND_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position.y if hit else NAN
