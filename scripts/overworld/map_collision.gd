class_name MapCollision
extends Node
## map.glb ships without collision, so this builds trimesh bodies for its meshes at startup, picking
## them by name. The keyword lists and layers are editable on this node in region_map.tscn; a mesh
## that matches no list gets no collision (water, roofs, flags, glows).

@export var map: Node3D
## Walkable surfaces, on the ground layer (height only).
@export var ground_keywords: PackedStringArray = ["Ground_Roads", "Grass_Blocks", "Sand_", "House_Foundation", "Door_Step", "Plinth", "Court_Surface", "_Path", "Interior_Floor"]
## What blocks the explorer, on the obstacle layer.
@export var obstacle_keywords: PackedStringArray = ["Wall_", "Window", "Door", "_Wall", "_Glass", "_Trim", "_Sign", "_Band", "Interior_Back", "Tree_", "Lamp_Pole", "Rocks"]
## Meshes that match an obstacle keyword but must stay walkable-through.
@export var not_obstacle_keywords: PackedStringArray = ["Door_Step", "Dome_Glass"]
## Meshes whose parent name contains this are door leaves, which swing open and never block.
@export var door_parent_keyword := "_Door_"
@export_flags_3d_physics var ground_layer := 1
@export_flags_3d_physics var obstacle_layer := 2

func _ready() -> void:
	if map == null:
		push_warning("MapCollision: no map assigned, so the island has no collision.")
		return
	for mesh: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var layer := _layer_for(mesh)
		if layer == 0:
			continue
		mesh.create_trimesh_collision()
		var body := mesh.get_child(mesh.get_child_count() - 1) as StaticBody3D
		if body == null:
			continue
		body.collision_layer = layer
		body.collision_mask = 0

func _layer_for(mesh: MeshInstance3D) -> int:
	var n := String(mesh.name)
	if _matches(n, ground_keywords):
		return ground_layer
	if _matches(n, obstacle_keywords) and not _matches(n, not_obstacle_keywords) \
			and not mesh.get_parent().name.contains(door_parent_keyword):
		return obstacle_layer
	return 0

func _matches(n: String, keywords: PackedStringArray) -> bool:
	for k in keywords:
		if n.contains(k):
			return true
	return false
