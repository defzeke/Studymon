class_name GymSlot
extends Node3D
## One gym on the island, placed in region_map.tscn. Move the markers in the editor to move the gym;
## nothing here is looked up by name. `trainers_from` → `trainers_to` is the road its trainers stand
## on (left empty for the Champion). Door clips are the map's own animation names; leave them empty
## for a gym with no door.

## Where the explorer walks in to trigger the gym.
@export var entrance: Marker3D
@export var trainers_from: Marker3D
@export var trainers_to: Marker3D
@export var door_open_clip: StringName
@export var door_close_clip: StringName
