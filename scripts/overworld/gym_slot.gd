class_name GymSlot
extends Node3D
## One gym on the island, placed in region_map.tscn. Move the marker in the editor to move the gym;
## nothing here is looked up by name. Door clips are the map's own animation names; leave them empty
## for a gym with no door. (The Challenge Houses are the map's houses, found by MapHouses.)

## Where the explorer walks in to trigger the gym.
@export var entrance: Marker3D
@export var door_open_clip: StringName
@export var door_close_clip: StringName
