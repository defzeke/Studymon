extends CanvasLayer
## The first-run tutorial over peek.tscn: Kuiz introduces itself, takes a profile and a name, then
## tours the rooms. A tap finishes the typing, then advances; a line with a prompt waits for it.
## A tap after the last line ends it (`finished`), and home.gd takes over.
## Contract: docs/ui-and-assets.md §2 Tutorial.

const CHARS_PER_SEC := 40.0
const FADE_TIME := 0.35
# One entry per line. clip: Kuiz's animation for the line (a State_* mood loops until the next
# line). room + move: where Kuiz goes before the line and how (jump, walk, close). prompt: what the
# player must do once the line is shown.
const LINES: Array[Dictionary] = [
	{"text": "Hi there! Welcome to the hub! I’m Kuiz, your AI study partner and digital companion. I've been waiting so long for my system setup to finish so we could finally meet!", "clip": "Greetings"},
	{"text": "First things first—let’s set up our shared user profile so I know who I’m teaming up with. Would you like to sign in with your Google Account to save your study progress automatically, or register a new profile?", "clip": "Blink", "prompt": "profile"},
	{"text": "Awesome! Connection established and synced to the cloud. Now... what name should I call you, Partner?", "clip": "Charging", "prompt": "name"},
	{"text": "{name}! What a cool name! It’s officially registered in my core memory now!", "clip": "Happy"},
	{"text": "Alright, {name}, welcome to our main hub—The Study Room! This is where I dock in my cradle to recharge when my energy gets low, and it's also where we launch into the overworld for study battles and review sessions!", "clip": "State_Charging", "room": "StudyRoom", "move": "jump"},
	{"text": "Since we're an official team now, let me give you a proper tour of the rest of our base! Follow me!", "clip": "Celebrate"},
	{"text": "Welcome to The Maintenance Bay! Mind the loose gears! Since I’m an AI pet, my frame needs a little care after long study sessions.", "clip": "Surprised", "room": "MaintenanceBay", "move": "walk"},
	{"text": "If you ever see me squeaking or moving a bit slow, just grab a screwdriver, tighten up my frame, and tune me up right here. Keeping my hardware in top shape keeps my study focus razor-sharp!", "clip": "State_Sick"},
	{"text": "Ooh, listen to that... my internal drive is rumbling! Welcome to The Data Kitchen!", "clip": "State_Hungry", "room": "DataKitchen", "move": "walk"},
	{"text": "I don't eat regular food—my favorite snacks are high-speed Data Chips! Whenever my hunger meter drops, just feed me some chips from the dispenser. Spicy Memory Chips are my absolute favorite!", "clip": "Pet"},
	{"text": "And last, but definitely not least... The Playroom! All study and no play? No way! Hanging out and playing mini-games here keeps my mood high and boosts my performance in our study challenges!", "clip": "Happy", "room": "Playroom", "move": "walk"},
	{"text": "And that’s the whole tour! Keep me fed, tuned-up, well-rested, and happy, and we'll conquer every study session together.", "clip": "Greetings", "room": "StudyRoom", "move": "close"},
	{"text": "Ready to jump into our very first review session?", "clip": "Learn_Something_New"},
]
signal finished

@onready var peek: Node3D = owner as Node3D
@onready var speech: Control = %Speech
@onready var text: Label = %Text
@onready var continue_button: Button = %Continue
@onready var name_row: Control = %NameRow
@onready var name_input: LineEdit = %NameInput
@onready var name_ok: Button = %NameOk
@onready var hint: Control = %Hint
@onready var hint_arrow: Polygon2D = %Arrow

var _line := -1
var _typing: Tween
var _waiting := false

func _ready() -> void:
	if GameState.tutorial_done:
		speech.hide()
		return
	continue_button.pressed.connect(_next)
	name_input.text_changed.connect(func(t: String) -> void: name_ok.disabled = t.strip_edges().is_empty())
	name_input.text_submitted.connect(func(_t: String) -> void: _submit_name())
	name_ok.pressed.connect(_submit_name)
	var bob := create_tween().set_loops()
	bob.tween_property(hint_arrow, "position:y", 5.0, 0.45).set_trans(Tween.TRANS_SINE)
	bob.tween_property(hint_arrow, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	await peek.peeked
	_fade(speech, 1.0)
	_next()

func _unhandled_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not (tap or event.is_action_pressed("ui_accept")):
		return
	if _typing and _typing.is_running():
		_typing.kill()
		text.visible_ratio = 1.0
		_shown()
	elif _waiting:
		_next()
	get_viewport().set_input_as_handled()

func _next() -> void:
	_waiting = false
	hint.modulate.a = 0.0
	continue_button.hide()
	name_row.hide()
	_line += 1
	if _line == LINES.size():
		GameState.tutorial_done = true
		set_process_unhandled_input(false)
		await _fade(speech, 0.0).finished
		finished.emit()
		return
	var line: Dictionary = LINES[_line]
	if line.has("move"):
		await _fade(speech, 0.0).finished
		match line["move"]:
			"jump":
				await peek.jump(peek.show_room.bind(line["room"]))
			"walk":
				await peek.walk(peek.show_room.bind(line["room"]))
			"close":
				await peek.walk(peek.show_room.bind(line["room"]))
				await peek.come_close()
		_fade(speech, 1.0)
	peek.act(line["clip"])
	text.text = line["text"].format({"name": GameState.player_name})
	text.visible_ratio = 0.0
	_typing = create_tween()
	_typing.tween_property(text, "visible_ratio", 1.0, text.text.length() / CHARS_PER_SEC)
	_typing.finished.connect(_shown)

func _shown() -> void:
	match LINES[_line].get("prompt", ""):
		"profile":
			continue_button.show()
		"name":
			name_row.show()
			name_input.grab_focus()
		_:
			_waiting = true
			hint.modulate.a = 1.0

func _submit_name() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		return
	GameState.player_name = player_name
	SaveManager.save_progress()
	name_input.release_focus()
	_next()

func _fade(item: CanvasItem, alpha: float) -> Tween:
	var t := create_tween()
	t.tween_property(item, "modulate:a", alpha, FADE_TIME)
	return t
