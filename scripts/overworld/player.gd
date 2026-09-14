extends CharacterBody2D
## Phase 6: top-down overworld player (GDD §6.1)
## CharacterBody2D + 4/8-directional movement via built-in ui_* actions.
## No custom InputMap needed — arrows + WASD both drive ui_* by default.

const SPEED := 300.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	# Fallback sprite if no texture assigned in scene
	if sprite.texture == null and ResourceLoader.exists("res://assets/sprites/bot_lv5.png"):
		sprite.texture = load("res://assets/sprites/bot_lv5.png") as Texture2D

func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = dir * SPEED
	move_and_slide()
	# Face movement direction (flip sprite horizontally)
	if dir.x != 0.0 and sprite != null:
		sprite.flip_h = dir.x < 0.0
