extends Node3D
## Kuiz peeks in on white after the loading screen, greets, then idles here. This is where the
## tutorial will start; nothing leads out of it yet.
## Rendering mirrors the KUIZMON Pet Bot artifact: docs/ui-and-assets.md §2 peek.tscn.

const PEEK := "Peek_Surprise"
const GREET := "Greetings"
const IDLE := "Idle"
const BLEND_TIME := 0.18
const INK := Color("29383A")
const FLAT_SELF_LIT := 0.85
# 8.6 * tan(12°): visible half-height of the artifact framing the peek clip was authored for.
const AUTHORED_HALF_HEIGHT := 1.828
const HEAD_REST_Y := 0.9

@onready var anim: AnimationPlayer = $Kuiz/AnimationPlayer
@onready var skeleton: Skeleton3D = $Kuiz/Skeleton3D
@onready var camera: Camera3D = $Camera3D
@onready var kuiz: Node3D = $Kuiz
@onready var shadow_mat: StandardMaterial3D = $Shadow.mesh.material

var _head := -1

func _ready() -> void:
	for mesh_instance: MeshInstance3D in kuiz.find_children("*", "MeshInstance3D", true, false):
		var outline: float = mesh_instance.get_meta("extras", {}).get("outline", 0.0)
		if outline > 0.0:
			mesh_instance.material_overlay = _ink(outline)
		for i in mesh_instance.get_surface_override_material_count():
			var mat := mesh_instance.get_active_material(i) as BaseMaterial3D
			if mat:
				_apply_extras(mat)
	_head = skeleton.find_bone("Head")
	anim.get_animation(IDLE).loop_mode = Animation.LOOP_LINEAR
	anim.playback_default_blend_time = BLEND_TIME
	anim.play(PEEK)
	anim.queue(GREET)
	anim.queue(IDLE)

# The peek clip is authored for a wider framing; re-anchor it to this screen's bottom edge so Kuiz
# rises from it, and fade the contact shadow while the head is low.
func _process(_delta: float) -> void:
	var head_y := skeleton.get_bone_pose_position(_head).y
	var peek := clampf(HEAD_REST_Y - head_y, 0.0, 1.0) if anim.current_animation == PEEK else 0.0
	var view := get_viewport().get_visible_rect().size
	var half_height := (camera.position.z - 1.0) * tan(deg_to_rad(camera.fov) / 2.0) * view.y / view.x
	kuiz.position.y = (AUTHORED_HALF_HEIGHT - half_height) * peek
	var spread := 1.0 / (1.0 + maxf(0.0, head_y - HEAD_REST_Y) * 1.6)
	$Shadow.scale = Vector3(spread, 1.0, spread)
	shadow_mat.albedo_color.a = (0.45 + 0.55 * spread) * (1.0 - minf(1.0, peek * 1.5))

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
