extends Node2D
## Skeletal companion rig: Polygon2D body (idle, bone-deformed) + AnimatedSprite2D
## blink overlay + Polygon2D sad layer for low energy. Bones are posed with sine
## tweens, so the pixels bend instead of scaling stiffly.
## Public API (unchanged): play_reaction(action), celebrate(), set_mood(name).

const BONE_POS := {
	"Body": Vector2(269.8, 297.2),
	"EarL": Vector2(83.1, 315.7),
	"EarR": Vector2(456.9, 315.7),
	"Antenna": Vector2(272.2, 88.2),
}
const BONE_SIGMA := {"Body": 166.8, "EarL": 85.8, "EarR": 85.8, "Antenna": 95.3}
const BONE_PATH := {
	"Body": "Root/Body",
	"EarL": "Root/Body/EarL",
	"EarR": "Root/Body/EarR",
	"Antenna": "Root/Body/Antenna",
}

const IDLE_TEX: Texture2D = preload("res://assets/sprites/companion/idle_companion.svg")
const BLINK_TEX: Texture2D = preload("res://assets/sprites/companion/blink_companion.svg")
# ponytail: Face overlay is static (not bone-weighted) so blinks never fight the
# squash/breathe tweens; 1-2px drift vs the deformed body during a 0.2s blink.
const BLINK_MIN_WAIT := 2.4
const BLINK_MAX_WAIT := 4.8

@onready var art: Polygon2D = $Mesh/Art
@onready var sad_art: Polygon2D = $Mesh/SadArt
@onready var face: AnimatedSprite2D = $Mesh/Face
@onready var root_bone: Bone2D = $Mesh/Skeleton/Root
@onready var body_bone: Bone2D = $Mesh/Skeleton/Root/Body
@onready var ear_l: Bone2D = $Mesh/Skeleton/Root/Body/EarL
@onready var ear_r: Bone2D = $Mesh/Skeleton/Root/Body/EarR
@onready var antenna: Bone2D = $Mesh/Skeleton/Root/Body/Antenna

var _reacting := false
var _wilted := false
var _mood := ""
var _base_pos := Vector2.ZERO
var _bob_tween: Tween
var _breathe_tween: Tween
var _sway_tween: Tween
var _squash_tween: Tween
var _face_tween: Tween
var _blink_timer: Timer

func _ready() -> void:
	_snap_rests($Mesh/Skeleton)
	_paint_weights()
	_center()
	var parent := get_parent()
	if parent is Control:
		(parent as Control).resized.connect(_center)
	_start_idle()
	_setup_face()
	_start_blink_loop()

func _snap_rests(node: Node) -> void:
	for child in node.get_children():
		if child is Bone2D:
			(child as Bone2D).rest = (child as Bone2D).transform
		_snap_rests(child)

func _gate(bone: String, p: Vector2) -> float:
	if bone == "Antenna":
		if p.y < 130.0:
			return 1.0
		if p.y > 157.9:
			return 0.0
		return (157.9 - p.y) / 27.9
	if bone == "EarL":
		if p.y < 222.9 or p.y > 417.9:
			return 0.0
		if p.x < 107.5:
			return 1.0
		if p.x > 166.2:
			return 0.0
		return (166.2 - p.x) / 58.6
	if bone == "EarR":
		if p.y < 222.9 or p.y > 417.9:
			return 0.0
		if p.x > 432.5:
			return 1.0
		if p.x < 373.8:
			return 0.0
		return (p.x - 373.8) / 58.6
	return 1.0

func _weights_for(p: Vector2) -> Dictionary:
	var ws := {}
	for bone in BONE_POS:
		var g := _gate(bone, p)
		if g <= 0.0:
			continue
		var d := p.distance_to(BONE_POS[bone])
		var s: float = BONE_SIGMA[bone]
		var w := exp(-(d * d) / (2.0 * s * s)) * g
		if w >= 0.02:
			ws[bone] = w
	if ws.is_empty():
		return {"Body": 1.0}
	var total := 0.0
	for bone in ws:
		total += ws[bone]
	for bone in ws:
		ws[bone] /= total
	return ws

func _paint_weights() -> void:
	for mesh in [art, sad_art]:
		var cols := {"Body": [], "EarL": [], "EarR": [], "Antenna": []}
		for p in mesh.polygon:
			var w := _weights_for(p)
			for bone in cols:
				cols[bone].append(w.get(bone, 0.0))
		for bone in cols:
			mesh.add_bone(NodePath("../Skeleton/" + BONE_PATH[bone]),
				PackedFloat32Array(cols[bone]))

func _center() -> void:
	var parent := get_parent()
	if parent is Control:
		var c := (parent as Control).size / 2.0 + Vector2(0, -140)
		_base_pos = c if c.x > 0.0 else Vector2(360, 500)
	else:
		_base_pos = Vector2(360, 500)
	position = _base_pos
	_start_bob(1.0, 10.0)

# --- public API ---

func play_reaction(_action: String) -> void:
	_reacting = true
	_squash_bone(Vector2(1.15, 0.85), 0.1, 0.4)
	_wiggle_antenna()

func celebrate() -> void:
	_reacting = true
	_squash_bone(Vector2(1.3, 1.3), 0.15, 0.45)
	_hop()

func set_mood(mood: String) -> void:
	if _reacting or mood == _mood:
		return
	_mood = mood
	if mood == "sad" or mood == "sleepy":
		_wilt(mood)
		_fade_face(1.0 if mood == "sad" else 0.0)
	elif _wilted:
		_unwilt()

# --- internals ---

func _start_idle() -> void:
	_start_bob(1.0, 10.0)
	_stop(_breathe_tween)
	_breathe_tween = create_tween().set_loops()
	_breathe_tween.tween_property(body_bone, "scale", Vector2(1.012, 1.012), 1.6).set_trans(Tween.TRANS_SINE)
	_breathe_tween.tween_property(body_bone, "scale", Vector2.ONE, 1.6).set_trans(Tween.TRANS_SINE)
	_start_sway()

func _start_sway() -> void:
	_stop(_sway_tween)
	_sway_tween = create_tween().set_loops()
	_sway_tween.tween_property(antenna, "rotation", 0.06, 2.1).set_trans(Tween.TRANS_SINE)
	_sway_tween.tween_property(antenna, "rotation", -0.06, 2.1).set_trans(Tween.TRANS_SINE)

func _start_bob(period: float, amp: float) -> void:
	_stop(_bob_tween)
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(self, "position:y", _base_pos.y - amp, period).set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(self, "position:y", _base_pos.y, period).set_trans(Tween.TRANS_SINE)

func _stop(t: Tween) -> void:
	if t and t.is_valid():
		t.kill()

# --- blink (AnimatedSprite2D overlay; first/last frames match the idle body
# so showing/hiding the node is invisible, no fade pop) ---

func _setup_face() -> void:
	var sf := SpriteFrames.new()
	sf.add_animation(&"idle")
	sf.add_frame(&"idle", IDLE_TEX)
	sf.add_animation(&"blink")
	sf.set_animation_loop(&"blink", false)
	sf.set_animation_speed(&"blink", 12)
	sf.add_frame(&"blink", IDLE_TEX, 0.5)
	sf.add_frame(&"blink", BLINK_TEX, 1.2)
	sf.add_frame(&"blink", IDLE_TEX, 0.8)
	face.sprite_frames = sf
	face.animation = &"idle"
	face.visible = false
	face.animation_finished.connect(_on_blink_finished)

func _start_blink_loop() -> void:
	if _blink_timer == null:
		_blink_timer = Timer.new()
		_blink_timer.one_shot = true
		_blink_timer.timeout.connect(_on_blink_timeout)
		add_child(_blink_timer)
	_blink_timer.start(randf_range(BLINK_MIN_WAIT, BLINK_MAX_WAIT))

func _on_blink_timeout() -> void:
	if _reacting or not is_inside_tree():
		_blink_timer.start(0.5)
		return
	face.visible = true
	face.play(&"blink")

func _on_blink_finished() -> void:
	face.visible = false
	face.animation = &"idle"
	if is_inside_tree() and is_instance_valid(_blink_timer):
		_blink_timer.start(randf_range(BLINK_MIN_WAIT, BLINK_MAX_WAIT))

func _fade_face(target: float) -> void:
	if is_equal_approx(sad_art.modulate.a, target):
		return
	_stop(_face_tween)
	_face_tween = create_tween()
	_face_tween.tween_property(sad_art, "modulate:a", target, 0.5).set_trans(Tween.TRANS_SINE)

func _squash_bone(amount: Vector2, down_t: float, up_t: float) -> void:
	_stop(_squash_tween)
	root_bone.scale = Vector2.ONE
	_squash_tween = create_tween()
	_squash_tween.tween_property(root_bone, "scale", amount, down_t)
	_squash_tween.tween_property(root_bone, "scale", Vector2.ONE, up_t).set_trans(Tween.TRANS_SINE)
	if not _squash_tween.finished.is_connected(_on_squash_done):
		_squash_tween.finished.connect(_on_squash_done)

func _on_squash_done() -> void:
	_reacting = false

func _wiggle_antenna() -> void:
	_stop(_sway_tween)
	var t := create_tween()
	t.tween_property(antenna, "rotation", 0.18, 0.09)
	t.tween_property(antenna, "rotation", -0.12, 0.12)
	t.tween_property(antenna, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
	t.finished.connect(_start_sway)

func _hop() -> void:
	_stop(_bob_tween)
	var t := create_tween()
	t.tween_property(self, "position:y", _base_pos.y - 44.0, 0.18).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "position:y", _base_pos.y, 0.3).set_trans(Tween.TRANS_SINE)
	t.finished.connect(_start_idle)

func _wilt(mood: String) -> void:
	_wilted = true
	_stop(_sway_tween)
	var droop := 0.3 if mood == "sad" else 0.22
	var t := create_tween().set_parallel(true)
	t.tween_property(ear_l, "rotation", droop, 0.8).set_trans(Tween.TRANS_SINE)
	t.tween_property(ear_r, "rotation", -droop, 0.8).set_trans(Tween.TRANS_SINE)
	t.tween_property(antenna, "rotation", 0.15, 0.8).set_trans(Tween.TRANS_SINE)
	_start_bob(2.2, 5.0)

func _unwilt() -> void:
	_wilted = false
	_fade_face(0.0)
	var t := create_tween().set_parallel(true)
	t.tween_property(ear_l, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(ear_r, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(antenna, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	t.chain().tween_callback(_start_sway)
	_start_bob(1.0, 10.0)
