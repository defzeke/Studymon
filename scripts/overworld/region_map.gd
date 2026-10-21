extends Node3D
## Phase 6: 3D Overworld & Gym Structure (GDD §6.1). Contract: docs/systems/overworld.md.
## The island in assets/models/map.glb, seen from an angled top-down camera that follows the
## explorer. One gym per question category, each in one of the map's gym buildings, with hallway
## trainers on the road leading to it. Trainer/boss triggers hand off to Battle (Phase 7).
## Phase 8: trainer markers carry mastery colours; the Champion holds the big gym —
## unlocks when all gym badges are earned, moveset = Mastered questions,
## clearing the gauntlet completes the region.
## Phase 9: particle burst on gym clear.

# Map buildings, in route order: gyms[0], gyms[1], then the Champion. Doors face +z.
const GYM_BUILDINGS: Array[String] = ["Gym2", "Gym3"]
# The third gym has no building: it stands at the GymSpot3 marker on the west end of the south road.
const MAX_GYMS := 3
const CHAMPION_BUILDING := "Gym"
const DOOR_FRONT := Vector3(0.0, 0.0, 0.8)
const TRIGGER_RADIUS := 0.7
const TRAINER_RADIUS := 0.45
const LABEL_HEIGHT := 1.4
const PLAYER_LAYER := 4
const OBSTACLE_LAYER := 2
# Walkable surfaces (ground layer: height only) and what blocks the explorer (obstacle layer).
# Everything else (water, roofs, flags, doors, glows) gets no collision.
const GROUND_MESHES: Array[String] = ["Ground_Roads", "Grass_Blocks", "Sand_", "House_Foundation", "Door_Step", "Plinth", "Court_Surface", "_Path", "Interior_Floor"]
const OBSTACLE_MESHES: Array[String] = ["Wall_", "Window", "Door", "_Wall", "_Glass", "_Trim", "_Sign", "_Band", "Interior_Back", "Tree_", "Lamp_Pole", "Rocks"]
const NOT_OBSTACLES: Array[String] = ["Door_Step", "Dome_Glass"]
const LABEL_FONT: Font = preload("res://assets/fonts/JosefinSans-Bold.ttf")
const INK := Color("29383A")

@onready var map: Node3D = $Map
@onready var map_anim: AnimationPlayer = $Map/AnimationPlayer
@onready var player: CharacterBody3D = $Player
@onready var trainers_root: Node3D = $Trainers
@onready var gyms_root: Node3D = $Gyms
@onready var progress_label: Label = $HUD/TopBar/ProgressLabel
@onready var badges_label: Label = $HUD/TopBar/BadgesLabel
@onready var back_btn: Button = $HUD/TopBar/BackButton
@onready var encounter_panel: PanelContainer = $HUD/EncounterPanel
@onready var encounter_title: Label = $HUD/EncounterPanel/Margin/List/EncounterTitle
@onready var encounter_question: Label = $HUD/EncounterPanel/Margin/List/EncounterQuestion
@onready var encounter_close_btn: Button = $HUD/EncounterPanel/Margin/List/EncounterCloseButton
@onready var encounter_clear_btn: Button = $HUD/EncounterPanel/Margin/List/EncounterClearButton

var _topic_id: String = ""
var _pending_encounter: Dictionary = {}
var _gym_positions: Dictionary = {}
var _prev_cleared_gyms: Dictionary = {}

func _ready() -> void:
	_topic_id = SessionManager.current_topic_id
	if _topic_id == "":
		_topic_id = SessionManager.editing_topic_id
	# Fallback: if overworld opened with no topic (e.g. direct scene run),
	# seed two mock questions so the route still renders.
	if SessionManager.pending_questions.is_empty():
		SessionManager.editing_topic_id = "topic_preview"
		SessionManager.current_topic_id = "topic_preview"
		_topic_id = "topic_preview"
		SessionManager.pending_questions = [
			{"id": "q1", "text": "Preview: what is training data?", "type": "identification", "answer": "Examples", "confidence": 0.9},
			{"id": "q2", "text": "Preview: explain feedback in your own words.", "type": "essay", "answer": "", "confidence": 0.6},
		]
	GameState.set_active_region(_topic_id)
	back_btn.pressed.connect(_on_back)
	encounter_close_btn.pressed.connect(_on_encounter_close)
	encounter_clear_btn.pressed.connect(_on_encounter_cleared)
	_show_encounter(false)
	SessionManager.overworld_progress_changed.connect(_refresh_progress)
	_add_collisions()
	player.global_position = $Spawn.global_position
	_build_route()
	_refresh_progress()

# map.glb ships without collision; build trimesh bodies from its meshes by name.
func _add_collisions() -> void:
	for mesh: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var n := String(mesh.name)
		var layer := 0
		if GROUND_MESHES.any(func(k: String) -> bool: return n.contains(k)):
			layer = 1
		elif OBSTACLE_MESHES.any(func(k: String) -> bool: return n.contains(k)) and not NOT_OBSTACLES.any(func(k: String) -> bool: return n.contains(k)) and not mesh.get_parent().name.contains("_Door_"):
			layer = OBSTACLE_LAYER
		if layer == 0:
			continue
		mesh.create_trimesh_collision()
		var body := mesh.get_child(mesh.get_child_count() - 1) as StaticBody3D
		body.collision_layer = layer
		body.collision_mask = 0

func _build_route() -> void:
	for c in trainers_root.get_children():
		c.queue_free()
	for c in gyms_root.get_children():
		c.queue_free()
	_gym_positions.clear()
	var gyms := SessionManager.get_gym_structure()
	if gyms.is_empty():
		return
	# One gym per question type: two in map buildings, the third at its spot.
	for gi in mini(gyms.size(), MAX_GYMS):
		_add_gym_node(gyms[gi], GYM_BUILDINGS[gi] if gi < GYM_BUILDINGS.size() else "", gi)
		# Hallway trainers for this gym, spread along its road (TrainersN/From → To).
		var from: Vector3 = get_node("Trainers%d/From" % (gi + 1)).global_position
		var to: Vector3 = get_node("Trainers%d/To" % (gi + 1)).global_position
		var indices: Array = gyms[gi]["question_indices"]
		for ti in indices.size():
			_add_trainer_node(int(indices[ti]), from.lerp(to, float(ti + 1) / float(indices.size() + 1)))
	_add_champion_node(CHAMPION_BUILDING)
	# Snapshot cleared state on build so we don't burst for saves that already cleared.
	_prev_cleared_gyms.clear()
	for g in gyms:
		var t: String = str(g["type"])
		if SessionManager.is_gym_cleared(_topic_id, t):
			_prev_cleared_gyms[t] = true

func _add_trainer_node(q_idx: int, pos: Vector3) -> void:
	var questions := SessionManager.get_pending_questions()
	if q_idx < 0 or q_idx >= questions.size():
		return
	var badge: Dictionary = SessionManager.mastery_badge(SessionManager.get_mastery_state(_topic_id, q_idx))
	var area := _trigger(pos, TRAINER_RADIUS, "T%d" % (q_idx + 1))
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = TRAINER_RADIUS
	disc.bottom_radius = TRAINER_RADIUS
	disc.height = 0.04
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = badge["color"]
	disc.material = mat
	pad.mesh = disc
	pad.position.y = 0.04
	area.add_child(pad)
	area.body_entered.connect(_on_trainer_touched.bind(q_idx))
	trainers_root.add_child(area)
	# Dim if already cleared
	if SessionManager.is_trainer_cleared(_topic_id, q_idx):
		mat.albedo_color = mat.albedo_color.darkened(0.5)
		(area.get_node("Label") as Label3D).modulate.a = 0.5

func _add_gym_node(gym: Dictionary, building: String, gym_idx: int) -> void:
	var gym_type: String = str(gym["type"])
	var badge := "BADGE" if SessionManager.is_gym_cleared(_topic_id, gym_type) else "GYM %d" % (gym_idx + 1)
	var pos: Vector3 = _door(building) if building != "" else (get_node("GymSpot%d" % (gym_idx + 1)) as Node3D).global_position
	var area := _trigger(pos, TRIGGER_RADIUS, "%s\n%s" % [badge, gym_type.capitalize()])
	_gym_positions[gym_type] = area.position
	area.body_entered.connect(_on_gym_touched.bind(gym_type))
	if building != "":
		_door_animates(area, building)
	gyms_root.add_child(area)

func _add_champion_node(building: String) -> void:
	var state := "LOCKED"
	if SessionManager.is_champion_defeated(_topic_id):
		state = "DOWN"
	elif SessionManager.is_champion_available(_topic_id):
		state = "FIGHT!"
	var area := _trigger(_door(building), TRIGGER_RADIUS, "CHAMPION\n%s" % state)
	area.body_entered.connect(_on_champion_touched)
	_door_animates(area, building)
	gyms_root.add_child(area)

# Ground point in front of a gym building's double door.
func _door(building: String) -> Vector3:
	var mid: Vector3 = (map.get_node(building + "_Door_Left").global_position + map.get_node(building + "_Door_Right").global_position) / 2.0
	return Vector3(mid.x, 0.0, mid.z) + DOOR_FRONT

func _door_animates(area: Area3D, building: String) -> void:
	area.body_entered.connect(func(_b: Node3D) -> void: map_anim.play(building + "_Door_Open"))
	area.body_exited.connect(func(_b: Node3D) -> void: map_anim.play(building + "_Door_Close"))

# A trigger the explorer walks into, with a billboard label above it.
func _trigger(pos: Vector3, radius: float, text: String) -> Area3D:
	var area := Area3D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = PLAYER_LAYER
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 2.0
	shape.shape = cyl
	shape.position.y = 1.0
	area.add_child(shape)
	var label := Label3D.new()
	label.name = "Label"
	label.text = text
	label.font = LABEL_FONT
	label.font_size = 40
	label.pixel_size = 0.01
	label.outline_size = 12
	label.outline_modulate = INK
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = LABEL_HEIGHT
	area.add_child(label)
	return area

# --- Phase 9: gym-clear burst (CPUParticles3D, one-shot, auto-freed) ---
func _spawn_gym_burst(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos + Vector3.UP * 0.5
	p.amount = 26
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.1
	p.direction = Vector3.UP
	p.spread = 60.0
	p.gravity = Vector3(0, -6, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	var bit := SphereMesh.new()
	bit.radius = 0.06
	bit.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.95, 0.55)
	bit.material = mat
	p.mesh = bit
	p.emitting = true
	add_child(p)
	p.finished.connect(p.queue_free)

func _on_trainer_touched(_body: Node3D, q_idx: int) -> void:
	var questions := SessionManager.get_pending_questions()
	if q_idx < 0 or q_idx >= questions.size():
		return
	var q: Dictionary = questions[q_idx]
	_pending_encounter = {"kind": "trainer", "q_index": q_idx, "gym": str(q.get("type", "essay"))}
	var cleared := SessionManager.is_trainer_cleared(_topic_id, q_idx)
	var badge: Dictionary = SessionManager.mastery_badge(SessionManager.get_mastery_state(_topic_id, q_idx))
	encounter_title.text = "Trainer %d %s" % [q_idx + 1, "(cleared)" if cleared else "wants to battle!"]
	encounter_question.text = "[%s] %s %s" % [str(badge["name"]), str(q.get("type", "essay")).capitalize(), str(q.get("text", ""))]
	encounter_clear_btn.text = "Fight Trainer!" if not cleared else "Already Cleared"
	encounter_clear_btn.disabled = cleared
	_show_encounter(true)

func _on_gym_touched(_body: Node3D, gym_type: String) -> void:
	var gyms := SessionManager.get_gym_structure()
	var indices: Array = []
	for g in gyms:
		if str(g["type"]) == gym_type:
			indices = g["question_indices"]
			break
	_pending_encounter = {"kind": "gym", "gym": gym_type, "question_indices": indices}
	var cleared := SessionManager.is_gym_cleared(_topic_id, gym_type)
	var count := indices.size()
	encounter_title.text = "Gym: %s %s" % [gym_type.capitalize(), "(badge earned)" if cleared else "— Boss ahead!"]
	encounter_question.text = "%d question(s) in this gym. Boss is the final question." % count
	encounter_clear_btn.text = "Fight Boss!" if not cleared else "Badge Earned"
	encounter_clear_btn.disabled = cleared
	_show_encounter(true)

func _on_champion_touched(_body: Node3D) -> void:
	# Pre-Champion summary screen: moveset preview with mastery badges.
	if SessionManager.is_champion_defeated(_topic_id):
		_pending_encounter = {}
		encounter_title.text = "Region Complete!"
		encounter_question.text = "You cleared every gym and dethroned the Champion. This region is yours."
		encounter_clear_btn.text = "Crowned"
		encounter_clear_btn.disabled = true
		_show_encounter(true)
		return
	if not SessionManager.is_champion_available(_topic_id):
		_pending_encounter = {}
		encounter_title.text = "Champion (locked)"
		encounter_question.text = "Earn every gym badge first — the Champion only faces proven trainers."
		encounter_clear_btn.text = "Locked"
		encounter_clear_btn.disabled = true
		_show_encounter(true)
		return
	var moveset := SessionManager.champion_moveset(_topic_id)
	if moveset.is_empty():
		_pending_encounter = {}
		encounter_title.text = "CHAMPION — not ready"
		encounter_question.text = "No Mastered questions yet. Win rematches to master questions, then face the Champion."
		encounter_clear_btn.text = "Locked"
		encounter_clear_btn.disabled = true
		_show_encounter(true)
		return
	var questions := SessionManager.get_pending_questions()
	var lines: Array[String] = []
	for n in mini(moveset.size(), 6):
		var qi := int(moveset[n])
		if qi >= 0 and qi < questions.size():
			var badge: Dictionary = SessionManager.mastery_badge(SessionManager.get_mastery_state(_topic_id, qi))
			lines.append("%s Q%d: %s" % [str(badge["emoji"]), qi + 1, str((questions[qi] as Dictionary).get("text", "")).left(50)])
	if moveset.size() > 6:
		lines.append("...and %d more." % (moveset.size() - 6))
	_pending_encounter = {"kind": "champion"}
	encounter_title.text = "CHAMPION — %d challenger(s)" % moveset.size()
	encounter_question.text = "The Champion fields your Mastered questions:\n" + "\n".join(lines) + "\nWin them all back-to-back to complete the region!"
	encounter_clear_btn.text = "Challenge Champion!"
	encounter_clear_btn.disabled = false
	_show_encounter(true)

# The explorer stands still while a panel is open.
func _show_encounter(shown: bool) -> void:
	encounter_panel.visible = shown
	player.locked = shown

func _on_encounter_close() -> void:
	_show_encounter(false)
	_pending_encounter = {}

func _on_encounter_cleared() -> void:
	if _pending_encounter.is_empty():
		return
	if _pending_encounter.get("kind") == "trainer":
		SessionManager.begin_battle(_topic_id, int(_pending_encounter.get("q_index", 0)), false)
	elif _pending_encounter.get("kind") == "gym":
		var indices: Array = _pending_encounter.get("question_indices", [])
		if indices.is_empty():
			return
		# Boss = final question of the gym.
		SessionManager.begin_battle(_topic_id, int(indices[indices.size() - 1]), true)
	elif _pending_encounter.get("kind") == "champion":
		if not SessionManager.begin_champion_battle(_topic_id):
			return
	else:
		return
	_show_encounter(false)
	_pending_encounter = {}
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

func _refresh_progress() -> void:
	var p := SessionManager.get_progress(_topic_id)
	var crown := "CROWNED" if SessionManager.is_champion_defeated(_topic_id) else ("CHAMP-READY" if SessionManager.is_champion_available(_topic_id) else "CHAMP-LOCKED")
	progress_label.text = "Trainers %d/%d  %s" % [int(p["cleared"]), int(p["total"]), crown]
	var gyms := SessionManager.get_gym_structure()
	var badges := ""
	for g in gyms:
		var t: String = str(g["type"])
		var now_cleared := SessionManager.is_gym_cleared(_topic_id, t)
		if now_cleared and not _prev_cleared_gyms.has(t):
			# Fresh clear → burst at gym position.
			_spawn_gym_burst(_gym_positions.get(t, player.global_position))
			_prev_cleared_gyms[t] = true
		elif now_cleared:
			_prev_cleared_gyms[t] = true
		badges += "[X]" if now_cleared else "[ ]"
	badges_label.text = "Gyms %d/%d %s" % [int(p["gyms_cleared"]), int(p["gyms_total"]), badges]

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/session_list.tscn")
