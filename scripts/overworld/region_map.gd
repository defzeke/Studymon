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

const ExplorerPicker := preload("res://scripts/overworld/explorer_picker.gd")
const BOLD: Font = preload("res://assets/fonts/JosefinSans-Bold.ttf")
const ICON_TRAINER: Texture2D = preload("res://assets/sprites/ui/icon_trainer.svg")
const ICON_BADGE: Texture2D = preload("res://assets/sprites/ui/icon_badge.svg")
const ICON_CROWN: Texture2D = preload("res://assets/sprites/ui/icon_crown.svg")
const ICON_LOCK: Texture2D = preload("res://assets/sprites/ui/icon_lock.svg")
const SLATE := Color("29383A")
const GRAY := Color("687778")
const TEAL := Color("4F8F89")
const OFF := Color("F7F5EF")
const AMBER := Color("D6A85F")
## How many upcoming objectives the list beside the minimap shows.
const OBJECTIVES_SHOWN := 3

@onready var map: Node3D = %Map
@onready var player: CharacterBody3D = %Player
@onready var kuiz: Node3D = %Kuiz
@onready var spawn: Marker3D = %Spawn
@onready var trainers_root: Node3D = %Trainers
@onready var gyms_root: Node3D = %Gyms
@onready var quest_tasks: HBoxContainer = %QuestTasks
@onready var quest_count: Label = %QuestCount
@onready var objectives: VBoxContainer = %Objectives
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

func _enter_tree() -> void:
	MusicManager.play_overworld()

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
	kuiz.place_behind()
	_build_route()
	_refresh_progress()
	player.set_explorer(GameState.explorer)
	# Each visit from the worlds list starts with picking the explorer; coming back from a battle or
	# flashcards keeps the one picked.
	if not GameState.explorer_picked:
		player.locked = true
		var picker := ExplorerPicker.new()
		picker.picked.connect(_on_explorer_picked)
		add_child(picker)

func _on_explorer_picked(id: String) -> void:
	GameState.explorer = id
	GameState.explorer_picked = true
	SaveManager.save_progress()
	player.set_explorer(id)
	player.locked = encounter_panel.visible

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
	_leave("res://scenes/battle/battle.tscn")

# The quest card: Trainers (cleared of all, with a bar), a badge per gym (lit once cleared) and the
# Champion (locked, ready or crowned), the count of all of them done, and the next objective.
func _refresh_progress() -> void:
	var gyms := SessionManager.get_gym_structure()
	var trainers_done := 0
	var trainers_total := 0
	var gyms_done := 0
	var badges: Array[bool] = []
	for g in gyms:
		var t: String = str(g["type"])
		for qi in g["trainer_indices"]:
			trainers_total += 1
			trainers_done += 1 if SessionManager.is_trainer_cleared(_topic_id, int(qi)) else 0
		var now_cleared := SessionManager.is_gym_cleared(_topic_id, t)
		if now_cleared and not _prev_cleared_gyms.has(t):
			# Fresh clear → burst at gym position.
			_spawn_gym_burst(_gym_positions.get(t, player.global_position))
		if now_cleared:
			_prev_cleared_gyms[t] = true
			gyms_done += 1
		badges.append(now_cleared)
	var crowned := SessionManager.is_champion_defeated(_topic_id)
	var champion_ready := SessionManager.is_champion_available(_topic_id)
	for c in quest_tasks.get_children():
		quest_tasks.remove_child(c)
		c.queue_free()
	var trainers := _task(ICON_TRAINER, "Trainers", "%d / %d" % [trainers_done, trainers_total])
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = maxi(trainers_total, 1)
	bar.value = trainers_done
	bar.add_theme_stylebox_override("background", _flat(Color(SLATE, 0.15), 4))
	bar.add_theme_stylebox_override("fill", _flat(TEAL, 4))
	trainers.get_child(1).add_child(bar)
	quest_tasks.add_child(trainers)
	var gym_task := _task(null, "Gyms", "%d / %d" % [gyms_done, gyms.size()])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for lit in badges:
		row.add_child(_icon(ICON_BADGE, 30, 1.0 if lit else 0.28))
	gym_task.add_child(row)
	gym_task.move_child(row, 0)
	quest_tasks.add_child(gym_task)
	quest_tasks.add_child(_task(ICON_CROWN if champion_ready or crowned else ICON_LOCK, "Champion", "Crowned" if crowned else ("Ready!" if champion_ready else "Locked")))
	quest_count.text = "%d / %d done" % [trainers_done + gyms_done + (1 if crowned else 0), trainers_total + gyms.size() + 1]
	_show_objectives(_objectives(gyms))

# Every step still to do, in order: each uncleared gym's unbeaten trainers (easiest first, the
# order they stand on its road), then its boss; then the Champion.
func _objectives(gyms: Array[Dictionary]) -> Array[String]:
	var steps: Array[String] = []
	if SessionManager.is_champion_defeated(_topic_id):
		steps.append("Region complete! You are the Champion.")
		return steps
	var questions := SessionManager.get_pending_questions()
	for g in gyms:
		var t: String = str(g["type"])
		if SessionManager.is_gym_cleared(_topic_id, t):
			continue
		var gym_name := t.capitalize().replace("_", " ")
		for qi in g["trainer_indices"]:
			if not SessionManager.is_trainer_cleared(_topic_id, int(qi)):
				var tier := str((questions[int(qi)] as Dictionary).get("difficulty", "medium")).capitalize()
				steps.append("Beat Trainer %d (%s) on the %s road" % [int(qi) + 1, tier, gym_name])
		steps.append("Challenge the %s gym boss" % gym_name)
	steps.append("Challenge the Champion" if not gyms.is_empty() else "Walk into a trainer or gym")
	return steps

# A bare bullet list beside the minimap (no panel): Off-White text with a Deep Slate outline so it
# reads over the map; the current step has an amber bullet, the later ones are dimmer.
func _show_objectives(steps: Array[String]) -> void:
	for c in objectives.get_children():
		objectives.remove_child(c)
		c.queue_free()
	for i in mini(steps.size(), OBJECTIVES_SHOWN):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := _outlined("●", 22, AMBER if i == 0 else OFF)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(dot)
		var text := _outlined(steps[i], 22 if i == 0 else 19, OFF)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		row.modulate.a = 1.0 if i == 0 else 0.85
		objectives.add_child(row)
	if steps.size() > OBJECTIVES_SHOWN:
		var more := _outlined("+%d more" % (steps.size() - OBJECTIVES_SHOWN), 17, OFF)
		more.modulate.a = 0.75
		objectives.add_child(more)

func _outlined(text: String, size: int, color: Color) -> Label:
	var l := _text(text, size, color)
	l.add_theme_color_override("font_outline_color", SLATE)
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# One task chip: an icon (when given), the task's name and its value, stacked beside it.
func _task(icon: Texture2D, title: String, value: String) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_constant_override("separation", 8)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != null:
		chip.add_child(_icon(icon, 44, 1.0))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(_text(title, 15, GRAY))
	text.add_child(_text(value, 22, SLATE))
	chip.add_child(text)
	return chip

func _icon(tex: Texture2D, size: float, alpha: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate.a = alpha
	return r

func _text(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", BOLD)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	return b

func _on_back() -> void:
	_leave("res://scenes/ui/session_list.tscn")

func _on_study() -> void:
	SessionManager.flashcards_return = "res://scenes/overworld/region_map.tscn"
	_leave("res://scenes/review_session/flashcards.tscn")

func _leave(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
