extends Node
## Local JSON persistence for CompanionState + GameState, on this device only (no accounts).
## The format is versioned via "v".

const SAVE_PATH := "user://studymon_save.json"
## The schema written by save_game(); history in docs/data-model.md.
const SAVE_VERSION := 15
# An exported save is a few KB; anything far bigger is not one.
const MAX_IMPORT_BYTES := 5 * 1024 * 1024

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
	data["v"] = SAVE_VERSION
	data["active_region_id"] = GameState.active_region_id
	data["large_text_enabled"] = GameState.large_text_enabled
	data["player_name"] = GameState.player_name
	data["tutorial_done"] = GameState.tutorial_done
	data["ai_consent"] = GameState.ai_consent
	data["food_stock"] = GameState.food_stock
	data["crystals"] = GameState.crystals
	data["world_slots"] = GameState.world_slots
	data["study_streak"] = GameState.study_streak
	data["study_goal_day"] = GameState.study_goal_day
	data["study_cards_day"] = GameState.study_cards_day
	data["study_cards"] = GameState.study_cards
	data["owned_costumes"] = GameState.owned_costumes
	data["minigame_day"] = GameState.minigame_day
	data["minigame_crystals"] = GameState.minigame_crystals
	data["outfit"] = GameState.outfit
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

## Settings' "Delete my data": removes the save file and puts every saved value back to a fresh game.
func delete_all() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_reset()

# Every saved value back to a fresh game; the file itself is left alone.
func _reset() -> void:
	CompanionState.from_dict({})
	SessionManager.from_dict({})
	SessionManager.pending_questions = []
	SessionManager.editing_topic_id = ""
	SessionManager.current_topic_id = ""
	GameState.player_name = ""
	GameState.tutorial_done = false
	GameState.ai_consent = false
	GameState.food_stock = {}
	GameState.outfit = {}
	GameState.active_region_id = ""
	GameState.add_crystals(-GameState.crystals)
	GameState.world_slots = GameState.FREE_WORLD_SLOTS
	GameState.minigame_day = ""
	GameState.minigame_crystals = 0
	GameState.study_streak = 0
	GameState.study_goal_day = ""
	GameState.study_cards_day = ""
	GameState.study_cards = 0
	GameState.owned_costumes.clear()

## Settings' Export: the current save, written to `path` (a file the player picked). Saves stay on the
## device only, so this is how a player keeps a copy. False when it cannot be written.
func export_to(path: String) -> bool:
	if not save_game():
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(FileAccess.get_file_as_string(SAVE_PATH))
	f.close()
	return true

## Settings' Import: replaces the save with the Studymon save at `path` and loads it. Returns "" on
## success, else why it was refused; a refused file leaves the current save untouched.
func import_from(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "That file could not be opened."
	if f.get_length() > MAX_IMPORT_BYTES:
		return "That file is too big to be a Studymon save."
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("v") or not (parsed as Dictionary).has("level"):
		return "That file is not a Studymon save."
	if int(parsed["v"]) > SAVE_VERSION:
		return "That save comes from a newer version of Studymon. Update the app first."
	var out := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if out == null:
		return "The save could not be written."
	out.store_string(text)
	out.close()
	# A fresh game first, so keys the file lacks take their defaults.
	_reset()
	load_game()
	return ""

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
	# Saves before v15 also hold "campaign_ready" / "campaign_unlocked_flag" (the removed Level 5
	# gate); they are ignored.
	GameState.active_region_id = str(parsed.get("active_region_id", ""))
	GameState.player_name = str(parsed.get("player_name", ""))
	# Saves from before v15 lack the flag; a saved name means the tutorial was already played.
	GameState.tutorial_done = bool(parsed.get("tutorial_done", GameState.player_name != ""))
	GameState.ai_consent = bool(parsed.get("ai_consent", false))
	var stock: Variant = parsed.get("food_stock", {})
	if typeof(stock) == TYPE_DICTIONARY:
		for id in stock:
			GameState.food_stock[str(id)] = int(stock[id])
	GameState.crystals = maxi(0, int(parsed.get("crystals", 0)))
	GameState.world_slots = maxi(GameState.FREE_WORLD_SLOTS, int(parsed.get("world_slots", GameState.FREE_WORLD_SLOTS)))
	GameState.minigame_day = str(parsed.get("minigame_day", ""))
	GameState.minigame_crystals = maxi(0, int(parsed.get("minigame_crystals", 0)))
	GameState.study_streak = maxi(0, int(parsed.get("study_streak", 0)))
	GameState.study_goal_day = str(parsed.get("study_goal_day", ""))
	GameState.study_cards_day = str(parsed.get("study_cards_day", ""))
	GameState.study_cards = maxi(0, int(parsed.get("study_cards", 0)))
	GameState.owned_costumes.clear()
	for id in parsed.get("owned_costumes", []):
		GameState.owned_costumes.append(str(id))
	GameState.crystals_changed.emit(GameState.crystals)
	# Saves before per-world explorers hold one global "explorer"; it is ignored (each world asks once).
	GameState.outfit = {}
	var outfit: Variant = parsed.get("outfit", {})
	if typeof(outfit) == TYPE_DICTIONARY:
		for slot in outfit:
			GameState.outfit[str(slot)] = str(outfit[slot])
	# v9 kept one costume; of those six only the glasses are a face item, the rest sit on the head.
	var costume := str(parsed.get("costume", ""))
	if costume != "":
		GameState.outfit["face" if costume == "glasses" else "head"] = costume
	# Saves from before the closet shop: whatever Kuiz already wears stays owned.
	for id in GameState.outfit.values():
		if not GameState.owned_costumes.has(str(id)):
			GameState.owned_costumes.append(str(id))
	if parsed.has("large_text_enabled"):
		GameState.large_text_enabled = bool(parsed["large_text_enabled"])
		GameState._apply_theme_font_size()
	MusicManager.set_music_volume(float(parsed.get("music_volume", 1.0)))
	MusicManager.set_sfx_volume(float(parsed.get("sfx_volume", 1.0)))
	SessionManager.from_dict(parsed.get("session", {}))
	# Saves before v12 also hold a "monetization" block (the removed weekly AI limit); it is ignored.
	return true
