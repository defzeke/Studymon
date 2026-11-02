class_name EncounterTrigger
extends Area3D
## A spot the explorer walks into (house, gym or Champion), with a billboard label above it and an
## optional coloured pad on the ground. Look, label font and sizes are set in encounter_trigger.tscn;
## the map sets `text`, `radius` (or `box`), `pad_color` and `show_pad` before adding it to the tree.

@export var radius := 0.7
## When set, the trigger is this box (standing on the ground) instead of the cylinder: a house uses
## its own footprint, so walking into the house is what triggers it.
@export var box := Vector3.ZERO
@export var show_pad := false
@export var pad_color := Color.WHITE
@export var text := ""
## How high the label floats; houses raise it above their roof.
@export var label_height := 1.4

@onready var shape: CollisionShape3D = %Shape
@onready var label: Label3D = %Label
@onready var pad: MeshInstance3D = %Pad

func _ready() -> void:
	if box != Vector3.ZERO:
		var b := BoxShape3D.new()
		b.size = box
		shape.shape = b
		shape.position.y = box.y / 2.0
	else:
		var cyl := shape.shape.duplicate() as CylinderShape3D
		cyl.radius = radius
		shape.shape = cyl
	label.text = text
	label.position.y = label_height
	pad.visible = show_pad
	var disc := pad.mesh.duplicate() as CylinderMesh
	disc.top_radius = radius
	disc.bottom_radius = radius
	var mat := disc.material.duplicate() as StandardMaterial3D
	mat.albedo_color = pad_color
	disc.material = mat
	pad.mesh = disc

## Greys the trigger out once its house is cleared.
func dim() -> void:
	var mat := pad.mesh.material as StandardMaterial3D
	mat.albedo_color = mat.albedo_color.darkened(0.5)
	label.modulate.a = 0.5
