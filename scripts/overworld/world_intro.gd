extends Node3D
## The walk between home and the island. Play: Kuiz's door opens and it waddles out under "Time to
## learn!", then the map opens. The map's Back (SessionManager.kuiz_going_home): the same in reverse,
## Kuiz waddles back indoors, then the pet room opens.
## Contract: docs/ui-and-assets.md §2 world_intro.tscn.

const Follower := preload("res://scripts/overworld/kuiz_follower.gd")
const MAP_SCENE := "res://scenes/overworld/region_map.tscn"
const HOME_SCENE := "res://scenes/ui/boot/peek.tscn"
const OUT_TEXT := "Time to learn!"
const HOME_TEXT := "Home sweet home!"
const KUIZ_SIZE := 0.85
# Where Kuiz stands: indoors behind the doorway, and out on the path.
const INDOORS_Z := -1.7
const OUTSIDE_Z := 4.5
const HOPS := 6
const HOP_TIME := 0.28
const DOOR_OPEN_DEG := -105.0
const DOOR_TIME := 0.4
const FADE_TIME := 0.35
# Setting off for the island: how far down the path Kuiz gets, and the fade that covers it.
const LEAVE_Z := 9.0
const LEAVE_HOPS := 4
const LEAVE_FADE_TIME := 1.1
const HOLD_TIME := 1.2
const WINDOW_DAY := Color(0.749, 0.851, 0.902)
const WINDOW_LIT := Color("D6A85F")

@onready var spot: Node3D = %KuizSpot
@onready var door: Node3D = %DoorHinge
@onready var voice: Node = %Voice
@onready var caption: Control = %Caption
@onready var fade: ColorRect = %Fade
@onready var window_glass: StandardMaterial3D = ($House/RoundGlass as MeshInstance3D).mesh.material

var _kuiz: Node3D
var _anim: AnimationPlayer
var _phase := 0.0

func _ready() -> void:
	var going_home := SessionManager.kuiz_going_home
	SessionManager.kuiz_going_home = false
	var next := HOME_SCENE if going_home else MAP_SCENE
	SessionManager.home_from_map = going_home
	SessionManager.pick_explorer = not going_home
	ResourceLoader.load_threaded_request(next)
	if going_home:
		MusicManager.play_main_room()
	else:
		MusicManager.play_overworld()
	# The mesh material is shared by every load of this scene.
	window_glass.albedo_color = WINDOW_DAY
	_kuiz = Follower.KUIZ.instantiate()
	spot.add_child(_kuiz)
	Follower.dress(_kuiz, 2.0)
	_anim = _kuiz.find_child("AnimationPlayer", true, false)
	_anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")
	voice.anim = _anim
	spot.position = Vector3(0.0, Follower.HOVER * KUIZ_SIZE / Follower.HEIGHT, OUTSIDE_Z if going_home else INDOORS_Z)
	Follower.waddle(_kuiz, 0.0, 0.0, KUIZ_SIZE)
	(%CaptionLabel as Label).text = HOME_TEXT if going_home else OUT_TEXT
	caption.modulate.a = 0.0
	# The first frames are heavy and would skip a tween started now.
	await get_tree().process_frame
	await get_tree().process_frame
	var fade_in := fade.create_tween()
	fade_in.tween_property(fade, "color:a", 0.0, FADE_TIME)
	await fade_in.finished
	if going_home:
		await _go_in()
	else:
		await _come_out()
	var out := fade.create_tween()
	if going_home:
		out.tween_property(fade, "color:a", 1.0, FADE_TIME)
	else:
		_waddle_to(LEAVE_Z, LEAVE_HOPS)
		var hide_text := create_tween()
		hide_text.tween_property(caption, "modulate:a", 0.0, 0.3)
		out.tween_property(fade, "color:a", 1.0, LEAVE_FADE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await out.finished
	# The engine draws one empty frame between scenes, and holds it while the next one loads.
	RenderingServer.set_default_clear_color(Color(fade.color, 1.0))
	# Holding the threaded result keeps it in the resource cache, so the change below doesn't block.
	var _loaded := ResourceLoader.load_threaded_get(next)
	get_tree().change_scene_to_file(next)

func _come_out() -> void:
	await _swing_door(true)
	await _waddle_to(OUTSIDE_Z)
	_swing_door(false)
	_anim.play("Happy")
	_anim.queue("Idle")
	_show_caption()
	await get_tree().create_timer(HOLD_TIME).timeout

func _go_in() -> void:
	_show_caption()
	await get_tree().create_timer(0.5).timeout
	# Turning its back on the camera, toward the door.
	var turn := create_tween()
	turn.tween_property(spot, "rotation:y", PI, 0.25)
	await turn.finished
	await _swing_door(true)
	await _waddle_to(INDOORS_Z)
	await _swing_door(false)
	var lights := create_tween()
	lights.tween_property(window_glass, "albedo_color", WINDOW_LIT, 0.25)
	await lights.finished
	await get_tree().create_timer(0.4).timeout

func _swing_door(open: bool) -> void:
	voice.play("pat")
	var t := create_tween()
	t.tween_property(door, "rotation_degrees:y", DOOR_OPEN_DEG if open else 0.0, DOOR_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished

# Kuiz's island waddle, `hops` hops along the path; it settles back into a hover on arrival.
func _waddle_to(z: float, hops := HOPS) -> void:
	var from := spot.position.z
	var t := create_tween()
	t.tween_method(_pose, 0.0, 1.0, 0.1)
	for i in hops:
		t.tween_callback(voice.play.bind("hop", 0.8))
		t.tween_method(func(p: float) -> void:
			_phase = p
			_pose(1.0), i * PI, (i + 1) * PI, HOP_TIME)
		t.parallel().tween_property(spot, "position:z", lerpf(from, z, float(i + 1) / hops), HOP_TIME)
	t.tween_method(_pose, 1.0, 0.0, 0.15)
	await t.finished

func _pose(blend: float) -> void:
	Follower.waddle(_kuiz, _phase, blend, KUIZ_SIZE)

func _show_caption() -> void:
	caption.pivot_offset = caption.size / 2.0
	var pop := create_tween().set_parallel()
	pop.tween_property(caption, "modulate:a", 1.0, 0.2)
	pop.tween_property(caption, "scale", Vector2.ONE, 0.35).from(Vector2.ONE * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
