extends Node3D
## Dresses the island for the real-world season (Northern Hemisphere calendar, from the device date),
## so it lasts for months: light, sky, fog, foliage and grass tint, and weather falling around the
## explorer. Each season's look is a SeasonLook (assets/data/seasons/*.tres). Contract:
## docs/systems/overworld.md §3.

enum Season { SUNNY, RAINY, AUTUMN, SNOWY }

const FOLIAGE_MESHES: Array[String] = ["Tree_Canopy_", "Tree_Conifer"]
const GRASS_MESH := "Grass_Blocks"
# Weather fills the volume the camera sees around the explorer: 0.5–4.5 up, from 10 behind to 4
# in front. Higher, it would only cross the camera's view right at the lens. Each weather scene's
# emitter box is 14 x 4 x 14 around this point.
const WEATHER_OFFSET := Vector3(0.0, 2.5, -3.0)

## Dec–Feb snowy, Mar–May sunny, Jun–Aug sunny with rain every fourth day of the month,
## Sep–Nov autumn. The same date always gives the same season.
static func season_for(month: int, day: int) -> Season:
	match month:
		12, 1, 2:
			return Season.SNOWY
		3, 4, 5:
			return Season.SUNNY
		6, 7, 8:
			return Season.RAINY if day % 4 == 0 else Season.SUNNY
	return Season.AUTUMN

@export var sun: DirectionalLight3D
@export var world: WorldEnvironment
@export var map: Node3D
@export var follow: Node3D
@export_group("Looks")
@export var sunny: SeasonLook
@export var rainy: SeasonLook
@export var autumn: SeasonLook
@export var snowy: SeasonLook

var season: Season
var _weather: GPUParticles3D

func _ready() -> void:
	var today := Time.get_date_dict_from_system()
	season = season_for(int(today["month"]), int(today["day"]))
	var look := _look()
	sun.light_color = look.sun_color
	sun.light_energy = look.sun_energy
	# The Environment is shared by every load of the scene, so set every field each time.
	var env := world.environment
	env.background_color = look.sky
	env.ambient_light_color = look.ambient
	env.ambient_light_energy = look.ambient_energy
	env.fog_enabled = look.fog > 0.0
	env.fog_light_color = look.sky
	env.fog_density = look.fog
	_tint(look)
	_weather = _make_weather()
	if _weather:
		# Deferred so the explorer is already at the spawn point when the weather prewarms there.
		_start_weather.call_deferred()

func _look() -> SeasonLook:
	return [sunny, rainy, autumn, snowy][season]

func _start_weather() -> void:
	_weather.position = follow.global_position + WEATHER_OFFSET
	add_child(_weather)

func _process(_delta: float) -> void:
	if _weather and _weather.is_inside_tree():
		_weather.global_position = follow.global_position + WEATHER_OFFSET

# The map's imported materials are shared with every instance, so tint copies.
func _tint(look: SeasonLook) -> void:
	var canopies := look.canopies
	var n := 0
	for mesh: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		var target := Color.WHITE
		var mix := 0.0
		if FOLIAGE_MESHES.any(func(k: String) -> bool: return mesh.name.begins_with(k)) and not canopies.is_empty():
			target = canopies[n % canopies.size()]
			mix = look.canopy_mix
			n += 1
		elif mesh.name == GRASS_MESH:
			target = look.grass
			mix = look.grass_mix
		if mix == 0.0:
			continue
		var mat := mesh.get_active_material(0).duplicate() as StandardMaterial3D
		mat.albedo_color = mat.albedo_color.lerp(target, mix)
		mesh.set_surface_override_material(0, mat)

# The season's weather scene (scenes/overworld/weather/), or none on a clear day.
func _make_weather() -> GPUParticles3D:
	var scene := _look().weather
	return scene.instantiate() as GPUParticles3D if scene != null else null
