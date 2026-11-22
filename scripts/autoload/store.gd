extends Node
## Sells the Gold packs for real money through RevenueCat (the godotx_revenue_cat plugin, Android only).
## RevenueCat checks each Google Play receipt before it reports a purchase, and consumes it so a pack
## can be bought again. Elsewhere (the editor, desktop, the headless gates), or without a key, nothing
## here runs, and debug builds keep the free test top-up. Contract: docs/systems/monetization.md.

## A purchase ended. `ok` is true when its Gold was added. `message` is "" when the player cancelled.
signal purchase_finished(ok: bool, message: String)
## The store's own prices arrived (see `prices`).
signal prices_changed

# shortcut: paste RevenueCat's public Android SDK key (goog_...) once the project exists (docs/systems/monetization.md)
const ANDROID_KEY := ""

## The store's localized price per product id ("PHP 49.00"); empty until fetch_prices() answers.
var prices: Dictionary = {}
## The pack being bought, or null.
var pending: GoldPack
var _rc: Object
var _asked_prices := false

func _ready() -> void:
	if OS.get_name() != "Android" or ANDROID_KEY == "" or not Engine.has_singleton("GodotxRevenueCat"):
		return
	_rc = Engine.get_singleton("GodotxRevenueCat")
	_rc.connect("purchase_result", _on_purchase_result)
	_rc.connect("products", _on_products)
	# The app user id stays anonymous until Play Games sign-in gives a player id (docs/next-steps.md Phase 2).
	_rc.initialize(ANDROID_KEY, "", OS.is_debug_build())

## True when real purchases work on this device.
func is_live() -> bool:
	return _rc != null

## Asks the store for the packs' prices once; `prices_changed` fires when they arrive.
func fetch_prices(packs: Array[GoldPack]) -> void:
	if _rc == null or _asked_prices:
		return
	_asked_prices = true
	var ids := PackedStringArray()
	for pack in packs:
		ids.append(pack.product_id)
	_rc.fetch_products(ids)

## Buys `pack`. Live: Google's payment sheet, and the Gold arrives with purchase_finished. Otherwise
## (debug builds only) the free test top-up adds it at once.
func buy(pack: GoldPack) -> void:
	if pending != null:
		return
	if _rc == null:
		if OS.is_debug_build():
			_grant(pack)
		return
	pending = pack
	_rc.purchase(pack.product_id)

func _on_purchase_result(data: Dictionary) -> void:
	var pack := pending
	pending = null
	if pack == null or str(data.get("product_id", "")) != pack.product_id:
		push_warning("Store: a purchase result for %s with no matching pack" % data.get("product_id", ""))
		return
	var error := str(data.get("error", ""))
	if error == "":
		_grant(pack)
	elif data.get("cancelled", false):
		purchase_finished.emit(false, "")
	else:
		purchase_finished.emit(false, "The purchase did not go through: %s" % error)

func _on_products(data: Dictionary) -> void:
	var products: Variant = data.get("products", [])
	if not products is Array:
		return
	for p: Variant in products:
		if p is Dictionary:
			# The font has no peso sign.
			prices[str(p.get("id", ""))] = str(p.get("price", "")).replace("₱", "PHP ")
	prices_changed.emit()

# Paid Gold is written at once, not on the save debounce, so closing the app cannot lose it.
func _grant(pack: GoldPack) -> void:
	GameState.add_gold(pack.gold)
	SaveManager.save_game()
	purchase_finished.emit(true, "")
