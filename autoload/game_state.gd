extends Node
## GameState — global run-time state (canonical; superset of Phase 0 + Phase 1 needs).
## Companion stats live in CompanionState; topics in SessionManager.

signal campaign_unlocked_changed(unlocked: bool)
signal campaign_unlocked
signal active_region_changed(region_id: String)
signal large_text_changed(enabled: bool)

var user_id: String = ""
var auth_token: String = ""
var campaign_unlocked_flag: bool = false
var active_region_id: String = ""
var current_topic_id: String = ""

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

func clear_session() -> void:
	user_id = ""
	auth_token = ""
	active_region_id = ""
	current_topic_id = ""

func set_campaign_unlocked(value: bool) -> void:
	if campaign_unlocked_flag == value:
		return
	campaign_unlocked_flag = value
	campaign_unlocked_changed.emit(value)
	if value:
		campaign_unlocked.emit()

func unlock_campaign() -> void:
	set_campaign_unlocked(true)

func set_active_region(region_id: String) -> void:
	active_region_id = region_id
	active_region_changed.emit(region_id)

# --- Phase 9: large-text toggle — mutates loaded Theme instance in memory ---
func set_large_text(enabled: bool) -> void:
	if large_text_enabled == enabled:
		return
	large_text_enabled = enabled
	_apply_theme_font_size()
	large_text_changed.emit(enabled)

func toggle_large_text() -> void:
	set_large_text(!large_text_enabled)

func is_large_text() -> bool:
	return large_text_enabled

func _apply_theme_font_size() -> void:
	var theme_path := "res://ui/app_theme.tres"
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
