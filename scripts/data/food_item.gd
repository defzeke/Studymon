class_name FoodItem
extends Resource
## A food the fridge sells and Kuiz eats. One .tres per food in assets/data/foods/, listed on the Home
## node's `foods` (peek.tscn). Contract: docs/systems/monetization.md, docs/systems/companion-care.md.

## Saved in GameState.food_stock: never change it once players have the food.
@export var id := ""
@export var display_name := ""
@export var icon: Texture2D
## How many a new player starts with.
@export var start_stock := 0
@export var price := 0
@export_group("Restores")
@export var hunger := 0.0
@export var mood := 0.0
@export var focus := 0.0
@export_group("")
## Kuiz's favourite: it plays Pet instead of Happy when eating it.
@export var favorite := false
