extends Control
## Phase 0: Root. Loads save, instantiates companion room.

func _ready() -> void:
	SaveManager.load_game()
