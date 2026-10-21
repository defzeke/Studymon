extends CharacterBody3D
## Overworld explorer: walks where the joystick (or arrows/WASD) points, turns to face the way it
## goes, and plays Idle / Walk / Run. Contract: docs/systems/overworld.md §3.
## Moves flat against the obstacle layer; height comes from a ray onto the ground layer, so road
## curbs never stop it, and a step that would land below the waterline is refused.

const WALK_SPEED := 2.2
const RUN_SPEED := 4.2
const RUN_FROM := 0.75
const TURN_SPEED := 12.0
const BLEND := 0.15
const WATERLINE := -0.05
const GROUND_LAYER := 1

@export var joystick: Control

@onready var boy: Node3D = $Boy
@onready var anim: AnimationPlayer = $Boy/AnimationPlayer

## Set while an encounter panel is open.
var locked := false

func _ready() -> void:
	for clip in ["Idle", "Walk", "Run"]:
		anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.play("Idle")

func _physics_process(delta: float) -> void:
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
		boy.rotation.y = lerp_angle(boy.rotation.y, atan2(dir.x, dir.z), minf(1.0, TURN_SPEED * delta))
	var clip := "Idle" if strength == 0.0 else ("Run" if strength >= RUN_FROM else "Walk")
	if anim.current_animation != clip:
		anim.play(clip, BLEND)

func _ground_y(at: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at + Vector3.DOWN * 5.0, GROUND_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position.y if hit else NAN
