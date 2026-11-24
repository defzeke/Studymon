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

## The shop shows when real purchases work (Store), or in a debug build with the free test top-up. A
## release build without them hides it: a purchase screen that cannot pay is a store rejection.
static func available() -> bool:
	return Store.is_live() or OS.is_debug_build()

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
		row.set_meta("pack", pack)
		(row.get_node("Row/Buy") as Button).pressed.connect(_ask_top_up.bind(pack))
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
	Store.prices_changed.connect(_refresh)
	Store.purchase_finished.connect(_on_purchase_finished)
	Store.fetch_prices(packs)
	%Note.visible = not Store.is_live()
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
	for row in %Packs.get_children():
		if row.has_meta("pack"):
			var pack := row.get_meta("pack") as GoldPack
			var buy := row.get_node("Row/Buy") as Button
			buy.text = Store.prices.get(pack.product_id, "PHP %d" % pack.pesos)
			buy.disabled = Store.pending != null

# Live, Google's own payment sheet confirms; the free test top-up asks here first.
func _ask_top_up(pack: GoldPack) -> void:
	if Store.is_live():
		Store.buy(pack)
		_refresh()
	else:
		ConfirmModal.open(self, "Test top-up", "Add %d Gold for PHP %d? This is a test: no money is charged." % [pack.gold, pack.pesos], "Add Gold", Store.buy.bind(pack), false, "Cancel")

func _on_purchase_finished(_ok: bool, message: String) -> void:
	_refresh()
	if message != "":
		ConfirmModal.open(self, "Top-up", message, "OK", Callable(), false, "")

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
