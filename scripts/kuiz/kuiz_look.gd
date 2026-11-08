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
## Every costume is bought with crystals: id -> [level needed, crystals]. Only "None" is free.
## Contract: docs/systems/monetization.md.
const COSTUME_UNLOCKS := {
	"party_hat": [1, 40], "beanie": [2, 60], "bow": [3, 80], "flower": [4, 100], "crown": [8, 200],
	"glasses": [1, 40], "shades": [3, 80], "hero_mask": [6, 150],
	"bow_tie": [1, 40], "scarf": [2, 60], "medal": [10, 250],
}
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
	for slot: Array in SLOTS:
		_worn[slot[0]] = [_head.get_node("Stickers/" + str(slot[0])), "-"]

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
		s.visible = COSTUMES.has(id)
		if s.visible:
			var c: Array = COSTUMES[id]
			_place(s, c[1], c[2], c[3], c[4])

func _place(s: Sprite3D, tex: Texture2D, at: Vector3, width: float, tilt: float) -> void:
	s.texture = tex
	s.pixel_size = width / tex.get_width()
	s.position = at
	s.rotation = Vector3(0.0, 0.0, tilt)
