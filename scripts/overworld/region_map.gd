extends Node2D
## Phase 6: 2D Overworld & Gym Structure (GDD §6.1)
## Route generator: one gym per question category, hallway trainers before each boss.
## Trainer/boss triggers hand off to Battle (Phase 7) with the question bound.
## Phase 8: trainer labels carry mastery badges; a Champion node caps the route —
## unlocks when all gym badges are earned, moveset = Mastered questions,
## clearing the gauntlet completes the region.
## Phase 9: CPUParticles2D burst on gym clear.

const PLAYER_SCENE_OFFSET := Vector2(360, 1100)

@onready var player: CharacterBody2D = $Player
@onready var trainers_root: Node2D = $Trainers
@onready var gyms_root: Node2D = $Gyms
@onready var route_line: Line2D = $Route
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
	GameState.current_topic_id = _topic_id
	back_btn.pressed.connect(_on_back)
	encounter_close_btn.pressed.connect(_on_encounter_close)
	encounter_clear_btn.pressed.connect(_on_encounter_cleared)
	encounter_panel.visible = false
	SessionManager.overworld_progress_changed.connect(_refresh_progress)
	_build_route()
	_refresh_progress()

func _build_route() -> void:
	for c in trainers_root.get_children():
		c.queue_free()
	for c in gyms_root.get_children():
		c.queue_free()
	_gym_positions.clear()
	var gyms := SessionManager.get_gym_structure()
	if gyms.is_empty():
		return
	# Vertical route: gyms spaced 320px apart going up from player start
	var points := PackedVector2Array()
	points.append(PLAYER_SCENE_OFFSET)
	var y := PLAYER_SCENE_OFFSET.y
	for gi in gyms.size():
		y -= 320.0
		var gym_pos := Vector2(360, y)
		points.append(gym_pos)
		_add_gym_node(gyms[gi], gym_pos, gi)
		# Hallway trainers for this gym: spread horizontally around the segment
		var indices: Array = gyms[gi]["question_indices"]
		for ti in indices.size():
			var frac := float(ti + 1) / float(indices.size() + 1)
			# Interpolate between previous point and gym pos, offset sideways
			var prev := points[points.size() - 2] if points.size() >= 2 else PLAYER_SCENE_OFFSET
			var base: Vector2 = prev.lerp(gym_pos, frac)
			var side := -120.0 if ti % 2 == 0 else 120.0
			_add_trainer_node(int(indices[ti]), Vector2(360 + side, base.y))
	# Champion caps the route above the final gym.
	y -= 320.0
	var champ_pos := Vector2(360, y)
	points.append(champ_pos)
	_add_champion_node(champ_pos)
	route_line.points = points
	# Snapshot cleared state on build so we don't burst for saves that already cleared.
	_prev_cleared_gyms.clear()
	for g in gyms:
		var t: String = str(g["type"])
		if SessionManager.is_gym_cleared(_topic_id, t):
			_prev_cleared_gyms[t] = true

func _add_trainer_node(q_idx: int, pos: Vector2) -> void:
	var questions := SessionManager.get_pending_questions()
	if q_idx < 0 or q_idx >= questions.size():
		return
	var q: Dictionary = questions[q_idx]
	var area := Area2D.new()
	area.position = pos
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 36.0
	shape.shape = circle
	area.add_child(shape)
	var badge: Dictionary = SessionManager.mastery_badge(SessionManager.get_mastery_state(_topic_id, q_idx))
	var label := Label.new()
	label.text = "T%d %s" % [q_idx + 1, str(badge["emoji"])]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-24, -28)
	area.add_child(label)
	area.body_entered.connect(_on_trainer_touched.bind(q_idx))
	trainers_root.add_child(area)
	# Dim if already cleared
	if SessionManager.is_trainer_cleared(_topic_id, q_idx):
		area.modulate = Color(0.5, 0.5, 0.5, 0.7)

func _add_gym_node(gym: Dictionary, pos: Vector2, gym_idx: int) -> void:
	var gym_type: String = str(gym["type"])
	_gym_positions[gym_type] = pos
	var area := Area2D.new()
	area.position = pos
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 56.0
	shape.shape = circle
	area.add_child(shape)
	var label := Label.new()
	var badge := "GYM-CLEAR" if SessionManager.is_gym_cleared(_topic_id, gym_type) else "GYM"
	label.text = "%s\n%s G%d" % [badge, gym_type.capitalize(), gym_idx + 1]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-48, -32)
	area.add_child(label)
	area.body_entered.connect(_on_gym_touched.bind(gym_type))
	gyms_root.add_child(area)

func _add_champion_node(pos: Vector2) -> void:
	var area := Area2D.new()
	area.position = pos
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 64.0
	shape.shape = circle
	area.add_child(shape)
	var label := Label.new()
	if SessionManager.is_champion_defeated(_topic_id):
		label.text = "CHAMPION\nDOWN"
	elif SessionManager.is_champion_available(_topic_id):
		label.text = "CHAMPION\nFIGHT!"
	else:
		label.text = "CHAMPION\nLOCKED"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-56, -32)
	area.add_child(label)
	area.body_entered.connect(_on_champion_touched)
	gyms_root.add_child(area)

# --- Phase 9: gym-clear burst (CPUParticles2D, one-shot, auto-freed) ---
func _spawn_gym_burst(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = 26
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.gravity = Vector2(0, 140)
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 160.0
	p.angular_velocity_min = -120.0
	p.angular_velocity_max = 120.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 5.5
	p.color = Color(0.35, 0.95, 0.55)
	p.emitting = true
	add_child(p)
	p.restart()
	var t := Timer.new()
	t.wait_time = 1.2
	t.one_shot = true
	t.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
		t.queue_free()
	)
	add_child(t)
	t.start()

func _on_trainer_touched(_body: Node2D, q_idx: int) -> void:
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
	encounter_panel.visible = true

func _on_gym_touched(_body: Node2D, gym_type: String) -> void:
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
	encounter_panel.visible = true

func _on_champion_touched(_body: Node2D) -> void:
	# Pre-Champion summary screen: moveset preview with mastery badges.
	if SessionManager.is_champion_defeated(_topic_id):
		_pending_encounter = {}
		encounter_title.text = "Region Complete!"
		encounter_question.text = "You cleared every gym and dethroned the Champion. This region is yours."
		encounter_clear_btn.text = "Crowned"
		encounter_clear_btn.disabled = true
		encounter_panel.visible = true
		return
	if not SessionManager.is_champion_available(_topic_id):
		_pending_encounter = {}
		encounter_title.text = "Champion (locked)"
		encounter_question.text = "Earn every gym badge first — the Champion only faces proven trainers."
		encounter_clear_btn.text = "Locked"
		encounter_clear_btn.disabled = true
		encounter_panel.visible = true
		return
	var moveset := SessionManager.champion_moveset(_topic_id)
	if moveset.is_empty():
		_pending_encounter = {}
		encounter_title.text = "CHAMPION — not ready"
		encounter_question.text = "No Mastered questions yet. Win rematches to master questions, then face the Champion."
		encounter_clear_btn.text = "Locked"
		encounter_clear_btn.disabled = true
		encounter_panel.visible = true
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
	encounter_panel.visible = true

func _on_encounter_close() -> void:
	encounter_panel.visible = false
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
	encounter_panel.visible = false
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
			var pos: Vector2 = _gym_positions.get(t, Vector2(360, 600))
			_spawn_gym_burst(pos)
			_prev_cleared_gyms[t] = true
		elif now_cleared:
			_prev_cleared_gyms[t] = true
		badges += "[X]" if now_cleared else "[ ]"
	badges_label.text = "Gyms %d/%d %s" % [int(p["gyms_cleared"]), int(p["gyms_total"]), badges]

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/session_list.tscn")
