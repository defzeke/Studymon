class_name Costume
extends Resource
## A closet costume: a sticker on Kuiz's Head bone, bought with crystals once Kuiz reaches its level, or
## with Gold if it is premium.
## One .tres per costume in assets/data/costumes/, listed on the Look node's `costumes` (peek.tscn), in
## closet order. Contract: docs/ui-and-assets.md §2 Kuiz's look, docs/systems/monetization.md.

## Saved in GameState.outfit and owned_costumes: never change it once players own the costume.
@export var id := ""
@export var display_name := ""
@export var texture: Texture2D
@export_enum("head", "face", "body") var slot := "head"
@export var level_needed := 1
@export var price := 0
## Premium: bought with this much Gold instead (price is ignored).
@export var gold_price := 0
@export_group("Placement")
## The sticker's centre in Head-bone space (model units), its width and its tilt (radians).
@export var position := Vector3.ZERO
@export var width := 1.0
@export var tilt := 0.0
