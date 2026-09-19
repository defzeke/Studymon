extends Node
## Phase 2: Local JSON persistence for CompanionState + GameState.
## (Cloud save arrives with backend/auth; format is versioned via "v".)

const SAVE_PATH := "user://studymon_save.json"
func save_game() -> bool:
	var data := CompanionState.to_dict()
	data["v"] = 4
	data["campaign_unlocked_flag"] = GameState.campaign_unlocked_flag
	data["active_region_id"] = GameState.active_region_id
	data["large_text_enabled"] = GameState.large_text_enabled
	data["session"] = SessionManager.to_dict()
	var _ms := get_node_or_null("/root/MonetizationState")
	if _ms != null:
		data["monetization"] = _ms.to_dict()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write " + SAVE_PATH)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	CompanionState.from_dict(parsed)
	if CompanionState.campaign_ready:
		GameState.set_campaign_unlocked(true)
	GameState.active_region_id = str(parsed.get("active_region_id", ""))
	if parsed.has("large_text_enabled"):
		GameState.large_text_enabled = bool(parsed["large_text_enabled"])
		GameState._apply_theme_font_size()
	SessionManager.from_dict(parsed.get("session", {}))
	if parsed.has("monetization"):
		var _ms := get_node_or_null("/root/MonetizationState")
		if _ms != null:
			_ms.from_dict(parsed["monetization"] as Dictionary)
	return true

func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
