class_name ArenaStage
extends SubViewportContainer
## The 3D arena behind the battle HUD. Everything placeable lives in battle.tscn: the camera, the
## PetSpot / FoeSpot markers (position = where, Y rotation = which way it faces) and the pads under
## them. Models are fitted to the heights below, so a re-exported glb of any size still lands on its pad.

@export var pet_scene: PackedScene
@export var foe_scenes: Array[PackedScene] = []
@export var pet_height := 2.6
@export var foe_height := 3.0
@export var big_foe_scale := 1.3
## Kuiz's idle pose sits above the rest-pose bounds measured here, so it is lowered by this share of its
## height to stand on the pad.
@export var pet_sink_ratio := 0.36
@export var foot_lift := 0.03
@export var idle_clip: StringName = &"Idle"
@export var attack_clip: StringName = &"Attack"
@export var defeat_clip: StringName = &"Defeat"
@export var pet_hurt_clip: StringName = &"Sad"
@export var pet_hit_clip: StringName = &"Happy"
@export var pet_win_clip: StringName = &"Celebrate"

@export_group("Look")
@export var ink_color := Color("29383A")
## Outline width for models that carry no outline hint of their own (the robots); 0 turns it off.
@export var foe_outline := 0.012
@export var flat_self_lit := 0.85
@export_group("Intro")
## Where each bot starts, relative to its pad, before it moves in.
@export var intro_pet_offset := Vector3(-9, 1.5, 4)
@export var intro_foe_offset := Vector3(9, 3.5, -3)
@export var intro_pet_time := 0.8
@export var intro_foe_time := 1.0
@export var intro_foe_delay := 0.25
@export var intro_pad_time := 0.4
## The camera starts this far back and zoomed out, then settles.
@export var intro_camera_offset := Vector3(0, 1.5, 4.5)
@export var intro_fov_extra := 14.0
@export var intro_camera_time := 1.4
@export_group("Idle hover")
@export var pet_hover_height := 0.05
@export var foe_hover_height := 0.03
@export var hover_time := 1.3

@export_group("Strikes")
## How far toward its target an attacker runs (0 = stays home, 1 = on top of it).
## Attacks happen in place: the attacker plays its attack clip, and after this long the blow lands.
@export var strike_impact_time := 0.55
## After the blow lands, how long before the exchange counts as finished.
@export var strike_recover_time := 0.6
@export var pet_attack_clip: StringName = &"Angry"
## The foe has no hurt clip, so it flinches with a quick tilt unless a clip with this name exists.
@export var foe_hurt_clip: StringName = &""

## Foes with sounds, by the name of the glb's root node: the voice fires them on its clips.
const FOE_VOICES := {"BrokenBot": preload("res://scripts/battle/broken_bot_voice.gd")}

## The foe has touched down: time for a flash, a shake, a dust burst.
signal foe_landed
signal pet_landed
## An attacker's blow has connected; `on_pet` is true when Kuiz was the one hit.
signal strike_hit(on_pet: bool)
## The attacker is back on its pad.
signal strike_finished

@onready var pet_spot: Node3D = %PetSpot
@onready var foe_spot: Node3D = %FoeSpot
@onready var camera: Camera3D = %Camera3D
@onready var pet_dust: CPUParticles3D = %PetDust
@onready var foe_dust: CPUParticles3D = %FoeDust

var _pet: AnimationPlayer
var _foe: AnimationPlayer
var _pet_model: Node3D
var _foe_model: Node3D
## True from play_intro() until the bots have settled.
var intro_running := false

## `big_foe` (gym boss, Champion) makes the opponent larger.
func setup(big_foe: bool) -> void:
	_pet_model = _add_model(pet_scene, pet_spot, pet_height, Vector3(0, -pet_sink_ratio * pet_height, 0))
	_dress(_pet_model, 0.0)
	_pet = _idle(_pet_model)
	if not foe_scenes.is_empty():
		_foe_model = _add_model(foe_scenes.pick_random(), foe_spot, foe_height * (big_foe_scale if big_foe else 1.0), Vector3.ZERO)
		_dress(_foe_model, foe_outline)
		_foe = _idle(_foe_model)
		for root_name: String in FOE_VOICES:
			if _foe_model.find_child(root_name, true, false) != null:
				var voice: Node = FOE_VOICES[root_name].new()
				voice.anim = _foe
				add_child(voice)

## Gentle floating on both bots. play_intro() starts it when it finishes; call this when skipping the intro.
func start_hover() -> void:
	_hover(_pet_model, pet_hover_height)
	_hover(_foe_model, foe_hover_height)

## Both bots fly onto their pads while the camera pulls in; finishes when everything has settled.
## Call it right after setup(), before the first frame, so nothing shows at rest first.
func play_intro() -> void:
	if _pet_model == null or _foe_model == null:
		return
	var pet_rest := _pet_model.position
	var foe_rest := _foe_model.position
	var cam_rest := camera.position
	var fov_rest := camera.fov
	var pads: Array[Node3D] = []
	for spot: Node3D in [pet_spot, foe_spot]:
		for p in spot.get_children():
			if p is MeshInstance3D:
				pads.append(p)
	intro_running = true
	_pet_model.position = pet_rest + intro_pet_offset
	_foe_model.position = foe_rest + intro_foe_offset
	_pet_model.rotation.y = TAU
	camera.position = cam_rest + intro_camera_offset
	camera.fov = fov_rest + intro_fov_extra
	for p in pads:
		p.scale = Vector3.ZERO
	var t := create_tween().set_parallel()
	t.tween_property(camera, "position", cam_rest, intro_camera_time).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(camera, "fov", fov_rest, intro_camera_time).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	for i in pads.size():
		t.tween_property(pads[i], "scale", Vector3.ONE, intro_pad_time).set_delay(i * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Kuiz swoops in from the left with a full spin.
	t.tween_property(_pet_model, "position", pet_rest, intro_pet_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_pet_model, "rotation:y", 0.0, intro_pet_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# The foe slides in from the right while dropping onto its pad with a bounce.
	t.tween_property(_foe_model, "position:x", foe_rest.x, intro_foe_time).set_delay(intro_foe_delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_foe_model, "position:z", foe_rest.z, intro_foe_time).set_delay(intro_foe_delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_foe_model, "position:y", foe_rest.y, intro_foe_time).set_delay(intro_foe_delay).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(intro_pet_time * 0.75).timeout.connect(func() -> void:
		pet_dust.restart()
		pet_landed.emit()
		_play(_pet, pet_hit_clip, true))
	get_tree().create_timer(intro_foe_delay + intro_foe_time * 0.4).timeout.connect(func() -> void:
		foe_dust.restart()
		foe_landed.emit()
		_play(_foe, attack_clip, true))
	await t.finished
	intro_running = false
	start_hover()

func enemy_attack() -> void:
	_play(_foe, attack_clip, true)

## The foe charges Kuiz, hits it, and trots home. Emits strike_hit on impact, strike_finished at the end.
func enemy_strike() -> void:
	await _strike(_foe_model, _pet_model, _foe, attack_clip, true)

## Kuiz charges the foe, hits it, and floats home.
func pet_strike() -> void:
	await _strike(_pet_model, _foe_model, _pet, pet_attack_clip, false)

## Where a hit lands on screen (in the Battle scene's coordinates), for floating numbers.
func impact_point(on_pet: bool) -> Vector2:
	var model := _pet_model if on_pet else _foe_model
	if model == null:
		return global_position + size / 2.0
	var top := model.global_position + Vector3.UP * (pet_height if on_pet else foe_height) * 0.55
	return global_position + camera.unproject_position(top)

func _strike(attacker: Node3D, target: Node3D, anim: AnimationPlayer, clip: StringName, on_pet: bool) -> void:
	if attacker == null or target == null:
		strike_hit.emit(on_pet)
		strike_finished.emit()
		return
	_play(anim, clip, true)
	await get_tree().create_timer(strike_impact_time).timeout
	(pet_dust if on_pet else foe_dust).restart()
	strike_hit.emit(on_pet)
	# The one hit reacts where it stands: Kuiz plays its hurt clip, the foe flinches.
	if on_pet:
		_play(_pet, pet_hurt_clip, true)
	elif _foe != null and foe_hurt_clip != &"" and _foe.has_animation(foe_hurt_clip):
		_play(_foe, foe_hurt_clip, true)
	else:
		var wob := create_tween()
		wob.tween_property(target, "rotation:z", 0.2, 0.06)
		wob.tween_property(target, "rotation:z", -0.15, 0.08)
		wob.tween_property(target, "rotation:z", 0.0, 0.1)
	await get_tree().create_timer(strike_recover_time).timeout
	strike_finished.emit()
func enemy_defeat() -> void:
	_play(_foe, defeat_clip, false)

func pet_hurt() -> void:
	_play(_pet, pet_hurt_clip, true)

func pet_hit() -> void:
	_play(_pet, pet_hit_clip, true)

func pet_win() -> void:
	_play(_pet, pet_win_clip, true)

# Stands the model on `spot` (feet centred) and `height` tall.
func _add_model(scene: PackedScene, spot: Node3D, height: float, offset: Vector3) -> Node3D:
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	spot.add_child(model)
	var box := _bounds(model, spot)
	var s := height / maxf(box.size.y, 0.001)
	model.scale = Vector3.ONE * s
	model.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s + offset
	model.position.y += foot_lift
	return model

# Gives a model the look it has on the home screen. Kuiz's glb carries its shading as extras: an ink
# outline width per mesh, vertex colours (the teal and gold) and self-lit parts. Without applying them it
# renders plain white. `default_outline` outlines meshes that carry no hint (the robots).
func _dress(model: Node3D, default_outline: float) -> void:
	if model == null:
		return
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = mi.get_meta("extras", {})
		var outline := float(extras.get("outline", default_outline))
		if outline > 0.0:
			mi.material_overlay = _ink(outline)
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var m_extras: Dictionary = mat.get_meta("extras", {})
			if m_extras.is_empty():
				continue
			mat.vertex_color_use_as_albedo = true
			if float(m_extras.get("selfLit", 0.0)) >= flat_self_lit:
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if str(m_extras.get("blend", "")) == "additive":
				mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

# Inverted hull: the mesh grown along its normals with front faces culled, so only the rim shows.
func _ink(width: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.grow = true
	mat.grow_amount = width
	mat.albedo_color = ink_color
	return mat

# The model's AnimationPlayer, started on its looping idle clip.
func _idle(model: Node3D) -> AnimationPlayer:
	if model == null:
		return null
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null and anim.has_animation(idle_clip):
		anim.get_animation(idle_clip).loop_mode = Animation.LOOP_LINEAR
		anim.play(idle_clip)
	return anim

# Endless gentle float: up and down around where the model rests.
func _hover(model: Node3D, height: float) -> void:
	if model == null or height <= 0.0:
		return
	var rest := model.position.y
	var t := create_tween().set_loops()
	t.tween_property(model, "position:y", rest + height, hover_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(model, "position:y", rest, hover_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Union of every mesh's bounds in the spot's own space (model still unscaled at its origin).
func _bounds(model: Node3D, spot: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var to_spot := spot.global_transform.affine_inverse()
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b := to_spot * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return AABB(Vector3.ZERO, Vector3.ONE) if first else box

func _play(anim: AnimationPlayer, clip: StringName, back_to_idle: bool) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	anim.play(clip, 0.1)
	if back_to_idle and anim.has_animation(idle_clip):
		await anim.animation_finished
		anim.play(idle_clip, 0.1)
