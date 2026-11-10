extends Node3D
## The 3D overworld. Contract: docs/systems/overworld.md.
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
## A house badge opens to show its type and tier only while the explorer is this close.
@export var house_label_near := 4.0
## A Challenge House trigger: encounter_trigger.tscn plus the Badge that bobs over its roof and the
## dark Doorway that unfolds over its door (house_trigger.tscn).
@export var house_scene: PackedScene
## Fast travel lands only on ground meshes whose name holds one of these: outdoors, never a floor
## inside a house or gym.
@export var travel_ground_keywords: PackedStringArray = ["Ground_Roads", "Grass_Blocks", "Sand_", "_Path"]

@export_group("HUD")
## The Champion chip's icon once the Champion is open or beaten, and while it is still locked.
@export var icon_crown: Texture2D
@export var icon_lock: Texture2D

const ExplorerPicker := preload("res://scenes/overworld/explorer_picker.tscn")
const PlayerScript := preload("res://scripts/overworld/player.gd")
## MapCollision's obstacle layer (trees, walls, lamp posts): fast travel never lands in one.
const OBSTACLE_LAYER := 2
## Each question type's colour: the icon over its houses.
const TYPE_COLORS := {"identification": Palette.TEAL, "essay": Palette.LILAC, "multiple_choice": Palette.AMBER}
## A house label floats this high so it clears the roof; the map's houses stand about 2 units tall.
const HOUSE_LABEL_HEIGHT := 2.6
## Entering a house or gym fades the screen to %Fade's colour over FADE_SEC; coming back fades it in.
const FADE_SEC := 0.35
## Arriving: held for the first heavy frames, which would skip a tween, then this long.
const ARRIVE_FADE_SEC := 0.8
## Fast travel: the explorer shrinks away in this long, and pops back in about 1.5 times as long.
const TRAVEL_SEC := 0.3

@onready var map: Node3D = %Map
@onready var player: CharacterBody3D = %Player
@onready var kuiz: Node3D = %Kuiz
@onready var spawn: Marker3D = %Spawn
@onready var trainers_root: Node3D = %Trainers
@onready var gyms_root: Node3D = %Gyms
@onready var quest_count: Label = %QuestCount
@onready var houses_value: Label = %HousesValue
@onready var houses_bar: ProgressBar = %HousesBar
@onready var gym_badges: HBoxContainer = %GymBadges
@onready var badge_template: TextureRect = %BadgeTemplate
@onready var gyms_value: Label = %GymsValue
@onready var champion_icon: TextureRect = %ChampionIcon
@onready var champion_value: Label = %ChampionValue
@onready var objectives: VBoxContainer = %Objectives
@onready var _fade: ColorRect = %Fade
@onready var back_btn: Button = %BackButton
@onready var study_btn: Button = %StudyButton
@onready var encounter_panel: Control = %EncounterPanel
@onready var encounter_title: Label = %EncounterTitle
@onready var encounter_question: Label = %EncounterQuestion
@onready var encounter_close_btn: Button = %EncounterCloseButton
@onready var encounter_clear_btn: Button = %EncounterClearButton
@onready var minimap: Control = $HUD/Minimap
@onready var travel_hint: Label = %TravelHint

var _topic_id: String = ""
var _pick_on_arrival := false
var _leaving := false
var _pending_encounter: Dictionary = {}
var _gym_positions: Dictionary = {}
var _prev_cleared_gyms: Dictionary = {}
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
	_fade.color.a = 1.0
	_arrive()
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
	if map_anim == null:
		map_anim = map.find_child("AnimationPlayer", true, false) as AnimationPlayer
	back_btn.pressed.connect(_on_back)
	study_btn.pressed.connect(_on_study)
	%ExplorerButton.pressed.connect(_on_change_explorer)
	encounter_close_btn.pressed.connect(_on_encounter_close)
	encounter_clear_btn.pressed.connect(_on_encounter_cleared)
	minimap.travel_picked.connect(_on_travel_picked)
	%MapOverlay.visibility_changed.connect(_reset_travel_hint)
	_reset_travel_hint()
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
	var chosen := SessionManager.world_explorer(_topic_id)
	player.set_explorer(chosen if chosen != "" else "boy")
	# Coming from home the player picks first; back from a battle or Study they carry on.
	_pick_on_arrival = chosen == "" or SessionManager.pick_explorer
	SessionManager.pick_explorer = false
	player.locked = _pick_on_arrival

func _arrive() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _pick_on_arrival:
		_open_picker(SessionManager.world_explorer(_topic_id))
	var t := _fade.create_tween()
	t.tween_property(_fade, "color:a", 0.0, ARRIVE_FADE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _open_picker(current: String) -> void:
	player.locked = true
	var picker := ExplorerPicker.instantiate()
	picker.current = current
	picker.picked.connect(_on_explorer_picked)
	add_child(picker)

# Any time on the map, except over an encounter panel or while leaving.
func _on_change_explorer() -> void:
	if not player.locked:
		_open_picker(SessionManager.world_explorer(_topic_id))

func _on_explorer_picked(id: String) -> void:
	SessionManager.set_world_explorer(_topic_id, id)
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
	# One gym per question type the world has, in its type's slot; every house plays the type of a gym near it.
	for gi in gyms.size():
		var slot := _slot_of(str(gyms[gi]["type"]))
		if slot != null:
			_add_gym_node(str(gyms[gi]["type"]), slot, gi)
	_houses = MapHouses.find(map)
	_assign_types(gyms)
	_number_houses()
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
	var slots := gyms.size()
	if slots == 0:
		return
	var room := ceili(float(_houses.size()) / slots)
	var pairs: Array = []
	for h in _houses.size():
		var at: Vector3 = (_houses[h]["box"] as AABB).get_center()
		for g in slots:
			var slot := _slot_of(str(gyms[g]["type"]))
			if slot != null and slot.entrance != null:
				pairs.append([Vector2(at.x, at.z).distance_to(Vector2(slot.entrance.global_position.x, slot.entrance.global_position.z)), h, g])
	pairs.sort()
	var taken: Array[int] = []
	taken.resize(slots)
	for p in pairs:
		var h: int = p[1]
		var g: int = p[2]
		if not _houses[h].has("type") and taken[g] < room:
			_houses[h]["type"] = str(gyms[g]["type"])
			taken[g] += 1

# The houses' route ("num", from 1): nearest the spawn first, then each next one nearest the last. They
# are cleared in this order; only the next uncleared one can be entered (cleared ones replay).
func _number_houses() -> void:
	var left: Array = _houses.filter(func(h: Dictionary) -> bool: return h.has("type"))
	var at := spawn.global_position if spawn != null else Vector3.ZERO
	var n := 1
	while not left.is_empty():
		var from := Vector2(at.x, at.z)
		left.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _house_xz(a).distance_to(from) < _house_xz(b).distance_to(from))
		var h: Dictionary = left.pop_front()
		h["num"] = n
		n += 1
		at = (h["box"] as AABB).get_center()

func _house_xz(h: Dictionary) -> Vector2:
	var c := (h["box"] as AABB).get_center()
	return Vector2(c.x, c.z)

# The first house on the route not yet cleared; {} once every house is.
func _next_house() -> Dictionary:
	var best: Dictionary = {}
	for h in _houses:
		if h.has("num") and not SessionManager.is_house_cleared(_topic_id, h["type"], h["id"]) \
				and (best.is_empty() or int(h["num"]) < int(best["num"])):
			best = h
	return best

# A type's gym building: gym_slots is in SessionManager.RUN_TYPES order, whichever types the world has.
func _slot_of(gym_type: String) -> GymSlot:
	var i := SessionManager.RUN_TYPES.find(gym_type)
	return gym_slots[i] if i >= 0 and i < gym_slots.size() else null

# A house is a Challenge House: walking into the house itself opens the panel (_physics_process), and its
# door "opens" (a dark doorway) while the explorer is near it, like the gyms' doors.
func _add_house_node(house: Dictionary) -> void:
	if not house.has("type"):
		return
	var t: String = house["type"]
	var id: String = house["id"]
	var cleared := SessionManager.is_house_cleared(_topic_id, t, id)
	var stars := SessionManager.best_stars("house", _topic_id, "%s#%s" % [t, id])
	var state := "House %d · %s" % [house["num"], "★".repeat(stars) + "☆".repeat(3 - stars) if cleared else "Easy"]
	var box: AABB = house["box"]
	var area := house_scene.instantiate() as EncounterTrigger
	area.position = Vector3(box.get_center().x, 0.0, box.get_center().z)
	area.box = Vector3(box.size.x + house_margin * 2.0, box.size.y, box.size.z + house_margin * 2.0)
	trainers_root.add_child(area)
	area.label.visible = false
	var doorway := _add_doorway(area, house)
	area.body_entered.connect(func(_b: Node3D) -> void: _open_doorway(doorway, true))
	area.body_exited.connect(func(_b: Node3D) -> void:
		_open_doorway(doorway, false)
		if _dismissed_house == id:
			_dismissed_house = "")
	var quest := "cleared" if cleared else ("next" if _next_house() == house else "locked")
	area.set_meta("house_state", quest)
	_add_house_badge(area, t, state, quest)
	if cleared:
		area.dim()

# The inside of the door (house_trigger.tscn's Doorway): a dark panel just in front of it, sized to
# this house's door and folded shut (zero width) until opened.
func _add_doorway(area: Node3D, house: Dictionary) -> MeshInstance3D:
	var doorway := area.get_node("Doorway") as MeshInstance3D
	var quad := doorway.mesh.duplicate() as QuadMesh
	quad.size = house["door_size"]
	doorway.mesh = quad
	var facing: Vector3 = house["facing"]
	doorway.position = (house["door"] as Vector3) - area.position + facing * 0.02
	doorway.basis = Basis.looking_at(-facing)
	doorway.scale = Vector3(0.01, 1, 1)
	return doorway

func _open_doorway(doorway: MeshInstance3D, open: bool) -> void:
	doorway.visible = true
	var t := doorway.create_tween()
	t.tween_property(doorway, "scale:x", 1.0 if open else 0.01, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not open:
		t.tween_callback(doorway.hide)

# The badge over the roof (house_trigger.tscn's Badge, drawn by its BadgeView): a circle in the type's
# colour from afar, opening into a pill with the type and "Easy" or the stars near the explorer. Faint
# once the house is cleared, bobbing.
func _add_house_badge(area: EncounterTrigger, t: String, state: String, quest: String) -> void:
	var view := area.get_node("BadgeView") as SubViewport
	var chip := view.get_node("Pill/Row/Chip") as PanelContainer
	var style := chip.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = TYPE_COLORS.get(t, Palette.TEAL)
	chip.add_theme_stylebox_override("panel", style)
	(view.get_node("Pill/Row/Text/Lines/Name") as Label).text = _type_name(t)
	(view.get_node("Pill/Row/Text/Lines/Tier") as Label).text = state
	var badge := area.get_node("Badge") as Sprite3D
	badge.texture = view.get_texture()
	badge.modulate.a = {"next": 1.0, "cleared": 0.55}.get(quest, 0.35)
	_show_badge_text(area, quest == "next")
	badge.position = Vector3(0, HOUSE_LABEL_HEIGHT - 0.3, 0)
	var tw := badge.create_tween().set_loops()
	tw.tween_property(badge, "position:y", HOUSE_LABEL_HEIGHT - 0.15, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(badge, "position:y", HOUSE_LABEL_HEIGHT - 0.3, 0.7).set_trans(Tween.TRANS_SINE)

# Opens or closes a house badge's text, then redraws its BadgeView once at the new size.
func _show_badge_text(area: Node, shown: bool) -> void:
	var view := area.get_node("BadgeView") as SubViewport
	var text := view.get_node("Pill/Row/Text") as Control
	if text.visible == shown and view.has_meta("drawn"):
		return
	view.set_meta("drawn", true)
	text.visible = shown
	var pill := view.get_node("Pill") as Control
	pill.reset_size()
	view.size = Vector2i(pill.get_combined_minimum_size().ceil())
	view.render_target_update_mode = SubViewport.UPDATE_ONCE

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

# The next house's badge always shows its text; a cleared one only near the explorer; a locked one never.
func _process(_delta: float) -> void:
	for area: Node in trainers_root.get_children():
		if area is EncounterTrigger and not area.is_queued_for_deletion():
			var quest := str(area.get_meta("house_state", ""))
			var near := player.global_position.distance_to((area as Node3D).global_position) < house_label_near
			_show_badge_text(area, quest == "next" or (quest == "cleared" and near))

# Fast travel: the island map's tap, checked here, confirmed and paid before the explorer moves.
func _reset_travel_hint() -> void:
	travel_hint.text = "Tap a road or field to travel there for %d crystals." % GameState.TRAVEL_PRICE

func _on_travel_picked(at: Vector3) -> void:
	var spot := _travel_spot(at)
	if spot == Vector3.INF:
		travel_hint.text = "Can't land there. Pick a road, path or field."
	elif GameState.crystals < GameState.TRAVEL_PRICE:
		travel_hint.text = "Travel costs %d crystals. You have %d." % [GameState.TRAVEL_PRICE, GameState.crystals]
	else:
		_reset_travel_hint()
		ConfirmModal.open(back_btn.get_parent(), "Travel here?", "You and Kuiz hop to the pin for %d crystals. You have %d." % [GameState.TRAVEL_PRICE, GameState.crystals], "Travel", _travel_to.bind(spot), false, "Stay")

func _travel_to(spot: Vector3) -> void:
	if GameState.crystals < GameState.TRAVEL_PRICE:
		return
	GameState.add_crystals(-GameState.TRAVEL_PRICE)
	SaveManager.save_progress()
	await minimap.close()
	# Vanish in a burst while the screen dims, land, then pop back in with a second burst.
	player.locked = true
	_spawn_gym_burst(player.global_position)
	var out := create_tween().set_parallel()
	out.tween_property(player.model, "scale", Vector3.ONE * 0.01, TRAVEL_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	out.tween_property(kuiz, "scale", Vector3.ONE * 0.01, TRAVEL_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	out.tween_property(_fade, "color:a", 0.85, TRAVEL_SEC)
	await out.finished
	player.global_position = spot
	kuiz.place_behind()
	_spawn_gym_burst(spot)
	var back := create_tween().set_parallel()
	back.tween_property(_fade, "color:a", 0.0, TRAVEL_SEC * 1.4).set_trans(Tween.TRANS_SINE)
	back.tween_property(player.model, "scale", Vector3.ONE, TRAVEL_SEC * 1.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	back.tween_property(kuiz, "scale", Vector3.ONE, TRAVEL_SEC * 1.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	await back.finished
	player.locked = false

# The ground under `at` when the explorer can stand there: an outdoor ground mesh above the water, not
# in a house, with no tree, wall or lamp post in the way. Vector3.INF otherwise.
func _travel_spot(at: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 100.0, at.z), Vector3(at.x, -10.0, at.z), PlayerScript.GROUND_LAYER))
	if hit.is_empty() or hit.position.y < PlayerScript.WATERLINE:
		return Vector3.INF
	var ground := String((hit.collider as Node).get_parent().name)
	if not Array(travel_ground_keywords).any(func(k: String) -> bool: return ground.contains(k)):
		return Vector3.INF
	for house in _houses:
		var box: AABB = (house["box"] as AABB).grow(house_margin)
		if at.x > box.position.x and at.x < box.end.x and at.z > box.position.z and at.z < box.end.z:
			return Vector3.INF
	var probe := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.45
	probe.shape = ball
	probe.transform = Transform3D(Basis(), hit.position + Vector3.UP * 0.6)
	probe.collision_mask = OBSTACLE_LAYER
	return hit.position if space.intersect_shape(probe, 1).is_empty() else Vector3.INF

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
	var area := house_scene.instantiate() as EncounterTrigger
	area.position = pos
	area.radius = radius
	area.text = text
	return area

# A one-shot burst where a gym was just cleared; it frees itself.
func _spawn_gym_burst(pos: Vector3) -> void:
	if burst_scene == null:
		return
	var p := burst_scene.instantiate() as CPUParticles3D
	p.position = pos + Vector3.UP * 0.5
	add_child(p)
	p.finished.connect(p.queue_free)

# Fills the pop-up: a title and tag, the run's facts for a `kind` that can be played now, and one short note.
func _fill_encounter(title: String, tag: String, note: String, action: String, can_go: bool, kind := "", gym_type := "") -> void:
	encounter_title.text = title
	%EncounterTag.text = tag
	%EncounterTag.visible = tag != ""
	var notes: Array[String] = []
	if note != "":
		notes.append(note)
	%EncounterFacts.visible = kind != ""
	%EncounterReady.visible = kind != ""
	if kind != "":
		var items := SessionManager.run_items(_topic_id, kind, gym_type)
		var ready := roundi(CompanionState.readiness())
		%FactItems.text = str(items)
		%FactLevel.text = str(SessionManager.RUN_TIER[kind]).capitalize()
		%FactMinutes.text = "%d+" % SessionManager.RUN_MINUTES[kind]
		%ReadyValue.text = "%d%%" % ready
		%ReadyBar.value = ready
		%ReadyName.text = "Kuiz readiness (low: feed and rest it)" if ready < 25 else "Kuiz readiness"
	encounter_question.text = "\n".join(notes)
	encounter_question.visible = not notes.is_empty()
	encounter_clear_btn.text = action
	encounter_clear_btn.disabled = false
	encounter_clear_btn.visible = can_go
	_show_encounter(true)

func _on_house_touched(house: Dictionary) -> void:
	var t: String = house["type"]
	var id: String = house["id"]
	var cleared := SessionManager.is_house_cleared(_topic_id, t, id)
	var next := _next_house()
	if not cleared and next != house:
		# No "kind": the panel only explains, and closing it still keeps this house shut until stepped away from.
		_pending_encounter = {"house": house}
		_fill_encounter("House %d" % house["num"], "Locked", "Clear House %d (%s) first. It's the green pin on your map." % [next["num"], _type_name(next["type"])], "", false)
		return
	_pending_encounter = {"kind": "house", "gym": t, "house": house}
	var stars := SessionManager.best_stars("house", _topic_id, "%s#%s" % [t, id])
	var note := "%d of %d %s houses cleared" % [SessionManager.houses_cleared(_topic_id, t), _houses_of(t), _type_name(t)]
	if cleared:
		note += ". Replays pay a quarter."
	elif not SessionManager.is_gym_open(_topic_id, t):
		note += ". Clear one to open the gym."
	_fill_encounter("House %d" % house["num"], _type_name(t) + ("  " + "★".repeat(stars) if cleared else ""), note, "Replay" if cleared else "Go inside", true, "house", t)

func _on_gym_touched(_body: Node3D, gym_type: String) -> void:
	_pending_encounter = {"kind": "gym", "gym": gym_type}
	var cleared := SessionManager.is_gym_cleared(_topic_id, gym_type)
	var type_name := _type_name(gym_type)
	if not SessionManager.is_gym_open(_topic_id, gym_type):
		_fill_encounter("%s Gym" % type_name, "Locked", "Clear any %s house first. Look for the icons over the roofs." % type_name, "", false)
		return
	_fill_encounter("%s Gym" % type_name, "Badge earned" if cleared else "", "Replays pay a quarter." if cleared else "", "Replay" if cleared else "Enter Gym", true, "gym", gym_type)

func _on_champion_touched(_body: Node3D) -> void:
	_pending_encounter = {}
	if not SessionManager.is_champion_available(_topic_id):
		_fill_encounter("Champion Gym", "Locked", "Earn every gym badge first.", "", false)
		return
	var crowned := SessionManager.is_champion_defeated(_topic_id)
	_pending_encounter = {"kind": "champion"}
	var have := SessionManager.get_gym_structure().map(func(g: Dictionary) -> String: return str(g["type"]))
	var order: Array[String] = []
	for seg: Array in SessionManager.RUN_QUOTAS["champion"]:
		if have.has(seg[0]):
			order.append(_type_name(seg[0]))
	_fill_encounter("Champion Gym", "Crowned" if crowned else "The toughest robot", "%s." % ", then ".join(order) + (" Replays pay a quarter." if crowned else ""), "Replay" if crowned else "Challenge Champion!", true, "champion")

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
	SessionManager.battle_explorer = player.explorer
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
	houses_value.text = "%d / %d" % [houses_done, _houses.size()]
	houses_bar.max_value = maxi(_houses.size(), 1)
	houses_bar.value = houses_done
	for c in gym_badges.get_children():
		if c != badge_template:
			gym_badges.remove_child(c)
			c.queue_free()
	for lit in badges:
		var badge := badge_template.duplicate() as TextureRect
		badge.visible = true
		badge.modulate.a = 1.0 if lit else 0.28
		gym_badges.add_child(badge)
	gyms_value.text = "%d / %d" % [gyms_done, gyms.size()]
	champion_icon.texture = icon_crown if champion_ready or crowned else icon_lock
	champion_value.text = "Crowned" if crowned else ("Ready!" if champion_ready else "Locked")
	quest_count.text = "%d / %d done" % [houses_done + gyms_done + (1 if crowned else 0), _houses.size() + gyms.size() + 1]
	_show_objectives(_objectives(gyms, _houses.size() - houses_done))

# Every step still to do, in order: the next house on the route (the green pin), then each open gym,
# then the Champion. A gym opens with the first house of its type the route reaches.
func _objectives(gyms: Array[Dictionary], houses_left: int) -> Array[String]:
	var steps: Array[String] = []
	if SessionManager.is_champion_defeated(_topic_id):
		steps.append("Region complete! You are the Champion.")
	var next := _next_house()
	if not next.is_empty():
		steps.append("Clear House %d (%s), the green pin" % [next["num"], _type_name(next["type"])])
	if not SessionManager.is_champion_defeated(_topic_id):
		for g in gyms:
			var t: String = str(g["type"])
			if SessionManager.is_gym_open(_topic_id, t) and not SessionManager.is_gym_cleared(_topic_id, t):
				steps.append("Clear the %s Gym" % _type_name(t))
		if SessionManager.is_champion_available(_topic_id):
			steps.append("Challenge the Champion Gym")
		elif not gyms.is_empty():
			steps.append("Win every gym badge to open the Champion")
	if houses_left > 1:
		steps.append("%d houses left on the route" % houses_left)
	return steps

# Fills the step rows placed in %Objectives (their look is set in the scene); as many steps show as
# there are rows.
func _show_objectives(steps: Array[String]) -> void:
	var rows := objectives.get_children()
	for i in rows.size():
		rows[i].visible = i < steps.size()
		if i < steps.size():
			(rows[i].get_node("Text") as Label).text = steps[i]

# Asks first. The pop-up goes on the HUD's layer, so it covers the HUD.
func _on_back() -> void:
	var was_locked: bool = player.locked
	player.locked = true
	var modal := ConfirmModal.open(back_btn.get_parent(), "Go home?", "Head back to the house with Kuiz? Your progress is saved.", "Go home", _go_home, false, "Stay")
	modal.tree_exited.connect(func() -> void: player.locked = was_locked or _leaving)

func _go_home() -> void:
	SessionManager.kuiz_going_home = true
	_leave("res://scenes/overworld/world_intro.tscn")

func _on_study() -> void:
	SessionManager.flashcards_return = "res://scenes/overworld/region_map.tscn"
	_leave("res://scenes/review_session/flashcards.tscn")

# Fades to %Fade's colour, then changes scene: stepping through a door feels like going in.
func _leave(scene: String) -> void:
	_leaving = true
	player.locked = true
	var t := _fade.create_tween()
	t.tween_property(_fade, "color:a", 1.0, FADE_SEC)
	await t.finished
	# The engine draws one empty frame between scenes, and holds it while the next one loads.
	RenderingServer.set_default_clear_color(Color(_fade.color, 1.0))
	get_tree().change_scene_to_file(scene)
