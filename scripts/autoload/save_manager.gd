extends Node
## Phase 0: Local JSON persistence (cloud login stubbed for later per GDD §3).

const SAVE_PATH := "user://studymon_save.json"

func save_game() -> bool:
	var gm := get_node("/root/GameManager")
	var data := {
		"level": gm.level,
		"xp": gm.xp,
		"energy": gm.energy,
		"focus": gm.focus,
		"mood": gm.mood,
		"campaign_unlocked": gm.campaign_unlocked,
		"codex_entries": gm.codex_entries,
	}
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
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var gm := get_node("/root/GameManager")
	gm.level = int(parsed.get("level", 1))
	gm.xp = int(parsed.get("xp", 0))
	gm.energy = float(parsed.get("energy", 80.0))
	gm.focus = float(parsed.get("focus", 70.0))
	gm.mood = float(parsed.get("mood", 75.0))
	gm.campaign_unlocked = bool(parsed.get("campaign_unlocked", false))
	gm.codex_entries.clear()
	for e in parsed.get("codex_entries", []):
		gm.codex_entries.append(str(e))
	gm.stats_changed.emit()
	gm.xp_changed.emit(gm.xp, gm.level)
	return true

func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
