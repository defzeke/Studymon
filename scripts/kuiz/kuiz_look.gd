extends Node
## What Kuiz wears and how grubby it is, all on its Head bone so it follows every clip and turn.
## Dirt spots and scratches are decals projected onto the shell, fading in one by one as
## CompanionState.dirt rises; the outfit (GameState.outfit, one costume per closet slot) is
## stickers (Sprite3D). Positions are in Head-bone space (the
## white shell's forehead band is y 0.62–1.05, the dark screen covers the face below it, ears rise
## to y 1.45 behind z 0.26, and the shell's bottom edge is at y -0.9).
## Contract: docs/ui-and-assets.md §2 Kuiz's look.

## The closet's costumes, in closet order (assets/data/costumes/*.tres): each one's name, art, slot,
## level and price, and where its sticker sits. Contract: docs/systems/monetization.md.
@export var costumes: Array[Costume] = []

## The dirt decals and the outfit stickers live in kuiz_head.tscn, on Kuiz's Head bone: each Dirt/Mark*
## decal projects onto the shell and starts to show at its `shows_from` dirt (metadata).
const HEAD_SCENE: PackedScene = preload("res://scenes/kuiz/kuiz_head.tscn")
## Dirt above a decal's threshold fades it in over this many points.
const FADE := 10.0

var _head: BoneAttachment3D
var _dirt: Array[Decal] = []
## slot -> [its sticker, the costume id it shows ("-" before the first update)]
var _worn := {}

## `kuiz` is the instanced glb (peek.gd hands it over).
func attach(kuiz: Node3D) -> void:
	var skeleton: Skeleton3D = kuiz.find_child("Skeleton3D", true, false)
	_head = HEAD_SCENE.instantiate()
	skeleton.add_child(_head)
	for d: Decal in _head.get_node("Dirt").get_children():
		_dirt.append(d)
	# One sticker per closet slot (head, face, body), named after it: Kuiz wears one costume per slot.
	for s: Sprite3D in _head.get_node("Stickers").get_children():
		_worn[String(s.name)] = [s, "-"]

func _process(_delta: float) -> void:
	if _head == null:
		return
	var dirt := CompanionState.dirt
	for d in _dirt:
		var a := clampf((dirt - float(d.get_meta("shows_from"))) / FADE, 0.0, 1.0)
		d.modulate.a = a
		d.visible = a > 0.0
	for slot: String in _worn:
		var id: String = GameState.outfit.get(slot, "")
		var worn: Array = _worn[slot]
		if id == worn[1]:
			continue
		worn[1] = id
		var s: Sprite3D = worn[0]
		var c := costume(id)
		s.visible = c != null
		if c:
			_place(s, c.texture, c.position, c.width, c.tilt)

func _place(s: Sprite3D, tex: Texture2D, at: Vector3, width: float, tilt: float) -> void:
	s.texture = tex
	s.pixel_size = width / tex.get_width()
	s.position = at
	s.rotation = Vector3(0.0, 0.0, tilt)

## The costume with `id`, or null ("" is no costume).
func costume(id: String) -> Costume:
	for c in costumes:
		if c.id == id:
			return c
	return null
