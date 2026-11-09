extends Node
## Copies the save to the player's Google Play Games Saved Games (a snapshot in their Google Drive app
## folder) and brings it back on a new phone. The file on the device stays the source of truth, and
## offline play is unchanged. Android only: elsewhere (the editor, the headless gates, desktop) nothing
## here runs. Contract: docs/data-model.md §8.

## Signed in or out of Google Play Games; `player_name` is the profile's display name.
signal account_changed(signed_in: bool, player_name: String)
## The cloud copy is newer than this phone's progress: home asks which one to keep (offer_choice()).
signal choice_ready

## The snapshot's name in Saved Games.
const SNAPSHOT := "studymon"
## At most one upload this often; app pause and close upload at once.
const UPLOAD_GAP := 60.0
## Saved Games holds 3 MB per snapshot. Above this the copy drops each world's reviewer text (only
## "More questions" uses it, and the phone keeps it).
const MAX_BYTES := 2_500_000
const HOME_SCENE := "res://scenes/ui/boot/peek.tscn"

var signed_in := false
var player_name := ""
var _active := false
## Uploads wait until the cloud copy has been compared with this phone's, so a fresh install never
## overwrites a player's progress before it is restored.
var _compared := false
var _upload_due := false
var _last_upload := -UPLOAD_GAP
## A newer cloud save waiting for the player's answer (its JSON text), and whether the question is open
## (uploads wait for the answer).
var _offered := ""
var _choosing := false
var _deleting := false

@onready var _sign_in: PlayGamesSignInClient = $SignIn
@onready var _snapshots: PlayGamesSnapshotsClient = $Snapshots
@onready var _players: PlayGamesPlayersClient = $Players

# Before the client nodes' _ready, which connect to the plugin only if it is initialised.
func _enter_tree() -> void:
	_active = OS.get_name() == "Android" and Engine.has_singleton("GodotPlayGameServices") \
		and GodotPlayGameServices.initialize() == GodotPlayGameServices.PlayGamesPluginError.OK

func _ready() -> void:
	if not _active:
		return
	_sign_in.user_authenticated.connect(_on_authenticated)
	_players.current_player_loaded.connect(func(p: PlayGamesPlayer) -> void:
		player_name = p.display_name if p else ""
		account_changed.emit(signed_in, player_name))
	_snapshots.game_loaded.connect(_on_game_loaded)
	_snapshots.conflict_emitted.connect(_on_conflict)
	_snapshots.snapshots_loaded.connect(_on_snapshots_loaded)
	_sign_in.is_authenticated()

## True on Android with the Play Games plugin present: the only place cloud saves exist.
func is_available() -> bool:
	return _active

## Settings' Sign in button: the Play Games sign-in flow.
func sign_in() -> void:
	if _active:
		_sign_in.sign_in()

## SaveManager wrote the save: upload it soon (at most once per UPLOAD_GAP).
func note_saved() -> void:
	_upload_due = true

func _process(_delta: float) -> void:
	if _upload_due and not _choosing and _now() - _last_upload >= UPLOAD_GAP:
		_upload()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _upload_due and not _choosing:
			_upload()
	# A load that failed (no network) sends nothing, so try again when the player comes back.
	elif what == NOTIFICATION_APPLICATION_RESUMED and _active and signed_in and not _compared:
		_snapshots.load_game(SNAPSHOT, false)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _on_authenticated(ok: bool) -> void:
	signed_in = ok
	account_changed.emit(ok, player_name)
	if not ok:
		return
	_players.load_current_player(false)
	SaveManager.load_once()
	_snapshots.load_game(SNAPSHOT, false)

# The cloud copy arrived (null when there is none yet): keep whichever is newer.
func _on_game_loaded(snapshot: PlayGamesSnapshot) -> void:
	if _compared:
		return
	_compared = true
	var text := snapshot.content.get_string_from_utf8() if snapshot and not snapshot.content.is_empty() else ""
	var cloud_at := _saved_at(text)
	if text == "" or SaveManager.check(text) != "" or cloud_at <= SaveManager.saved_at:
		# None, unreadable or older: this phone's save is the one to keep.
		if GameState.tutorial_done:
			note_saved()
		return
	if not GameState.tutorial_done:
		# A new install: restore silently.
		_restore(text)
		return
	_offered = text
	choice_ready.emit()

## Home calls this once it is showing: if a newer cloud save is waiting, asks which one to keep.
func offer_choice(host: Node) -> void:
	if _offered == "":
		return
	var parsed: Dictionary = JSON.parse_string(_offered)
	var worlds: int = (parsed.get("session", {}) as Dictionary).get("topics", []).size()
	var modal := ConfirmModal.open(host, "Save found in your Google account",
		"It has Kuiz at Level %d and %d world%s, saved more recently than this phone. Use it? This phone's progress is replaced." % [
			int(parsed.get("level", 1)), worlds, "" if worlds == 1 else "s"],
		"Use it", _restore.bind(_offered), false, "Keep this phone's")
	_offered = ""
	_choosing = true
	# "Use it" runs _restore before the pop-up leaves the tree; anything else keeps this phone's
	# progress and uploads it, so the two copies agree again.
	modal.tree_exited.connect(func() -> void:
		if _choosing:
			_choosing = false
			note_saved())

func _restore(text: String) -> void:
	_choosing = false
	_upload_due = false
	if SaveManager.replace_with(text) != "":
		return
	if get_tree().current_scene and get_tree().current_scene.scene_file_path == HOME_SCENE:
		get_tree().change_scene_to_file(HOME_SCENE)

# Quietly 0 for no text or text that is not JSON (JSON.parse_string would log an error).
func _saved_at(text: String) -> int:
	var json := JSON.new()
	if text == "" or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return 0
	return int((json.data as Dictionary).get("saved_at", 0))

func _upload() -> void:
	_upload_due = false
	_last_upload = _now()
	if not (_active and signed_in and _compared and FileAccess.file_exists(SaveManager.SAVE_PATH)):
		return
	var text := FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		text = _without_reviewer_text(text)
	var worlds := SessionManager.get_topics_cache().size()
	# The progress value is the save time, so Play Games' "highest progress" rule keeps the newest copy.
	_snapshots.save_game(SNAPSHOT, "Kuiz Level %d · %d world%s" % [CompanionState.level, worlds, "" if worlds == 1 else "s"],
		text.to_utf8_buffer(), 0, SaveManager.saved_at)

func _without_reviewer_text(text: String) -> String:
	var parsed: Dictionary = JSON.parse_string(text)
	for t in (parsed.get("session", {}) as Dictionary).get("topics", []):
		if t is Dictionary:
			(t as Dictionary).erase("source_text")
	return JSON.stringify(parsed)

# Play Games could not settle two copies itself: keep the one saved last.
func _on_conflict(conflict: PlayGamesSnapshotConflict) -> void:
	var a := conflict.server_snapshot
	var b := conflict.conflicting_snapshot
	var pick := a if a and (not b or _saved_at(a.content.get_string_from_utf8()) >= _saved_at(b.content.get_string_from_utf8())) else b
	if pick == null:
		return
	if conflict.origin == "LOAD":
		_compared = false
		_on_game_loaded(pick)
	else:
		note_saved()

## Settings' "Delete my data": removes the cloud copy too.
func delete_cloud() -> void:
	_upload_due = false
	if not (_active and signed_in):
		return
	_deleting = true
	_snapshots.load_snapshots(true)

func _on_snapshots_loaded(snapshots: Array[PlayGamesSnapshotMetadata]) -> void:
	if not _deleting:
		return
	_deleting = false
	for s in snapshots:
		if s.unique_name == SNAPSHOT:
			_snapshots.delete_snapshot(s.snapshot_id)
