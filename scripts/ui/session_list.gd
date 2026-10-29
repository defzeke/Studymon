extends Control
## Worlds hub: the saved worlds (play, cards, edit, reset, delete) and a New World button into the builder.
## A world is a topic; contract: docs/ui-and-assets.md §2 Worlds.

const ConfirmModal := preload("res://scripts/ui/widgets/confirm_modal.gd")
const REGION_SCENE := "res://scenes/overworld/region_map.tscn"
const BUILDER_SCENE := "res://scenes/review_session/categorizer.tscn"

@onready var list_box: VBoxContainer = %ListBox
@onready var empty_label: Label = %EmptyLabel
@onready var new_btn: Button = %NewButton
@onready var slots_label: Label = %SlotsLabel
@onready var back_btn: Button = %BackButton


func _ready() -> void:
	theme = load("res://assets/theme/app_theme.tres") as Theme
	GameState.tutorial_done = true  # only reachable from home, so Back must not replay the intro
	# Coming back from the region map, the route theme crossfades back to the home loop.
	MusicManager.play_main_room()
	# The next region map visit starts by picking the explorer again.
	GameState.explorer_picked = false
	new_btn.pressed.connect(_on_new_world)
	back_btn.pressed.connect(_on_back)
	SessionManager.topics_listed.connect(_on_topics_listed)
	SessionManager.list_topics()
	_on_topics_listed(SessionManager.get_topics_cache())

func _on_topics_listed(topics: Array[Dictionary]) -> void:
	for c in list_box.get_children():
		c.queue_free()
	empty_label.visible = topics.is_empty()
	slots_label.text = "Worlds %d / %d slots  ·  %d crystals  ·  Study streak %d" % [topics.size(), GameState.world_slots, GameState.crystals, GameState.current_streak()]
	for t in topics:
		list_box.add_child(_make_card(t))

func _make_card(topic: Dictionary) -> Control:
	var id := str(topic.get("id", ""))
	var progress := SessionManager.topic_progress(id)
	var total := int(progress["questions"])
	var card := PanelContainer.new()
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	pad.add_child(box)
	var name_label := Label.new()
	name_label.text = str(topic.get("name", id))
	name_label.clip_text = true
	name_label.add_theme_font_override("font", theme.get_font("font", "Button"))
	name_label.add_theme_color_override("font_color", Color("D6A85F"))
	box.add_child(name_label)
	var info := Label.new()
	info.text = "%d questions · %d houses · %d/%d gyms cleared" % [total, int(progress["houses"]), int(progress["gyms"]), int(progress["gyms_total"])]
	info.modulate = Color("E8F0EA", 0.75)
	info.add_theme_font_size_override("font_size", 22)
	box.add_child(info)
	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 8)
	box.add_child(main_row)
	var play := _button("Play", main_row, _on_play_world.bind(topic), total == 0)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button("Cards", main_row, _on_open_cards.bind(topic), total == 0)
	_button("Edit", main_row, _on_edit.bind(topic))
	var danger_row := HBoxContainer.new()
	danger_row.add_theme_constant_override("separation", 8)
	box.add_child(danger_row)
	var reset := _button("Reset progress", danger_row, _ask.bind("Reset progress?", "\"%s\" loses its cleared houses, gyms, mastery and Champion. Your questions are kept." % name_label.text, "Reset", SessionManager.reset_topic_progress.bind(id)))
	var delete := _button("Delete", danger_row, _ask.bind("Delete world?", "\"%s\" and all its progress will be removed. This cannot be undone." % name_label.text, "Delete", SessionManager.delete_topic.bind(id)))
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ConfirmModal.tint_danger(delete)
	return card

func _button(text: String, parent: Control, on_pressed: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.disabled = disabled
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


func _ask(title: String, message: String, confirm_text: String, action: Callable) -> void:
	ConfirmModal.open(self, title, message, confirm_text, action, true)

func _load_topic(topic: Dictionary) -> void:
	var questions: Array[Dictionary] = []
	for q in topic.get("questions", []):
		if q is Dictionary:
			questions.append(q)
	SessionManager.set_editing_topic(str(topic.get("id", "")), questions)

func _on_play_world(topic: Dictionary) -> void:
	_load_topic(topic)
	var id := str(topic.get("id", ""))
	SessionManager.current_topic_id = id
	GameState.set_active_region(id)
	get_tree().change_scene_to_file(REGION_SCENE)

func _on_edit(topic: Dictionary) -> void:
	_load_topic(topic)
	get_tree().change_scene_to_file(BUILDER_SCENE)

func _on_open_cards(topic: Dictionary) -> void:
	_load_topic(topic)
	SessionManager.current_topic_id = str(topic.get("id", ""))
	SessionManager.flashcards_return = "res://scenes/ui/session_list.tscn"
	get_tree().change_scene_to_file("res://scenes/review_session/flashcards.tscn")

# Every world needs a slot: with all of them in use, offer one for crystals (contract:
# docs/systems/monetization.md).
func _on_new_world() -> void:
	if not SessionManager.has_free_world_slot():
		var title := "All %d world slots are full" % GameState.world_slots
		if GameState.crystals >= GameState.WORLD_SLOT_PRICE:
			ConfirmModal.open(self, title, "Buy one more slot for %d crystals? You have %d. A slot you buy is yours to keep, even after deleting a world." % [GameState.WORLD_SLOT_PRICE, GameState.crystals], "Buy slot", _buy_slot, false, "Not now")
		else:
			ConfirmModal.open(self, title, "One more slot costs %d crystals, and you have %d. Earn crystals by clearing houses, gyms and the Champion, or in the Playroom minigames. Or delete a world to free its slot." % [GameState.WORLD_SLOT_PRICE, GameState.crystals], "OK", Callable(), false, "")
		return
	_open_builder()

func _buy_slot() -> void:
	if GameState.buy_world_slot():
		SaveManager.save_progress()
		_open_builder()

func _open_builder() -> void:
	SessionManager.pending_questions.clear()
	SessionManager.last_source_text = ""
	SessionManager.editing_topic_id = "topic_%d" % (int(Time.get_unix_time_from_system()) % 100000)
	get_tree().change_scene_to_file(BUILDER_SCENE)

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/boot/peek.tscn")
