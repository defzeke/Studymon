extends Button
## The round music button on the map and in battle: mutes or restores the music of both, and saves.

const ICON_ON: Texture2D = preload("res://assets/sprites/ui/icon_music_on.svg")
const ICON_OFF: Texture2D = preload("res://assets/sprites/ui/icon_music_off.svg")

func _ready() -> void:
	_refresh()
	pressed.connect(func() -> void:
		MusicManager.set_adventure_music(not MusicManager.adventure_music)
		SaveManager.save_game()
		_refresh())

func _refresh() -> void:
	icon = ICON_ON if MusicManager.adventure_music else ICON_OFF
