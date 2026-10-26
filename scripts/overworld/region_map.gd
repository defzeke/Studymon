extends Node3D
## 3D Overworld (GDD §6.1). Contract: docs/systems/overworld.md.
## The island in assets/models/map.glb, seen from an angled top-down camera that follows the
## explorer. One gym per question type at the GymSlots placed in region_map.tscn; every house on the
## island is a Challenge House (MapHouses finds them), entered by walking into the house itself. The
## Champion holds the big gym. Houses and gyms hand off to Battle as a run (docs/systems/battle.md).

# Gyms stand where region_map.tscn places them: one GymSlot per gym, in question-type order, plus one for
# the Champion. Houses come from the map itself. Collision rules live on the MapCollision node.
@export var gym_slots: Array[GymSlot] = []
@export var champion_slot: GymSlot
@export var trigger_scene: PackedScene
@export var burst_scene: PackedScene
## Plays the door clips. Left empty, the map's own AnimationPlayer is used.
@export var map_anim: AnimationPlayer
@export var trigger_radius := 0.7
## Walking into a house opens it: a collision of the explorer with anything within this distance of a
## house's footprint (its walls, the windows sticking out of them, its door) counts as touching it.
@export var house_contact := 0.35
## The area around a house, its footprint grown by this much: entering it opens the doorway, and
## leaving it lets a house whose panel was closed open again.
@export var house_margin := 0.6
## A house's label shows only while the explorer is this close, so 15 labels do not crowd the screen.
@export var house_label_near := 4.0

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
const LILAC := Color("8D82A8")
## Each question type's colour: the icon over its houses.
const TYPE_COLORS := {"identification": TEAL, "essay": LILAC, "multiple_choice": AMBER}
## An open doorway: the dark inside of a house, shown when the explorer walks up to it.
const DOORWAY := Color("1E2829")
## How many upcoming objectives the list beside the minimap shows.
const OBJECTIVES_SHOWN := 3
## A house label floats this high so it clears the roof; the map's houses stand about 2 units tall.
const HOUSE_LABEL_HEIGHT := 2.6
## Entering a house or gym fades the screen to this over FADE_SEC; coming back fades it in again.
const FADE_COLOR := Color("F7F5EF")
const FADE_SEC := 0.35

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
var _fade: ColorRect
## The island's houses (MapHouses.find), each with the question type it plays ("type").
var _houses: Array[Dictionary] = []
## The id of a house whose panel was just closed: it stays shut until the explorer steps away from it,
## so leaning on the wall does not reopen the panel every frame.
var _dismissed_house := ""
## Where the explorer comes back out after a battle: {topic, pos, face}. Static, so it outlives the
## scene change to the battle and back.
static var _return_to: Dictionary = {}

func _enter_tree() -> void:
	MusicManager.play_overworld()

func _ready() -> void:
	_build_fade()
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
	# Back from a battle: step out of the building that was entered, facing away from it.
	if _return_to.get("topic", "") == _topic_id:
		player.global_position = _return_to["pos"]
		player.face(_return_to["face"])
	_return_to = {}
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

func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	_fade = ColorRect.new()
	_fade.color = FADE_COLOR
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	add_child(layer)
	var t := _fade.create_tween()
	t.tween_property(_fade, "color:a", 0.0, FADE_SEC)

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
	# One gym per question type, in slot order; every house plays the type of a gym near it.
	for gi in mini(gyms.size(), gym_slots.size()):
		_add_gym_node(str(gyms[gi]["type"]), gym_slots[gi], gi)
	_houses = MapHouses.find(map)
	_assign_types(gyms)
	for house in _houses:
		_add_house_node(house)
	_add_champion_node()
	# Snapshot cleared state on build so we don't burst for saves that already cleared.
	_prev_cleared_gyms.clear()
	for g in gyms:
		var t: String = str(g["type"])
		if SessionManager.is_gym_cleared(_topic_id, t):
			_prev_cleared_gyms[t] = true

# Shares the houses out between the question types: each house goes to the nearest gym that still has
# room, so every type gets about the same number of houses and they cluster around their gym.
func _assign_types(gyms: Array[Dictionary]) -> void:
	var slots := mini(gyms.size(), gym_slots.size())
	if slots == 0:
		return
	var room := ceili(float(_houses.size()) / slots)
	var pairs: Array = []
	for h in _houses.size():
		var at: Vector3 = (_houses[h]["box"] as AABB).get_center()
		for g in slots:
			if gym_slots[g].entrance != null:
				pairs.append([Vector2(at.x, at.z).distance_to(Vector2(gym_slots[g].entrance.global_position.x, gym_slots[g].entrance.global_position.z)), h, g])
	pairs.sort()
	var taken: Array[int] = []
	taken.resize(slots)
	for p in pairs:
		var h: int = p[1]
		var g: int = p[2]
		if not _houses[h].has("type") and taken[g] < room:
			_houses[h]["type"] = str(gyms[g]["type"])
			taken[g] += 1

# A house is a Challenge House: walking into the house itself opens the panel (_physics_process), and its
# door "opens" (a dark doorway) while the explorer is near it, like the gyms' doors.
func _add_house_node(house: Dictionary) -> void:
	if not house.has("type"):
		return
	var t: String = house["type"]
	var id: String = house["id"]
	var cleared := SessionManager.is_house_cleared(_topic_id, t, id)
	var state := "%d/3 stars" % SessionManager.best_stars("house", _topic_id, "%s#%s" % [t, id]) if cleared else "Easy"
	var box: AABB = house["box"]
	var area := trigger_scene.instantiate() as EncounterTrigger
	area.position = Vector3(box.get_center().x, 0.0, box.get_center().z)
	area.box = Vector3(box.size.x + house_margin * 2.0, box.size.y, box.size.z + house_margin * 2.0)
	area.text = "%s\n%s" % [_type_name(t), state]
	area.label_height = HOUSE_LABEL_HEIGHT
	trainers_root.add_child(area)
	area.label.visible = false
	var doorway := _add_doorway(area, house)
	area.body_entered.connect(func(_b: Node3D) -> void: _open_doorway(doorway, true))
	area.body_exited.connect(func(_b: Node3D) -> void:
		_open_doorway(doorway, false)
		if _dismissed_house == id:
			_dismissed_house = "")
	_add_house_icon(area, TYPE_COLORS.get(t, TEAL), cleared)
	if cleared:
		area.dim()

# The inside of the door: a dark panel just in front of it, folded shut (zero width) until opened.
func _add_doorway(area: Node3D, house: Dictionary) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = house["door_size"]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = DOORWAY
	quad.material = mat
	var doorway := MeshInstance3D.new()
	doorway.mesh = quad
	var facing: Vector3 = house["facing"]
	doorway.position = (house["door"] as Vector3) - area.position + facing * 0.02
	doorway.basis = Basis.looking_at(-facing)
	doorway.scale = Vector3(0.01, 1, 1)
	doorway.visible = false
	area.add_child(doorway)
	return doorway

func _open_doorway(doorway: MeshInstance3D, open: bool) -> void:
	doorway.visible = true
	var t := doorway.create_tween()
	t.tween_property(doorway, "scale:x", 1.0 if open else 0.01, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not open:
		t.tween_callback(doorway.hide)

# A bobbing icon over the roof in the house's type colour, faint once the house is cleared.
func _add_house_icon(area: EncounterTrigger, color: Color, cleared: bool) -> void:
	var icon := Sprite3D.new()
	icon.texture = ICON_TRAINER
	icon.pixel_size = 0.003
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.modulate = Color(color, 0.4 if cleared else 1.0)
	icon.position = Vector3(0, HOUSE_LABEL_HEIGHT - 0.3, 0)
	area.add_child(icon)
	var t := icon.create_tween().set_loops()
	t.tween_property(icon, "position:y", HOUSE_LABEL_HEIGHT - 0.15, 0.7).set_trans(Tween.TRANS_SINE)
	t.tween_property(icon, "position:y", HOUSE_LABEL_HEIGHT - 0.3, 0.7).set_trans(Tween.TRANS_SINE)

# The explorer walked into something: if it is part of a house (its contact point lies on the house's
# footprint, give or take the windows), that house opens. Windows, trees and lamp posts can keep the
# explorer from reaching any box drawn around a house, but they cannot hide the bump itself.
func _physics_process(_delta: float) -> void:
	if player.locked or encounter_panel.visible:
		return
	for i in player.get_slide_collision_count():
		var at := player.get_slide_collision(i).get_position()
		for house in _houses:
			if not house.has("type") or house["id"] == _dismissed_house:
				continue
			var box: AABB = house["box"]
			if at.x > box.position.x - house_contact and at.x < box.end.x + house_contact \
					and at.z > box.position.z - house_contact and at.z < box.end.z + house_contact:
				_on_house_touched(house)
				return

# House labels show only near the explorer; the icons mark the houses from afar.
func _process(_delta: float) -> void:
	for area: Node in trainers_root.get_children():
		if area is EncounterTrigger:
			var near := player.global_position.distance_to((area as Node3D).global_position) < house_label_near
			(area as EncounterTrigger).label.visible = near

func _type_name(t: String) -> String:
	return t.capitalize().replace("_", " ")

func _houses_of(t: String) -> int:
	var n := 0
	for h in _houses:
		n += 1 if h.get("type", "") == t else 0
	return n

# The midpoint of a gym's double door (its Left and Right leaves, named after the slot's clips), or
# Vector3.INF for a gym with no door.
func _gym_door(slot: GymSlot) -> Vector3:
	var base := String(slot.door_open_clip).trim_suffix("_Open")
	var left := map.find_child(base + "_Left", true, false) as Node3D
	var right := map.find_child(base + "_Right", true, false) as Node3D
	if base == "" or left == null or right == null:
		return Vector3.INF
	return (left.global_position + right.global_position) / 2.0

func _add_gym_node(gym_type: String, slot: GymSlot, gym_idx: int) -> void:
	if slot.entrance == null:
		return
	var state := "%d/3 stars" % SessionManager.best_stars("gym", _topic_id, gym_type)
	if not SessionManager.is_gym_cleared(_topic_id, gym_type):
		state = "GYM %d" % (gym_idx + 1) if SessionManager.is_gym_open(_topic_id, gym_type) else "LOCKED"
	var area := _trigger(slot.entrance.global_position, trigger_radius, "%s\n%s" % [state, gym_type.capitalize()])
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

# What a run is: its items, its tier and how long it takes to review.
func _run_blurb(kind: String, gym_type: String) -> String:
	var low := CompanionState.readiness() < 25.0
	var items := SessionManager.run_items(kind, gym_type)
	var have := SessionManager.get_pending_questions().size()
	var text := "%d items · %s · at least %d minutes.\nKuiz readiness %d%%%s" % [
		items, str(SessionManager.RUN_TIER[kind]).capitalize(), SessionManager.RUN_MINUTES[kind],
		roundi(CompanionState.readiness()), " (low — feed and rest Kuiz first)" if low else ""]
	if have < items:
		text += "\nThis world has %d question%s, so they repeat. Add more with Edit on the worlds list." % [have, "" if have == 1 else "s"]
	return text

func _on_house_touched(house: Dictionary) -> void:
	var t: String = house["type"]
	var id: String = house["id"]
	_pending_encounter = {"kind": "house", "gym": t, "house": house}
	var cleared := SessionManager.is_house_cleared(_topic_id, t, id)
	var stars := SessionManager.best_stars("house", _topic_id, "%s#%s" % [t, id])
	encounter_title.text = "Challenge House · %s%s" % [_type_name(t), "  %s" % "★".repeat(stars) if cleared else ""]
	var line := "\n%d of %d %s houses cleared." % [SessionManager.houses_cleared(_topic_id, t), _houses_of(t), _type_name(t)]
	if not SessionManager.is_gym_open(_topic_id, t):
		line += " Clear one to open the %s Gym." % _type_name(t)
	encounter_question.text = _run_blurb("house", t) + line + ("\nReplays pay a quarter of the rewards." if cleared else "")
	encounter_clear_btn.text = "Replay" if cleared else "Go inside"
	encounter_clear_btn.disabled = false
	_show_encounter(true)

func _on_gym_touched(_body: Node3D, gym_type: String) -> void:
	_pending_encounter = {"kind": "gym", "gym": gym_type}
	var cleared := SessionManager.is_gym_cleared(_topic_id, gym_type)
	var open := SessionManager.is_gym_open(_topic_id, gym_type)
	encounter_title.text = "Gym: %s%s" % [gym_type.capitalize(), " (badge earned)" if cleared else ("" if open else " — locked")]
	if open:
		encounter_question.text = _run_blurb("gym", gym_type) + ("\nReplays pay a quarter of the rewards." if cleared else "")
	else:
		encounter_question.text = "Clear any %s Challenge House first: look for the %s icons over the roofs." % [_type_name(gym_type), _type_name(gym_type)]
	encounter_clear_btn.text = "Replay" if cleared else ("Enter Gym" if open else "Locked")
	encounter_clear_btn.disabled = not open
	_show_encounter(true)

func _on_champion_touched(_body: Node3D) -> void:
	_pending_encounter = {}
	if not SessionManager.is_champion_available(_topic_id):
		encounter_title.text = "Champion Gym (locked)"
		encounter_question.text = "Earn every gym badge first — the Champion only faces proven players."
		encounter_clear_btn.text = "Locked"
		encounter_clear_btn.disabled = true
		_show_encounter(true)
		return
	var crowned := SessionManager.is_champion_defeated(_topic_id)
	_pending_encounter = {"kind": "champion"}
	encounter_title.text = "Champion Gym" + (" (crowned)" if crowned else "")
	encounter_question.text = _run_blurb("champion", "") + "\nMultiple choice, then identification, then essay — against the toughest robot." + ("\nReplays pay a quarter of the rewards." if crowned else "")
	encounter_clear_btn.text = "Replay" if crowned else "Challenge Champion!"
	encounter_clear_btn.disabled = false
	_show_encounter(true)

# The explorer stands still while a panel is open.
func _show_encounter(shown: bool) -> void:
	encounter_panel.visible = shown
	player.locked = shown

func _on_encounter_close() -> void:
	var house: Dictionary = _pending_encounter.get("house", {})
	if not house.is_empty():
		_dismissed_house = house["id"]
	_show_encounter(false)
	_pending_encounter = {}

func _on_encounter_cleared() -> void:
	if _pending_encounter.is_empty():
		return
	var kind: String = _pending_encounter.get("kind", "")
	var gym_type: String = _pending_encounter.get("gym", "")
	if kind == "gym" and not SessionManager.is_gym_open(_topic_id, gym_type):
		return
	if kind == "champion" and not SessionManager.is_champion_available(_topic_id):
		return
	var house: Dictionary = _pending_encounter.get("house", {})
	var house_id: String = house.get("id", "")
	if not SessionManager.begin_run(_topic_id, kind, gym_type, house_id, _houses.find(house) + 1):
		encounter_question.text = "This world has no questions yet. Add some with Edit on the worlds list."
		encounter_clear_btn.disabled = true
		return
	var entry := _pending_encounter
	_show_encounter(false)
	_pending_encounter = {}
	await _go_inside(entry)
	_leave("res://scenes/battle/battle.tscn")

# Entering a building: the explorer walks through its door, and the way back out is remembered so the
# explorer steps out of the same building after the battle.
func _go_inside(entry: Dictionary) -> void:
	var door := Vector3.INF
	var out_dir := Vector3.ZERO
	var outside := player.global_position
	var house: Dictionary = entry.get("house", {})
	if not house.is_empty():
		# The explorer comes back out where it went in: the spot it touched the house from, which it could
		# reach (a tree or lamp post may stand in front of the door itself).
		var centre: Vector3 = (house["box"] as AABB).get_center()
		out_dir = Vector3(outside.x - centre.x, 0.0, outside.z - centre.z).normalized()
		# On the door's side it walks in through the door; from any other side it just goes in.
		var to_door := outside - (house["door"] as Vector3)
		if Vector3(to_door.x, 0.0, to_door.z).dot(house["facing"]) > 0.0:
			door = house["door"]
	else:
		var slot: GymSlot = champion_slot
		var gi := SessionManager.RUN_TYPES.find(str(entry.get("gym", "")))
		if entry.get("kind") == "gym":
			slot = gym_slots[gi] if gi >= 0 and gi < gym_slots.size() else null
		if slot != null and slot.entrance != null:
			door = _gym_door(slot)
			if door != Vector3.INF:
				var e := slot.entrance.global_position
				out_dir = Vector3(e.x - door.x, 0.0, e.z - door.z).normalized()
				outside = e + out_dir * (trigger_radius + 0.4)
	# A gym with no door (GymSlot3) has no inside to come out of: the explorer starts at the spawn.
	if out_dir != Vector3.ZERO:
		_return_to = {"topic": _topic_id, "pos": Vector3(outside.x, 0.0, outside.z), "face": out_dir}
	player.locked = true
	if door != Vector3.INF:
		await player.walk_into(door)

# The quest card: Houses (cleared of all, with a bar), a badge per gym (lit once cleared) and the
# Champion (locked, ready or crowned), the count of all of them done, and the next objective.
func _refresh_progress() -> void:
	var gyms := SessionManager.get_gym_structure()
	var houses_done := 0
	for h in _houses:
		if h.has("type") and SessionManager.is_house_cleared(_topic_id, h["type"], h["id"]):
			houses_done += 1
	var gyms_done := 0
	var badges: Array[bool] = []
	for g in gyms:
		var t: String = str(g["type"])
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
	var houses := _task(ICON_TRAINER, "Houses", "%d / %d" % [houses_done, _houses.size()])
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = maxi(_houses.size(), 1)
	bar.value = houses_done
	bar.add_theme_stylebox_override("background", _flat(Color(SLATE, 0.15), 4))
	bar.add_theme_stylebox_override("fill", _flat(TEAL, 4))
	houses.get_child(1).add_child(bar)
	quest_tasks.add_child(houses)
	var gym_task := _task(null, "Gyms", "%d / %d" % [gyms_done, gyms.size()])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for lit in badges:
		row.add_child(_icon(ICON_BADGE, 30, 1.0 if lit else 0.28))
	gym_task.add_child(row)
	gym_task.move_child(row, 0)
	quest_tasks.add_child(gym_task)
	quest_tasks.add_child(_task(ICON_CROWN if champion_ready or crowned else ICON_LOCK, "Champion", "Crowned" if crowned else ("Ready!" if champion_ready else "Locked")))
	quest_count.text = "%d / %d done" % [houses_done + gyms_done + (1 if crowned else 0), _houses.size() + gyms.size() + 1]
	_show_objectives(_objectives(gyms, _houses.size() - houses_done))

# Every step still to do, in order: a house of each type (which opens its gym), then the gym; then the
# Champion; and the houses still standing, which are optional but pay their first-clear bonus.
func _objectives(gyms: Array[Dictionary], houses_left: int) -> Array[String]:
	var steps: Array[String] = []
	if not SessionManager.is_champion_defeated(_topic_id):
		for g in gyms:
			var t: String = str(g["type"])
			if not SessionManager.is_gym_open(_topic_id, t):
				steps.append("Enter a house marked %s (%d on the island)" % [_type_name(t), _houses_of(t)])
			if not SessionManager.is_gym_cleared(_topic_id, t):
				steps.append("Clear the %s Gym" % _type_name(t))
		steps.append("Challenge the Champion Gym" if not gyms.is_empty() else "Walk into a house or gym")
	else:
		steps.append("Region complete! You are the Champion.")
	if houses_left > 0:
		steps.append("Clear the other houses (%d left)" % houses_left)
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

# Fades to FADE_COLOR, then changes scene: stepping through a door feels like going in.
func _leave(scene: String) -> void:
	player.locked = true
	var t := _fade.create_tween()
	t.tween_property(_fade, "color:a", 1.0, FADE_SEC)
	await t.finished
	get_tree().change_scene_to_file(scene)
