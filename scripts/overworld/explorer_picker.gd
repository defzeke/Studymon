extends CanvasLayer
## "Choose your explorer": shown over the region map the first time a world is played (each world keeps its own). Each card is a live 3D preview
## of an explorer (its own small world, idling; the chosen one cheers). "Let's go!" emits `picked`
## with the id from player.gd's EXPLORERS. Layout lives in explorer_picker.tscn; one card per explorer
## is copied from %CardTemplate. Contract: docs/systems/overworld.md §3 Explorer.

signal picked(id: String)

const Player := preload("res://scripts/overworld/player.gd")
const NAMES := {"boy": "Boy", "girl": "Girl"}

## The chosen card's panel, and every other card's.
@export var card_selected: StyleBox
@export var card_normal: StyleBox

@onready var panel: PanelContainer = %Panel
@onready var cards: HBoxContainer = %Cards
@onready var card_template: PanelContainer = %CardTemplate

var _choice := ""
var _cards := {}
var _anims := {}

func _ready() -> void:
	_choice = "boy"
	for id: String in Player.EXPLORERS:
		cards.add_child(_card(id))
	%GoButton.pressed.connect(_go)
	_select(_choice)
	panel.modulate.a = 0.0
	panel.scale = Vector2.ONE * 0.92
	panel.pivot_offset = panel.get_combined_minimum_size() / 2.0
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "modulate:a", 1.0, 0.25)
	t.tween_property(panel, "scale", Vector2.ONE, 0.3)

func _card(id: String) -> Control:
	var card := card_template.duplicate() as PanelContainer
	card.visible = true
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select(id))
	var model: Node3D = Player.EXPLORERS[id].instantiate()
	model.rotation_degrees.y = -18.0
	card.get_node("Box/View/Viewport").add_child(model)
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
	anim.play("Idle")
	anim.animation_finished.connect(func(_c: StringName) -> void: anim.play("Idle", 0.2))
	_anims[id] = anim
	(card.get_node("Box/Name") as Label).text = NAMES.get(id, id.capitalize())
	_cards[id] = card
	return card

# The chosen card gets a thick teal border and cheers; the other is plain.
func _select(id: String) -> void:
	_choice = id
	for key: String in _cards:
		_cards[key].add_theme_stylebox_override("panel", card_selected if key == id else card_normal)
	if _anims[id].current_animation != "Celebrate":
		_anims[id].play("Celebrate", 0.2)

func _go() -> void:
	picked.emit(_choice)
	var t := create_tween()
	for c in get_children():
		if c is CanvasItem:
			t.parallel().tween_property(c, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)
