class_name GoldPack
extends Resource
## A Gold top-up sold for pesos. One .tres per pack in assets/data/gold_packs/, listed on the TopUp
## node (top_up.tscn). Contract: docs/systems/monetization.md.

@export var gold := 0
## The price shown, in whole pesos; the store's own price wins once Play Billing is wired.
@export var pesos := 0
## The Google Play product id this pack will be sold under.
@export var product_id := ""
