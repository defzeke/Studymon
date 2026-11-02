class_name MapHouses
extends RefCounted
## Finds the island's houses in map.glb. The houses are merged by material (one `House_Foundation`
## mesh, one `Door` mesh), so a house is a cluster of foundation triangles and its door is the door
## triangles over that footprint. Contract: docs/systems/overworld.md §2.

const FOUNDATION := "House_Foundation"
const DOOR := "Door"
## Walls and roofs reach about this high (the tallest house is 2.05).
const HEIGHT := 2.1

## [{id, box, door, facing, door_size}]: `box` is the footprint from the ground up to HEIGHT, `door` the
## door's centre, `facing` the unit vector out of the door, `door_size` its width and height. Sorted north
## to south, then west to east, so a house keeps its id ("h1".."hN") from run to run.
static func find(map: Node3D) -> Array[Dictionary]:
	var boxes: Array[AABB] = []
	for b in _tri_boxes(map, FOUNDATION):
		boxes.append(b)
	var merged := true
	while merged:
		merged = false
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				if boxes[i].grow(0.05).intersects(boxes[j].grow(0.05)):
					boxes[i] = boxes[i].merge(boxes[j])
					boxes.remove_at(j)
					merged = true
					break
			if merged:
				break
	var doors := _tri_boxes(map, DOOR)
	var out: Array[Dictionary] = []
	for b in boxes:
		var door := AABB()
		var found := false
		for d in doors:
			var c := d.get_center()
			if c.x > b.position.x - 0.5 and c.x < b.end.x + 0.5 and c.z > b.position.z - 0.5 and c.z < b.end.z + 0.5:
				door = d if not found else door.merge(d)
				found = true
		if not found:
			continue
		var centre := door.get_center()
		# The door is a thin slab: it faces along its thin axis, away from the middle of the house.
		var facing := Vector3(signf(centre.x - b.get_center().x), 0, 0)
		var size := Vector2(door.size.z, door.size.y)
		if door.size.z < door.size.x:
			facing = Vector3(0, 0, signf(centre.z - b.get_center().z))
			size = Vector2(door.size.x, door.size.y)
		var foot := AABB(Vector3(b.position.x, 0.0, b.position.z), Vector3(b.size.x, HEIGHT, b.size.z))
		out.append({"box": foot, "door": centre, "facing": facing, "door_size": size})
	out.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		var pa: Vector3 = (a["box"] as AABB).get_center()
		var pc: Vector3 = (c["box"] as AABB).get_center()
		return pa.z < pc.z or (is_equal_approx(pa.z, pc.z) and pa.x < pc.x))
	for i in out.size():
		out[i]["id"] = "h%d" % (i + 1)
	return out

# One world-space box per triangle of every mesh named `mesh_name` under `map`.
static func _tri_boxes(map: Node3D, mesh_name: String) -> Array[AABB]:
	var out: Array[AABB] = []
	for mi: MeshInstance3D in map.find_children(mesh_name, "MeshInstance3D", true, false):
		if mi.name != mesh_name:
			continue
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx = PackedInt32Array(range(v.size()))
			for t in range(0, idx.size(), 3):
				out.append(AABB(xf * v[idx[t]], Vector3.ZERO).expand(xf * v[idx[t + 1]]).expand(xf * v[idx[t + 2]]))
	return out
