extends Node3D
## Kuiz peeks in on white after the loading screen, then the tutorial (tutorial.gd) runs on top,
## then the home loop (home.gd). Once the tutorial is done this session, the scene opens straight
## into the Study Room. This node owns Kuiz (the artifact look, clips, stage moves, where it looks)
## and the rooms behind it.
## Rendering mirrors the KUIZMON Pet Bot artifact: docs/ui-and-assets.md §2 peek.tscn.

signal peeked

const PEEK := "Peek_Surprise"
const IDLE := "Idle"
# State_* clips are moods (charging, hungry, sick…): they loop for as long as they are asked for.
const STATE_PREFIX := "State_"
const BLEND_TIME := 0.18
const INK := Color("29383A")
const FLAT_SELF_LIT := 0.85
# 8.6 * tan(12°): visible half-height of the artifact framing the peek clip was authored for.
const AUTHORED_HALF_HEIGHT := 1.828
const HEAD_REST_Y := 0.9
# Stage poses: standing in a room behind the dialogue box, and hovering close to the screen.
const ROOM_SCALE := 0.7
const ROOM_Y := -0.33
const CLOSE_SCALE := 1.05
const CLOSE_Y := 0.0
const JUMP_HEIGHT := 0.9
const WALK_OFF_X := 3.6
const WALK_TIME := 0.55
const LEAN := 0.12
const HOP := 0.18
const HOVER := 0.06
const FADE_TIME := 0.35
const ROOM_NAMES := {
	"StudyRoom": "The Study Room",
	"MaintenanceBay": "The Maintenance Bay",
	"DataKitchen": "The Data Kitchen",
	"Playroom": "The Playroom",
}
# Lights off in the Study Room: light and ambient energy scale, and the night art's fade time.
const DARK := 0.3
const LIGHTS_TIME := 0.6
# Looking at a screen point: the most Kuiz turns (radians), and how fast it follows.
const LOOK_YAW := 0.55
const LOOK_PITCH := 0.3
const LOOK_SPEED := 8.0
# Kuiz's head centre sits this far above the stage origin, and fills this radius (model units).
const HEAD_CENTRE := 0.22
const HEAD_RADIUS := 1.15

@onready var camera: Camera3D = %Camera3D
@onready var stage: Node3D = %Stage
@onready var kuiz: Node3D = %Kuiz
# Inside the Kuiz glb, so found by type rather than by a path that a re-export could change.
@onready var anim: AnimationPlayer = kuiz.find_child("AnimationPlayer", true, false)
@onready var skeleton: Skeleton3D = kuiz.find_child("Skeleton3D", true, false)
@onready var shadow: MeshInstance3D = %Shadow
@onready var shadow_mat: StandardMaterial3D = shadow.mesh.material
@onready var rooms: CanvasLayer = %Rooms
@onready var room_sign: Control = %RoomSign
@onready var room_label: Label = %RoomLabel
@onready var night: Array[CanvasItem] = [%Night, %Veil]
@onready var lights: Array[DirectionalLight3D] = [%Key, %Fill, %Rim]
@onready var env: Environment = %WorldEnvironment.environment

var room := "White"

var _head := -1
# Prop blend shapes (hearts, confetti, screws, bubbles…) not keyed by the current clip.
var _props: Array = []
var _props_clip := ""
var _blend_shapes: Array = []
var _hover: Tween
var _look := Vector2.INF
var _energy: Array[float] = []
var _ambient := 0.0

func _ready() -> void:
	MusicManager.play_main_room()
	for mesh_instance: MeshInstance3D in kuiz.find_children("*", "MeshInstance3D", true, false):
		var outline: float = mesh_instance.get_meta("extras", {}).get("outline", 0.0)
		if outline > 0.0:
			mesh_instance.material_overlay = _ink(outline)
		for i in mesh_instance.get_surface_override_material_count():
			var mat := mesh_instance.get_active_material(i) as BaseMaterial3D
			if mat:
				_apply_extras(mat)
		for i in mesh_instance.get_blend_shape_count():
			var track := "%s:%s" % [kuiz.get_path_to(mesh_instance), mesh_instance.mesh.get_blend_shape_name(i)]
			_blend_shapes.append([mesh_instance, i, track])
	_head = skeleton.find_bone("Head")
	anim.get_animation(IDLE).loop_mode = Animation.LOOP_LINEAR
	for clip in anim.get_animation_list():
		if clip.begins_with(STATE_PREFIX):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.playback_default_blend_time = BLEND_TIME
	for light in lights:
		_energy.append(light.light_energy)
	_ambient = env.ambient_light_energy
	if GameState.tutorial_done:
		anim.play(IDLE)
		stage.scale = Vector3.ONE * ROOM_SCALE
		stage.position.y = ROOM_Y
		show_room("StudyRoom", true)
		return
	anim.play(PEEK)
	await anim.animation_finished
	kuiz.position.y = 0.0
	anim.play(IDLE)
	peeked.emit()

# The peek clip is authored for a wider framing; re-anchor it to this screen's bottom edge so Kuiz
# rises from it, and fade the contact shadow while the head is low.
func _process(delta: float) -> void:
	var head_y := skeleton.get_bone_pose_position(_head).y
	var peek := 0.0
	if anim.current_animation == PEEK:
		peek = clampf(HEAD_REST_Y - head_y, 0.0, 1.0)
		var view := get_viewport().get_visible_rect().size
		var half_height := (camera.position.z - 1.0) * tan(deg_to_rad(camera.fov) / 2.0) * view.y / view.x
		kuiz.position.y = (AUTHORED_HALF_HEIGHT - half_height) * peek
	var spread := 1.0 / (1.0 + maxf(0.0, head_y - HEAD_REST_Y + kuiz.position.y) * 1.6)
	shadow.scale = Vector3(spread, 1.0, spread)
	shadow_mat.albedo_color.a = (0.45 + 0.55 * spread) * (1.0 - minf(1.0, peek * 1.5))
	_hide_props()
	var yaw := 0.0
	var pitch := 0.0
	if _look != Vector2.INF:
		var centre := head_point()
		yaw = clampf((_look.x - centre.x) / 300.0, -1.0, 1.0) * LOOK_YAW
		pitch = clampf((_look.y - centre.y) / 400.0, -1.0, 1.0) * LOOK_PITCH
	var follow := minf(1.0, LOOK_SPEED * delta)
	stage.rotation.y = lerp_angle(stage.rotation.y, yaw, follow)
	stage.rotation.x = lerpf(stage.rotation.x, pitch, follow)

# A clip only keys its own props, so a prop shown by an earlier clip would otherwise freeze on
# screen. This runs before the AnimationPlayer (a child) each frame: an outgoing clip still fades
# its props during the blend, and after that they stay at 0.
func _hide_props() -> void:
	if anim.current_animation != _props_clip:
		_props_clip = anim.current_animation
		_props.clear()
		var clip := anim.get_animation(_props_clip) if _props_clip else null
		for shape: Array in _blend_shapes:
			if clip == null or clip.find_track(NodePath(shape[2]), Animation.TYPE_BLEND_SHAPE) == -1:
				_props.append(shape)
	for shape: Array in _props:
		(shape[0] as MeshInstance3D).set_blend_shape_value(shape[1], 0.0)

## Plays a clip: a one-shot falls back into Idle, a State_* mood keeps looping.
func act(clip: String) -> void:
	anim.clear_queue()
	anim.play(clip)
	if not clip.begins_with(STATE_PREFIX):
		anim.queue(IDLE)

## Hops up on white; `at_top` swaps the background, and Kuiz lands at room size.
func jump(at_top: Callable) -> void:
	var t := create_tween()
	t.tween_property(kuiz, "position:y", JUMP_HEIGHT, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(at_top)
	t.tween_property(kuiz, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(stage, "scale", Vector3.ONE * ROOM_SCALE, 0.4).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(stage, "position:y", ROOM_Y, 0.4).set_trans(Tween.TRANS_SINE)
	await t.finished

## "Follow me": hops off to one side (`dir` 1 = right), `midway` swaps the room, and Kuiz hops in
## from the other.
func walk(midway: Callable, dir := 1) -> void:
	var hops := create_tween().set_loops(4)
	hops.tween_property(kuiz, "position:y", HOP, WALK_TIME / 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hops.tween_property(kuiz, "position:y", 0.0, WALK_TIME / 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var t := create_tween()
	t.tween_property(stage, "rotation:z", -LEAN * dir, 0.15)
	t.parallel().tween_property(stage, "position:x", WALK_OFF_X * dir, WALK_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(midway)
	t.tween_callback(func() -> void: stage.position.x = -WALK_OFF_X * dir)
	t.tween_property(stage, "position:x", 0.0, WALK_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(stage, "rotation:z", 0.0, 0.2)
	await t.finished

## Drifts up to the screen and keeps hovering there.
func come_close() -> void:
	var t := create_tween().set_parallel()
	t.tween_property(stage, "scale", Vector3.ONE * CLOSE_SCALE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(stage, "position:y", CLOSE_Y, 0.6).set_trans(Tween.TRANS_SINE)
	await t.finished
	_hover = create_tween().set_loops()
	_hover.tween_property(kuiz, "position:y", HOVER, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hover.tween_property(kuiz, "position:y", 0.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Stops hovering and settles back to room size, standing in the room.
func to_room_pose() -> void:
	if _hover:
		_hover.kill()
		_hover = null
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	t.tween_property(stage, "scale", Vector3.ONE * ROOM_SCALE, 0.5)
	t.tween_property(stage, "position:y", ROOM_Y, 0.5)
	t.tween_property(kuiz, "position:y", 0.0, 0.5)
	await t.finished

## Cross-fades to a room and names it on the sign.
func show_room(room_name: String, instant := false) -> void:
	var next: CanvasItem = rooms.get_node(room_name)
	var old: CanvasItem = rooms.get_node(room)
	room = room_name
	rooms.move_child(next, -1)
	if instant:
		next.modulate.a = 1.0
		if old != next:
			old.modulate.a = 0.0
		room_label.text = ROOM_NAMES[room_name]
		room_sign.modulate.a = 1.0
		return
	_fade(next, 1.0).finished.connect(func() -> void:
		if old != next:
			old.modulate.a = 0.0)
	var t := create_tween()
	t.tween_property(room_sign, "modulate:a", 0.0, FADE_TIME * room_sign.modulate.a)
	t.tween_callback(func() -> void: room_label.text = ROOM_NAMES[room_name])
	t.tween_property(room_sign, "modulate:a", 1.0, FADE_TIME)

## Study Room lights: off dims the 3D lights and fades in the night art, so only Kuiz's self-lit
## face (and its charging bolt) glows.
func set_lights(on: bool) -> void:
	var k := 1.0 if on else DARK
	var t := create_tween().set_parallel()
	for i in lights.size():
		t.tween_property(lights[i], "light_energy", _energy[i] * k, LIGHTS_TIME)
	t.tween_property(env, "ambient_light_energy", _ambient * k, LIGHTS_TIME)
	for item in night:
		t.tween_property(item, "modulate:a", 0.0 if on else 1.0, LIGHTS_TIME)

## Turns Kuiz's head toward a screen point; look_ahead() turns it back.
func look_at_point(point: Vector2) -> void:
	_look = point

func look_ahead() -> void:
	_look = Vector2.INF

## Screen-space centre and radius of Kuiz's head, for drops and hits.
func head_point() -> Vector2:
	return camera.unproject_position(kuiz.global_position + Vector3.UP * HEAD_CENTRE * stage.scale.y)

func head_radius() -> float:
	var top := camera.unproject_position(kuiz.global_position + Vector3.UP * (HEAD_CENTRE + HEAD_RADIUS) * stage.scale.y)
	return head_point().distance_to(top)

func hits(point: Vector2) -> bool:
	return point.distance_to(head_point()) < head_radius()

func _fade(item: CanvasItem, alpha: float) -> Tween:
	var t := create_tween()
	t.tween_property(item, "modulate:a", alpha, FADE_TIME)
	return t

# glTF vertex colours are imported but left off; extras carry the artifact's shading hints.
func _apply_extras(mat: BaseMaterial3D) -> void:
	mat.vertex_color_use_as_albedo = true
	var extras: Dictionary = mat.get_meta("extras", {})
	if extras.get("selfLit", 0.0) >= FLAT_SELF_LIT:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if extras.get("blend", "") == "additive":
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

# Inverted hull: the mesh grown along its normals, front faces culled, so only the rim shows.
func _ink(width: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.grow = true
	mat.grow_amount = width
	mat.albedo_color = INK
	return mat
