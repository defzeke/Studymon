extends Node
## GameState — global run-time state (canonical; superset of Phase 0 + Phase 1 needs).
## Companion stats live in CompanionState; topics in SessionManager.

signal large_text_changed(enabled: bool)
signal crystals_changed(amount: int)

## Saved: the name the tutorial asks for.
var player_name: String = ""
## Saved: the tutorial plays once per install.
var tutorial_done: bool = false
## Saved: the player agreed to send reviewers and typed answers to the AI (asked before the first
## upload, withdrawn in Settings). Without it nothing is sent and essays are graded on the device.
var ai_consent := false
## What the consent pop-up and Settings say is sent (Apple 5.1.2(i)); keep it true to the backend.
const AI_CONSENT_TEXT := "To turn your reviewer into questions, Studymon sends the text or PDF you upload, and the essay answers you type in battles, to its study server, which passes them to Claude, an AI by Anthropic. They are used only to make and grade your questions, and Studymon does not keep them. Your worlds and progress stay on this device."
## Saved: food id -> count in stock.
var food_stock: Dictionary = {}
# Home's currency (top-right pill): battles, level-ups and minigames earn it; world slots and a new
# battery spend it. Contract: docs/systems/monetization.md.
var crystals: int = 0
## World slots: how many worlds the player can keep at once. Bought slots are permanent: deleting a
## world frees its slot, never refunds it. Saved.
const FREE_WORLD_SLOTS := 3
const WORLD_SLOT_PRICE := 300
var world_slots := FREE_WORLD_SLOTS
## Minigames pay at most this many crystals per local day, so studying stays the main income. Saved.
const MINIGAME_DAILY_CRYSTALS := 60
var minigame_day := ""
var minigame_crystals := 0
## What Kuiz wears: closet slot ("head", "face", "body") -> an id from kuiz_look.gd's COSTUMES; a
## missing slot is bare.
var outfit: Dictionary = {}
## The region map's explorer (player.gd EXPLORERS id), saved; `explorer_picked` (memory only) is
## set once it is chosen on a visit to the map and cleared when the worlds list opens again.
var explorer: String = "boy"
var explorer_picked := false
var active_region_id: String = ""

# --- Phase 9: Accessibility — font-size scaling hooked into app_theme.tres ---
# Standard = theme default (28 / 32), Large = scaled for readability.
const FONT_SIZE_STANDARD := 28
const FONT_SIZE_LARGE := 36
const BUTTON_FONT_STANDARD := 32
const BUTTON_FONT_LARGE := 40
var large_text_enabled: bool = false

func add_crystals(amount: int) -> void:
	crystals = maxi(0, crystals + amount)
	crystals_changed.emit(crystals)

## Spends WORLD_SLOT_PRICE crystals on one more world slot; false (nothing spent) without enough.
func buy_world_slot() -> bool:
	if crystals < WORLD_SLOT_PRICE:
		return false
	add_crystals(-WORLD_SLOT_PRICE)
	world_slots += 1
	return true

## Pays a minigame round's crystals up to today's MINIGAME_DAILY_CRYSTALS; returns what was paid.
func pay_minigame(amount: int) -> int:
	var today := Time.get_date_string_from_system()
	if today != minigame_day:
		minigame_day = today
		minigame_crystals = 0
	var paid := clampi(amount, 0, MINIGAME_DAILY_CRYSTALS - minigame_crystals)
	minigame_crystals += paid
	add_crystals(paid)
	return paid

## The daily study goal: finish one battle run, or rate STUDY_GOAL_CARDS flashcards, in a local day.
## Meeting it pays STUDY_GOAL_CRYSTALS once that day and grows the streak; a missed day restarts it.
## Saved. Contract: docs/systems/monetization.md.
const STUDY_GOAL_CARDS := 10
const STUDY_GOAL_CRYSTALS := 15
var study_streak := 0
## The last day the goal was met, and today's flashcard count toward it.
var study_goal_day := ""
var study_cards_day := ""
var study_cards := 0

## Counts study toward today's goal; returns the crystals paid when this meets it (else 0).
func note_study(cards: int, runs: int) -> int:
	var today := Time.get_date_string_from_system()
	if study_goal_day == today:
		return 0
	if study_cards_day != today:
		study_cards_day = today
		study_cards = 0
	study_cards += cards
	if runs == 0 and study_cards < STUDY_GOAL_CARDS:
		return 0
	study_streak = study_streak + 1 if study_goal_day == _yesterday(today) else 1
	study_goal_day = today
	add_crystals(STUDY_GOAL_CRYSTALS)
	return STUDY_GOAL_CRYSTALS

## The streak as it stands today: 0 once a whole day has passed without meeting the goal.
func current_streak() -> int:
	var today := Time.get_date_string_from_system()
	return study_streak if study_goal_day in [today, _yesterday(today)] else 0

func _yesterday(day: String) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(day) - 86400)

## Closet costumes bought with crystals (kuiz_look.gd COSTUME_UNLOCKS); free ones are always owned. Saved.
var owned_costumes: Array[String] = []

## Buys a costume for `price` crystals; false (nothing spent) without enough.
func buy_costume(id: String, price: int) -> bool:
	if crystals < price:
		return false
	add_crystals(-price)
	if not owned_costumes.has(id):
		owned_costumes.append(id)
	return true

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
