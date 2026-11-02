extends CanvasLayer
## Shared by the Playroom minigames (inside peek.tscn). home.gd calls start(); the game shows its
## backdrop (a node under Rooms, behind Kuiz) and moves Kuiz with peek.place(). Each finished round
## pays its crystals and emits `played` (home counts it as play care and saves); leaving emits
## `finished`.
## Contract: docs/ui-and-assets.md §2 Minigames.

signal played
signal finished

const ConfirmModal := preload("res://scripts/ui/widgets/confirm_modal.gd")
# The backdrops are drawn for a 720x1280 screen and cover the view (TextureRect keep-aspect-covered).
const ART := Vector2(720, 1280)

@onready var peek: Node3D = owner as Node3D

var playing := false

func _ready() -> void:
	visible = false

func start() -> void:
	visible = true
	_begin()

## Subclasses set up a fresh round here.
func _begin() -> void:
	pass

func quit() -> void:
	playing = false
	visible = false
	finished.emit()

## Ends a round: pays `crystals`, and a pop-up offers another round or going back to the Playroom.
func _game_over(title: String, message: String, crystals: int) -> void:
	playing = false
	var paid := GameState.pay_minigame(crystals)
	if paid > 0:
		message += "\n+%d crystals" % paid
	if paid < crystals:
		message += "\nToday's minigame crystals are used up: battles still pay."
	played.emit()
	var again := [false]
	var modal := ConfirmModal.open(self, title, message, "Play again", func() -> void: again[0] = true, false, "Back")
	# Only a pop-up closed by its buttons (or Esc) queues itself; the whole scene unloading does not.
	modal.tree_exited.connect(func() -> void:
		if not modal.is_queued_for_deletion():
			return
		if again[0]:
			_begin()
		else:
			quit())

func _view() -> Vector2:
	return get_viewport().get_visible_rect().size

## How much the covering backdrop is scaled up from its 720x1280 art.
func _art_scale() -> float:
	var view := _view()
	return maxf(view.x / ART.x, view.y / ART.y)

## A point in the backdrop's art, on screen.
func _art(point: Vector2) -> Vector2:
	var k := _art_scale()
	return (_view() - ART * k) / 2.0 + point * k

## Kuiz's stage scale for a size measured on a 720-wide screen: the 3D camera keeps the screen
## width, so Kuiz grows with width while the backdrop grows with its covering scale.
func _kuiz_scale(base: float) -> float:
	return base * _art_scale() / (_view().x / ART.x)
