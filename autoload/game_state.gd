extends Node
## GameState — global run-time state (canonical; superset of Phase 0 + Phase 1 needs).
## Companion stats live in CompanionState; topics in SessionManager.

signal campaign_unlocked_changed(unlocked: bool)
signal campaign_unlocked
signal active_region_changed(region_id: String)

var user_id: String = ""
var auth_token: String = ""
var campaign_unlocked_flag: bool = false
var active_region_id: String = ""
var current_topic_id: String = ""

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
