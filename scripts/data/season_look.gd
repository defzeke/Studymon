class_name SeasonLook
extends Resource
## How the island looks in one season: light, sky, fog, foliage and grass tint, and its weather. Set
## on region_map.tscn's Season node. Contract: docs/systems/overworld.md §3.

@export var sun_color := Color.WHITE
@export var sun_energy := 1.0
@export var sky := Color.WHITE
@export var ambient := Color.WHITE
@export var ambient_energy := 1.0
## Fog density; 0 turns fog off.
@export var fog := 0.0
@export_group("Foliage")
## Tree canopies are pulled `canopy_mix` of the way toward these colours, cycling through them; none
## leaves them as authored.
@export var canopies: PackedColorArray = []
@export_range(0.0, 1.0) var canopy_mix := 0.0
@export var grass := Color.WHITE
@export_range(0.0, 1.0) var grass_mix := 0.0
@export_group("")
## Falls around the explorer (scenes/overworld/weather/); none on a clear day.
@export var weather: PackedScene
