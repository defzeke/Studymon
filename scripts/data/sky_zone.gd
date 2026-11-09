class_name SkyZone
extends Resource
## A Sky Jump zone: from `from_m` metres up its platforms take its art and its banner flashes. Listed
## in climb order on SkyJumpHud's `zones` (peek.tscn); zone i after the first fades in child i - 1 of
## %ZoneBackdrops. Contract: docs/ui-and-assets.md §2 Minigames.

@export var from_m := 0
@export var banner := ""
@export var platform: Texture2D
