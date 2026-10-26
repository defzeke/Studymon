extends Node
## Phase 2: Local JSON persistence for CompanionState + GameState.
## (Cloud save arrives with backend/auth; format is versioned via "v".)

const SAVE_PATH := "user://studymon_save.json"

var _loaded := false

# Deferred so every autoload exists first. Loading at boot means the first scene already sees the
# saved name, tutorial flag and food, and a scene run on its own still cannot overwrite the save.
func _ready() -> void:
	load_once.call_deferred()

## Loads the save once per session; later calls keep the in-memory state (it may be newer).
func load_once() -> void:
	if not _loaded:
		_loaded = true
		load_game()

func save_game() -> bool:
	var data := CompanionState.to_dict()
	data["v"] = 14
	data["campaign_unlocked_flag"] = GameState.campaign_unlocked_flag
	data["active_region_id"] = GameState.active_region_id
	data["large_text_enabled"] = GameState.large_text_enabled
	data["player_name"] = GameState.player_name
	data["food_stock"] = GameState.food_stock
	data["crystals"] = GameState.crystals
	data["outfit"] = GameState.outfit
	data["explorer"] = GameState.explorer
	data["music_volume"] = MusicManager.music_volume
	data["sfx_volume"] = MusicManager.sfx_volume
	data["session"] = SessionManager.to_dict()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write " + SAVE_PATH)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

## Progress saves never run before a load, so a scene run on its own cannot overwrite the real save.
func save_progress() -> void:
	if _loaded:
		save_game()

func load_game() -> bool:
	_loaded = true
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
	GameState.player_name = str(parsed.get("player_name", ""))
	var stock: Variant = parsed.get("food_stock", {})
	if typeof(stock) == TYPE_DICTIONARY:
		for id in stock:
			GameState.food_stock[str(id)] = int(stock[id])
	GameState.crystals = maxi(0, int(parsed.get("crystals", 0)))
	GameState.crystals_changed.emit(GameState.crystals)
	GameState.explorer = str(parsed.get("explorer", "boy"))
	GameState.outfit = {}
	var outfit: Variant = parsed.get("outfit", {})
	if typeof(outfit) == TYPE_DICTIONARY:
		for slot in outfit:
			GameState.outfit[str(slot)] = str(outfit[slot])
	# v9 kept one costume; of those six only the glasses are a face item, the rest sit on the head.
	var costume := str(parsed.get("costume", ""))
	if costume != "":
		GameState.outfit["face" if costume == "glasses" else "head"] = costume
	if parsed.has("large_text_enabled"):
		GameState.large_text_enabled = bool(parsed["large_text_enabled"])
		GameState._apply_theme_font_size()
	MusicManager.set_music_volume(float(parsed.get("music_volume", 1.0)))
	MusicManager.set_sfx_volume(float(parsed.get("sfx_volume", 1.0)))
	SessionManager.from_dict(parsed.get("session", {}))
	# Saves before v12 also hold a "monetization" block (the removed weekly AI limit); it is ignored.
	return true
