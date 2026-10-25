extends Node
## What Kuiz wears and how grubby it is, all on its Head bone so it follows every clip and turn.
## Dirt spots and scratches are decals projected onto the shell, fading in one by one as
## CompanionState.dirt rises; the outfit (GameState.outfit, one costume per closet slot) is
## stickers (Sprite3D). Positions are in Head-bone space (the
## white shell's forehead band is y 0.62–1.05, the dark screen covers the face below it, ears rise
## to y 1.45 behind z 0.26, and the shell's bottom edge is at y -0.9).
## Contract: docs/ui-and-assets.md §2 Kuiz's look.

## The closet's tabs: [slot id, tab name]. Kuiz wears one costume per slot.
const SLOTS := [["head", "Head"], ["face", "Face"], ["body", "Body"]]
## id -> [name, texture, centre, width (model units), tilt (radians), slot]
const COSTUMES := {
	"party_hat": ["Party hat", preload("res://assets/sprites/props/costume_party_hat.svg"), Vector3(0.0, 1.4, 0.36), 0.8, 0.0, "head"],
	"crown": ["Crown", preload("res://assets/sprites/props/costume_crown.svg"), Vector3(0.0, 1.18, 0.42), 0.86, 0.0, "head"],
	"beanie": ["Beanie", preload("res://assets/sprites/props/costume_beanie.svg"), Vector3(0.0, 1.08, 0.5), 1.7, 0.0, "head"],
	"bow": ["Bow", preload("res://assets/sprites/props/costume_bow.svg"), Vector3(0.78, 1.12, 0.4), 0.62, -0.35, "head"],
	"flower": ["Flower", preload("res://assets/sprites/props/costume_flower.svg"), Vector3(-0.78, 1.08, 0.42), 0.46, 0.3, "head"],
	"glasses": ["Glasses", preload("res://assets/sprites/props/costume_glasses.svg"), Vector3(0.0, -0.17, 1.1), 1.75, 0.0, "face"],
	"shades": ["Shades", preload("res://assets/sprites/props/costume_shades.svg"), Vector3(0.0, -0.17, 1.1), 1.8, 0.0, "face"],
	"hero_mask": ["Hero mask", preload("res://assets/sprites/props/costume_hero_mask.svg"), Vector3(0.0, -0.14, 1.1), 2.0, 0.0, "face"],
	"bow_tie": ["Bow tie", preload("res://assets/sprites/props/costume_bow_tie.svg"), Vector3(0.0, -0.9, 0.92), 0.74, 0.0, "body"],
	"scarf": ["Scarf", preload("res://assets/sprites/props/costume_scarf.svg"), Vector3(0.05, -0.92, 0.9), 2.2, 0.0, "body"],
	"medal": ["Medal", preload("res://assets/sprites/props/costume_medal.svg"), Vector3(0.0, -1.0, 0.9), 0.56, 0.0, "body"],
}
## Dirt is projected onto the shell (Decal), so it hugs the curve instead of floating in front:
## [texture, surface point, its outward normal, width, tilt (radians), dirt at which it starts to
## show]. Points and normals are vertices of Head_Shell / EarMesh_R in rest pose.
const DIRT := [
	[preload("res://assets/sprites/props/dirt_spot_1.svg"), Vector3(-0.555, 0.807, 0.526), Vector3(-0.369, 0.747, 0.553), 0.48, 0.0, 12.0],
	[preload("res://assets/sprites/props/scratch_1.svg"), Vector3(0.553, 0.787, 0.553), Vector3(0.361, 0.722, 0.590), 0.68, -0.2, 28.0],
	[preload("res://assets/sprites/props/dirt_spot_2.svg"), Vector3(-1.002, 0.149, 0.579), Vector3(-0.814, 0.181, 0.552), 0.42, 0.0, 42.0],
	[preload("res://assets/sprites/props/dirt_spot_3.svg"), Vector3(0.841, 1.146, -0.247), Vector3(0.476, 0.127, 0.870), 0.42, 0.4, 56.0],
	[preload("res://assets/sprites/props/scratch_2.svg"), Vector3(1.006, -0.349, 0.616), Vector3(0.801, -0.056, 0.597), 0.54, 1.2, 70.0],
	[preload("res://assets/sprites/props/dirt_spot_1.svg"), Vector3(-0.808, -0.705, 0.620), Vector3(-0.464, -0.735, 0.495), 0.4, -0.5, 84.0],
]
## Dirt above a decal's threshold fades it in over this many points.
const FADE := 10.0
## How deep each decal's box reaches, centred on the surface point (model units).
const DIRT_DEPTH := 0.5

var _head: BoneAttachment3D
var _dirt: Array[Decal] = []
## slot -> [its sticker, the costume id it shows ("-" before the first update)]
var _worn := {}

## `kuiz` is the instanced glb (peek.gd hands it over).
func attach(kuiz: Node3D) -> void:
	var skeleton: Skeleton3D = kuiz.find_child("Skeleton3D", true, false)
	_head = BoneAttachment3D.new()
	_head.bone_name = "Head"
	skeleton.add_child(_head)
	for d: Array in DIRT:
		_dirt.append(_decal(d[0], d[1], d[2], d[3], d[4]))
	for slot: Array in SLOTS:
		_worn[slot[0]] = [_sticker(null, Vector3.ZERO, 1.0, 0.0), "-"]

func _process(_delta: float) -> void:
	if _head == null:
		return
	var dirt := CompanionState.dirt
	for i in _dirt.size():
		var a := clampf((dirt - DIRT[i][5]) / FADE, 0.0, 1.0)
		_dirt[i].modulate.a = a
		_dirt[i].visible = a > 0.0
	for slot: String in _worn:
		var id: String = GameState.outfit.get(slot, "")
		var worn: Array = _worn[slot]
		if id == worn[1]:
			continue
		worn[1] = id
		var s: Sprite3D = worn[0]
		s.visible = COSTUMES.has(id)
		if s.visible:
			var c: Array = COSTUMES[id]
			_place(s, c[1], c[2], c[3], c[4])

# A decal projects along its -Y, with the texture across X (right) and Z (down): Y is the surface
# normal, Z points down the surface (upright art from the front), then the whole turns by `tilt`.
func _decal(tex: Texture2D, at: Vector3, normal: Vector3, width: float, tilt: float) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(width, DIRT_DEPTH, width * tex.get_height() / tex.get_width())
	d.normal_fade = 0.4
	var y := normal.normalized()
	var z := (Vector3.DOWN - y * Vector3.DOWN.dot(y)).normalized()
	d.basis = Basis(y.cross(z), y, z).rotated(y, tilt)
	d.position = at
	d.modulate.a = 0.0
	d.visible = false
	_head.add_child(d)
	return d

func _sticker(tex: Texture2D, at: Vector3, width: float, tilt: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.shaded = false
	s.double_sided = false
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	s.render_priority = 1
	_head.add_child(s)
	if tex != null:
		_place(s, tex, at, width, tilt)
	return s

func _place(s: Sprite3D, tex: Texture2D, at: Vector3, width: float, tilt: float) -> void:
	s.texture = tex
	s.pixel_size = width / tex.get_width()
	s.position = at
	s.rotation = Vector3(0.0, 0.0, tilt)
