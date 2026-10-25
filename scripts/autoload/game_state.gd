extends Node
## GameState — global run-time state (canonical; superset of Phase 0 + Phase 1 needs).
## Companion stats live in CompanionState; topics in SessionManager.

signal large_text_changed(enabled: bool)
signal crystals_changed(amount: int)

var user_id: String = ""
var auth_token: String = ""
# shortcut: memory only while there is no backend; save it with the profile once accounts exist.
var player_name: String = ""
# shortcut: memory only like the name; the tutorial replays each launch until it is saved with the profile.
var tutorial_done: bool = false
# shortcut: memory only until Kuiz's stats and the shop's currency exist; food id -> count.
var food_stock: Dictionary = {}
var campaign_unlocked_flag: bool = false
# Home's currency (top-right pill): minigame rounds earn it, a new battery spends it.
var crystals: int = 0
## What Kuiz wears: closet slot ("head", "face", "body") -> an id from kuiz_look.gd's COSTUMES; a
## missing slot is bare.
var outfit: Dictionary = {}
var active_region_id: String = ""

# --- Phase 9: Accessibility — font-size scaling hooked into app_theme.tres ---
# Standard = theme default (28 / 32), Large = scaled for readability.
const FONT_SIZE_STANDARD := 28
const FONT_SIZE_LARGE := 36
const BUTTON_FONT_STANDARD := 32
const BUTTON_FONT_LARGE := 40
var large_text_enabled: bool = false

func set_user(uid: String, token: String) -> void:
	user_id = uid
	auth_token = token

func add_crystals(amount: int) -> void:
	crystals = maxi(0, crystals + amount)
	crystals_changed.emit(crystals)

func set_campaign_unlocked(value: bool) -> void:
	if campaign_unlocked_flag == value:
		return
	campaign_unlocked_flag = value

func set_active_region(region_id: String) -> void:
	active_region_id = region_id

# --- Phase 9: large-text toggle — mutates loaded Theme instance in memory ---
func set_large_text(enabled: bool) -> void:
	if large_text_enabled == enabled:
		return
	large_text_enabled = enabled
	_apply_theme_font_size()
	large_text_changed.emit(enabled)

func _apply_theme_font_size() -> void:
	var theme_path := "res://assets/theme/app_theme.tres"
	if not ResourceLoader.exists(theme_path):
		return
	var theme: Theme = load(theme_path) as Theme
	if theme == null:
		return
	theme.default_font_size = FONT_SIZE_LARGE if large_text_enabled else FONT_SIZE_STANDARD
	theme.set_font_size("font_size", "Button", BUTTON_FONT_LARGE if large_text_enabled else BUTTON_FONT_STANDARD)
	# Propagate to already-instantiated tree: root theme override ensures inheritance.
	if get_tree() and get_tree().root:
		get_tree().root.theme = theme

func _ready() -> void:
	# Apply saved preference on boot (SaveManager loads before this in some flows, so defer one frame).
	call_deferred("_apply_theme_font_size")
