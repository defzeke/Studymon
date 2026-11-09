extends Control
## Worlds hub: a card per saved world (Play, Cards; the rest behind its "more" button) and New World.
## A world is a topic; contract: docs/ui-and-assets.md §2 Worlds.

const INTRO_SCENE := "res://scenes/overworld/world_intro.tscn"
const BUILDER_SCENE := "res://scenes/review_session/categorizer.tscn"

@onready var list_box: VBoxContainer = %ListBox
@onready var empty_label: Label = %EmptyLabel
@onready var new_btn: Button = %NewButton
@onready var slots_label: Label = %SlotsLabel
@onready var back_btn: Button = %BackButton
@onready var card_template: PanelContainer = %CardTemplate
@onready var world_menu: Control = %WorldMenu

var _menu_topic := {}


func _ready() -> void:
	theme = load("res://assets/theme/app_theme.tres") as Theme
	# Loaded ahead so Play doesn't stall on Kuiz's model.
	ResourceLoader.load_threaded_request(INTRO_SCENE)
	GameState.tutorial_done = true  # only reachable from home, so Back must not replay the intro
	# Coming back from the region map, the route theme crossfades back to the home loop.
	MusicManager.play_main_room()
	new_btn.pressed.connect(_on_new_world)
	back_btn.pressed.connect(_on_back)
	world_menu.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			world_menu.hide())
	%MenuClose.pressed.connect(world_menu.hide)
	%MenuEdit.pressed.connect(func() -> void: _on_edit(_menu_topic))
	%MenuReset.pressed.connect(_ask_reset)
	%MenuDelete.pressed.connect(_ask_delete)
	SessionManager.topics_listed.connect(_on_topics_listed)
	SessionManager.list_topics()
	_on_topics_listed(SessionManager.get_topics_cache())

func _on_topics_listed(topics: Array[Dictionary]) -> void:
	for c in list_box.get_children():
		c.queue_free()
	empty_label.visible = topics.is_empty()
	slots_label.text = "%d of %d world slots  ·  Study streak %d" % [topics.size(), GameState.world_slots, GameState.current_streak()]
	%CrystalLabel.text = str(GameState.crystals)
	for t in topics:
		list_box.add_child(_make_card(t))

# The card's look and layout are %CardTemplate's; this fills one copy.
func _make_card(topic: Dictionary) -> Control:
	var id := str(topic.get("id", ""))
	var progress := SessionManager.topic_progress(id)
	var total := int(progress["questions"])
	var card := card_template.duplicate() as PanelContainer
	card.visible = true
	(card.get_node("Box/Head/Name") as Label).text = str(topic.get("name", id))
	(card.get_node("Box/Info") as Label).text = "%s  ·  %s  ·  %d of %d gyms" % [_count(total, "question"), _count(int(progress["houses"]), "house"), int(progress["gyms"]), int(progress["gyms_total"])]
	(card.get_node("Box/Gyms") as ProgressBar).value = float(progress["gyms"]) / maxi(1, int(progress["gyms_total"]))
	var play := card.get_node("Box/Actions/Play") as Button
	play.disabled = total == 0
	play.pressed.connect(_on_play_world.bind(topic))
	var cards := card.get_node("Box/Actions/Cards") as Button
	cards.disabled = total == 0
	cards.pressed.connect(_on_open_cards.bind(topic))
	(card.get_node("Box/Head/More") as Button).pressed.connect(_open_menu.bind(topic))
	return card

func _count(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]

func _open_menu(topic: Dictionary) -> void:
	_menu_topic = topic
	%MenuTitle.text = str(topic.get("name", ""))
	world_menu.show()

func _ask_reset() -> void:
	world_menu.hide()
	ConfirmModal.open(self, "Reset progress?", "\"%s\" loses its cleared houses, gyms, mastery and Champion. Your questions are kept." % %MenuTitle.text, "Reset", SessionManager.reset_topic_progress.bind(str(_menu_topic.get("id", ""))), true)

func _ask_delete() -> void:
	world_menu.hide()
	ConfirmModal.open(self, "Delete world?", "\"%s\" and all its progress will be removed. This cannot be undone." % %MenuTitle.text, "Delete", SessionManager.delete_topic.bind(str(_menu_topic.get("id", ""))), true)

func _load_topic(topic: Dictionary) -> void:
	var questions: Array[Dictionary] = []
	for q in topic.get("questions", []):
		if q is Dictionary:
			questions.append(q)
	SessionManager.set_editing_topic(str(topic.get("id", "")), questions)

func _on_play_world(topic: Dictionary) -> void:
	_load_topic(topic)
	SessionManager.current_topic_id = str(topic.get("id", ""))
	get_tree().change_scene_to_file(INTRO_SCENE)

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
