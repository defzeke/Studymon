class_name TopUp
extends Control
## The shop behind the crystal pill: top up Gold for pesos, and trade Gold for crystals. TopUp.open(host).
## The packs and bundles are data (assets/data/gold_packs/, assets/data/crystal_bundles/) listed on this
## scene's root; each row is a copy of a hidden template. Contract: docs/systems/monetization.md.

const SCENE := "res://scenes/ui/widgets/top_up.tscn"

@export var packs: Array[GoldPack] = []
@export var bundles: Array[CrystalBundle] = []

@onready var _dim: ColorRect = %Dim
@onready var _card: PanelContainer = %Card
var _closing := false

# shortcut: only debug builds have the shop, and their top-ups add Gold without payment; wire Google Play Billing (docs/systems/monetization.md) before release
## Release builds hide the shop: a purchase screen that cannot pay is a store rejection.
static func available() -> bool:
	return OS.is_debug_build()

## Shows the shop over `host` (a screen's top layer).
static func open(host: Node) -> Control:
	var shop: TopUp = (load(SCENE) as PackedScene).instantiate()
	host.add_child(shop)
	return shop

func _ready() -> void:
	for pack in packs:
		var row := %PackTemplate.duplicate() as PanelContainer
		row.show()
		(row.get_node("Row/Amount") as Label).text = "%d Gold" % pack.gold
		var buy := row.get_node("Row/Buy") as Button
		buy.text = "PHP %d" % pack.pesos
		buy.pressed.connect(_ask_top_up.bind(pack))
		%Packs.add_child(row)
	for bundle in bundles:
		var row := %BundleTemplate.duplicate() as PanelContainer
		row.show()
		row.set_meta("bundle", bundle)
		(row.get_node("Row/Amount") as Label).text = "%d crystals" % bundle.crystals
		var buy := row.get_node("Row/Buy") as Button
		buy.text = str(bundle.gold)
		buy.pressed.connect(_exchange.bind(bundle))
		%Bundles.add_child(row)
	%Close.pressed.connect(_close)
	%Dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close())
	GameState.gold_changed.connect(_refresh.unbind(1))
	GameState.crystals_changed.connect(_refresh.unbind(1))
	_refresh()
	%Close.grab_focus()
	_card.modulate.a = 0.0
	_card.scale = Vector2.ONE * 0.85
	_pop_in.call_deferred()

func _refresh() -> void:
	%GoldLabel.text = str(GameState.gold)
	%CrystalLabel.text = str(GameState.crystals)
	for row in %Bundles.get_children():
		if row.has_meta("bundle"):
			(row.get_node("Row/Buy") as Button).disabled = GameState.gold < (row.get_meta("bundle") as CrystalBundle).gold

func _ask_top_up(pack: GoldPack) -> void:
	ConfirmModal.open(self, "Test top-up", "Add %d Gold for PHP %d? This is a test: no money is charged." % [pack.gold, pack.pesos], "Add Gold", _top_up.bind(pack), false, "Cancel")

func _top_up(pack: GoldPack) -> void:
	GameState.add_gold(pack.gold)
	SaveManager.save_progress()

func _exchange(bundle: CrystalBundle) -> void:
	if GameState.buy_crystals(bundle):
		SaveManager.save_progress()

func _pop_in() -> void:
	_card.pivot_offset = _card.size / 2.0
	var t := create_tween().set_parallel()
	t.tween_property(_dim, "color:a", 0.72, 0.18)
	t.tween_property(_card, "modulate:a", 1.0, 0.18)
	t.tween_property(_card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _close() -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween().set_parallel()
	t.tween_property(_dim, "color:a", 0.0, 0.14)
	t.tween_property(_card, "modulate:a", 0.0, 0.14)
	await t.finished
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
