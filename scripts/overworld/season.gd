extends Node3D
## Dresses the island for a season picked at random each time the overworld loads, never the same
## one twice in a row: light, sky, fog, foliage and grass tint, and weather falling around the
## explorer. Contract: docs/systems/overworld.md §3.

enum Season { SUNNY, RAINY, AUTUMN, SNOWY }

const AMBER := Color("D6A85F")
const CORAL := Color("C97970")
const SNOW := Color(0.93, 0.96, 0.98)
const LEAF: Texture2D = preload("res://assets/sprites/effects/leaf.svg")
# Per season: sun colour/energy, sky, ambient colour/energy, fog density (0 = off), and how far the
# foliage and grass are pulled toward a colour (autumn cycles its canopies through `canopies`).
const LOOKS := {
	Season.SUNNY: {"sun": Color(1.0, 0.96, 0.88), "sun_energy": 1.15, "sky": Color(0.749, 0.851, 0.902),
		"ambient": Color(0.8, 0.85, 0.88), "ambient_energy": 0.7, "fog": 0.0,
		"canopies": [], "canopy_mix": 0.0, "grass": Color.WHITE, "grass_mix": 0.0},
	Season.RAINY: {"sun": Color(0.78, 0.84, 0.9), "sun_energy": 0.35, "sky": Color(0.55, 0.62, 0.68),
		"ambient": Color(0.62, 0.68, 0.75), "ambient_energy": 0.85, "fog": 0.025,
		"canopies": [Color(0.18, 0.32, 0.24)], "canopy_mix": 0.3, "grass": Color(0.3, 0.5, 0.3), "grass_mix": 0.3},
	Season.AUTUMN: {"sun": Color(1.0, 0.84, 0.66), "sun_energy": 1.0, "sky": Color(0.85, 0.8, 0.7),
		"ambient": Color(0.9, 0.8, 0.7), "ambient_energy": 0.7, "fog": 0.0,
		"canopies": [AMBER, CORAL, Color(0.81, 0.57, 0.41), Color(0.72, 0.42, 0.25)], "canopy_mix": 0.75,
		"grass": Color(0.78, 0.72, 0.4), "grass_mix": 0.45},
	Season.SNOWY: {"sun": Color(0.9, 0.95, 1.0), "sun_energy": 0.9, "sky": Color(0.82, 0.87, 0.92),
		"ambient": Color(0.85, 0.9, 0.97), "ambient_energy": 0.9, "fog": 0.015,
		"canopies": [SNOW], "canopy_mix": 0.55, "grass": SNOW, "grass_mix": 0.85},
}
const FOLIAGE_MESHES: Array[String] = ["Tree_Canopy_", "Tree_Conifer"]
const GRASS_MESH := "Grass_Blocks"
# Weather fills the volume the camera sees around the explorer: 0.5–4.5 up, from 10 behind to 4
# in front. Higher, it would only cross the camera's view right at the lens.
const WEATHER_OFFSET := Vector3(0.0, 2.5, -3.0)
const WEATHER_BOX := Vector3(7.0, 2.0, 7.0)
# Culling box for the simulated particles: the emitter box plus the fall to the ground.
const WEATHER_BOUNDS := AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 7.0, 16.0))

static var _last := -1

@export var sun: DirectionalLight3D
@export var world: WorldEnvironment
@export var map: Node3D
@export var follow: Node3D

var season: Season
var _weather: GPUParticles3D

func _ready() -> void:
	var options: Array = Season.values()
	options.erase(_last)
	season = options.pick_random()
	_last = season
	var look: Dictionary = LOOKS[season]
	sun.light_color = look["sun"]
	sun.light_energy = look["sun_energy"]
	# The Environment is shared by every load of the scene, so set every field each time.
	var env := world.environment
	env.background_color = look["sky"]
	env.ambient_light_color = look["ambient"]
	env.ambient_light_energy = look["ambient_energy"]
	env.fog_enabled = look["fog"] > 0.0
	env.fog_light_color = look["sky"]
	env.fog_density = look["fog"]
	_tint(look)
	_weather = _make_weather()
	if _weather:
		# Deferred so the explorer is already at the spawn point when the weather prewarms there.
		_start_weather.call_deferred()

func _start_weather() -> void:
	_weather.position = follow.global_position + WEATHER_OFFSET
	add_child(_weather)

func _process(_delta: float) -> void:
	if _weather and _weather.is_inside_tree():
		_weather.global_position = follow.global_position + WEATHER_OFFSET

# The map's imported materials are shared with every instance, so tint copies.
func _tint(look: Dictionary) -> void:
	var canopies: Array = look["canopies"]
	var n := 0
	for mesh: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var target := Color.WHITE
		var mix := 0.0
		if FOLIAGE_MESHES.any(func(k: String) -> bool: return mesh.name.begins_with(k)) and not canopies.is_empty():
			target = canopies[n % canopies.size()]
			mix = look["canopy_mix"]
			n += 1
		elif mesh.name == GRASS_MESH:
			target = look["grass"]
			mix = look["grass_mix"]
		if mix == 0.0:
			continue
		var mat := mesh.get_active_material(0).duplicate() as StandardMaterial3D
		mat.albedo_color = mat.albedo_color.lerp(target, mix)
		mesh.set_surface_override_material(0, mat)

func _make_weather() -> GPUParticles3D:
	if season == Season.SUNNY:
		return null
	var p := GPUParticles3D.new()
	var sim := ParticleProcessMaterial.new()
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	p.local_coords = false
	p.visibility_aabb = WEATHER_BOUNDS
	sim.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sim.emission_box_extents = WEATHER_BOX
	sim.direction = Vector3.DOWN
	match season:
		Season.RAINY:
			quad.size = Vector2(0.025, 0.4)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			p.amount = 400
			p.lifetime = 0.45
			sim.spread = 4.0
			sim.initial_velocity_min = 11.0
			sim.initial_velocity_max = 13.0
			sim.gravity = Vector3.ZERO
			sim.color = Color(0.85, 0.92, 1.0, 0.55)
		Season.AUTUMN:
			quad.size = Vector2(0.3, 0.3)
			mat.albedo_texture = LEAF
			p.amount = 90
			p.lifetime = 5.0
			sim.spread = 30.0
			sim.initial_velocity_min = 0.4
			sim.initial_velocity_max = 0.9
			sim.gravity = Vector3(0.3, -0.5, 0.0)
			sim.angle_min = -180.0
			sim.angle_max = 180.0
			sim.angular_velocity_min = -90.0
			sim.angular_velocity_max = 90.0
			var colors := Gradient.new()
			colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			colors.offsets = PackedFloat32Array([0.0, 0.5])
			colors.colors = PackedColorArray([AMBER, CORAL])
			var ramp := GradientTexture1D.new()
			ramp.gradient = colors
			sim.color_initial_ramp = ramp
		Season.SNOWY:
			quad.size = Vector2(0.09, 0.09)
			p.amount = 300
			p.lifetime = 5.0
			sim.spread = 25.0
			sim.initial_velocity_min = 1.0
			sim.initial_velocity_max = 1.6
			sim.gravity = Vector3(0.15, -0.2, 0.0)
			sim.color = Color(1.0, 1.0, 1.0, 0.9)
	p.preprocess = p.lifetime
	p.process_material = sim
	quad.material = mat
	p.draw_pass_1 = quad
	return p
