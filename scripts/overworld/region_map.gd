extends Node3D
## Phase 6: 3D Overworld & Gym Structure (GDD §6.1). Contract: docs/systems/overworld.md.
## The island in assets/models/map.glb, seen from an angled top-down camera that follows the
## explorer. One gym per question category, each at one of the GymSlots placed in region_map.tscn,
## with hallway trainers on the road leading to it. Trainer/boss triggers hand off to Battle (Phase 7).
## Phase 8: trainer markers carry mastery colours; the Champion holds the big gym —
## unlocks when all gym badges are earned, moveset = Mastered questions,
## clearing the gauntlet completes the region.
## Phase 9: particle burst on gym clear.

# Where everything stands is set in region_map.tscn: one GymSlot per gym, in question-type order,
# plus one for the Champion. A slot's markers place the gym and its trainer road, so nothing is found
# by node name. Collision rules live on the MapCollision node.
@export var gym_slots: Array[GymSlot] = []
@export var champion_slot: GymSlot
@export var trigger_scene: PackedScene
@export var burst_scene: PackedScene
## Plays the door clips. Left empty, the map's own AnimationPlayer is used.
@export var map_anim: AnimationPlayer
@export var trigger_radius := 0.7
@export var trainer_radius := 0.45

@onready var map: Node3D = %Map
@onready var player: CharacterBody3D = %Player
@onready var spawn: Marker3D = %Spawn
@onready var trainers_root: Node3D = %Trainers
@onready var gyms_root: Node3D = %Gyms
@onready var progress_label: Label = %ProgressLabel
@onready var badges_label: Label = %BadgesLabel
@onready var back_btn: Button = %BackButton
@onready var study_btn: Button = %StudyButton
@onready var encounter_panel: PanelContainer = %EncounterPanel
@onready var encounter_title: Label = %EncounterTitle
@onready var encounter_question: Label = %EncounterQuestion
@onready var encounter_close_btn: Button = %EncounterCloseButton
@onready var encounter_clear_btn: Button = %EncounterClearButton

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
	if map_anim == null:
		map_anim = map.find_child("AnimationPlayer", true, false) as AnimationPlayer
	back_btn.pressed.connect(_on_back)
	study_btn.pressed.connect(_on_study)
	encounter_close_btn.pressed.connect(_on_encounter_close)
	encounter_clear_btn.pressed.connect(_on_encounter_cleared)
	_show_encounter(false)
	SessionManager.overworld_progress_changed.connect(_refresh_progress)
	if spawn != null:
		player.global_position = spawn.global_position
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
	# One gym per question type, in slot order.
	for gi in mini(gyms.size(), gym_slots.size()):
		var slot := gym_slots[gi]
		_add_gym_node(gyms[gi], slot, gi)
		# Hallway trainers for this gym, spread along its road (trainers_from → trainers_to).
		if slot.trainers_from == null or slot.trainers_to == null:
			continue
		var from := slot.trainers_from.global_position
		var to := slot.trainers_to.global_position
		var indices: Array = gyms[gi]["trainer_indices"]
		for ti in indices.size():
			_add_trainer_node(int(indices[ti]), from.lerp(to, float(ti + 1) / float(indices.size() + 1)))
	_add_champion_node()
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
	var tier := str(questions[q_idx].get("difficulty", "medium"))
	var area := _trigger(pos, trainer_radius, "T%d\n%s" % [q_idx + 1, tier.capitalize()])
	area.show_pad = true
	area.pad_color = badge["color"]
	area.body_entered.connect(_on_trainer_touched.bind(q_idx))
	trainers_root.add_child(area)
	# Dim if already cleared
	if SessionManager.is_trainer_cleared(_topic_id, q_idx):
		area.dim()

func _add_gym_node(gym: Dictionary, slot: GymSlot, gym_idx: int) -> void:
	if slot.entrance == null:
		return
	var gym_type: String = str(gym["type"])
	var badge := "BADGE" if SessionManager.is_gym_cleared(_topic_id, gym_type) else "GYM %d" % (gym_idx + 1)
	var area := _trigger(slot.entrance.global_position, trigger_radius, "%s\n%s" % [badge, gym_type.capitalize()])
	_gym_positions[gym_type] = area.position
	area.body_entered.connect(_on_gym_touched.bind(gym_type))
	_door_animates(area, slot)
	gyms_root.add_child(area)

func _add_champion_node() -> void:
	if champion_slot == null or champion_slot.entrance == null:
		return
	var state := "LOCKED"
	if SessionManager.is_champion_defeated(_topic_id):
		state = "DOWN"
	elif SessionManager.is_champion_available(_topic_id):
		state = "FIGHT!"
	var area := _trigger(champion_slot.entrance.global_position, trigger_radius, "CHAMPION\n%s" % state)
	area.body_entered.connect(_on_champion_touched)
	_door_animates(area, champion_slot)
	gyms_root.add_child(area)

# Opens and closes the gym's door as the explorer enters and leaves; a slot with no clips has no door.
func _door_animates(area: Area3D, slot: GymSlot) -> void:
	if map_anim == null:
		return
	if map_anim.has_animation(slot.door_open_clip):
		area.body_entered.connect(func(_b: Node3D) -> void: map_anim.play(slot.door_open_clip))
	if map_anim.has_animation(slot.door_close_clip):
		area.body_exited.connect(func(_b: Node3D) -> void: map_anim.play(slot.door_close_clip))

# A trigger the explorer walks into, from encounter_trigger.tscn; the caller adds it to the tree.
func _trigger(pos: Vector3, radius: float, text: String) -> EncounterTrigger:
	var area := trigger_scene.instantiate() as EncounterTrigger
	area.position = pos
	area.radius = radius
	area.text = text
	return area

# --- Phase 9: gym-clear burst (one-shot, auto-freed) ---
func _spawn_gym_burst(pos: Vector3) -> void:
	if burst_scene == null:
		return
	var p := burst_scene.instantiate() as CPUParticles3D
	p.position = pos + Vector3.UP * 0.5
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
	var boss := -1
	var count := 0
	for g in SessionManager.get_gym_structure():
		if str(g["type"]) == gym_type:
			boss = int(g["boss_index"])
			count = (g["question_indices"] as Array).size()
			break
	_pending_encounter = {"kind": "gym", "gym": gym_type, "boss_index": boss}
	var cleared := SessionManager.is_gym_cleared(_topic_id, gym_type)
	var left := SessionManager.gym_trainers_left(_topic_id, gym_type)
	var locked := not cleared and left > 0
	encounter_title.text = "Gym: %s %s" % [gym_type.capitalize(), "(badge earned)" if cleared else ("— boss locked" if locked else "— boss ahead!")]
	if locked:
		encounter_question.text = "Beat %d more trainer(s) on the road first, easiest to hardest, then face the boss." % left
	else:
		encounter_question.text = "%d question(s) in this gym. The boss is its hardest question." % count
	encounter_clear_btn.text = "Badge Earned" if cleared else ("Boss Locked" if locked else "Fight Boss!")
	encounter_clear_btn.disabled = cleared or locked
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
	var all_questions := SessionManager.mastered_indices(_topic_id).is_empty()
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
	var fields := "every question, since none is Mastered yet" if all_questions else "your Mastered questions"
	encounter_question.text = "The Champion fields %s, easiest first:\n" % fields + "\n".join(lines) + "\nWin them all back-to-back to complete the region!"
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
		var boss := int(_pending_encounter.get("boss_index", -1))
		if boss < 0 or SessionManager.gym_trainers_left(_topic_id, str(_pending_encounter["gym"])) > 0:
			return
		SessionManager.begin_battle(_topic_id, boss, true)
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

func _on_study() -> void:
	SessionManager.flashcards_return = "res://scenes/overworld/region_map.tscn"
	get_tree().change_scene_to_file("res://scenes/review_session/flashcards.tscn")
