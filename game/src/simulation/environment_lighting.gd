extends RefCounted
## Independently designed ordinary-location light state. RGB is imported; the
## setup factors and float precision follow both verified source renderers.
## Sky 15's campaign-dependent changes and the no-station path are unsupported.
const Colors = preload("res://src/content/environment_color_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Placement = preload("res://src/simulation/sun_placement.gd")
var error := ""

func for_station(colors: Dictionary, station_id: Variant, planet_type: Variant, sky_index: Variant) -> Dictionary:
	error=""
	if not Colors.parameters(colors): return reject("Environment color tables are unavailable")
	if not Numbers.integer(sky_index,0,18) or sky_index==15:
		return reject("This sky requires unsupported environment lighting conditions")
	if not Numbers.integer(planet_type,0,26): return reject("Station planet type has no environment color row")
	var placement := Placement.new()
	var sun := placement.for_station(station_id,int(planet_type))
	if sun.is_empty(): return reject(placement.error)
	var source_sun := rgb(colors.sun_rgb[int(sky_index)])
	var source_planet := rgb(colors.planet_rgb[int(planet_type)])
	var diffuse := source_sun*15.0
	for axis in 3: diffuse[axis]=clampf(diffuse[axis],0.0,2.0)
	return {"sun":sun,"global_ambient":source_sun*PackedFloat32Array([0.15])[0],
		"rim_color":rgb(colors.rim_rgb[int(sky_index)])*3.0,
		"lights":[{"direction_to_light":sun.direction_to_sun,"ambient":Vector3.ZERO,
			"diffuse":diffuse,"specular":Vector3.ONE*2.0},
			{"direction_to_light":Vector3(0,0,-1),"ambient":Vector3.ZERO,"diffuse":source_planet*1.5,"specular":source_planet*1.5}]}

func rgb(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func reject(message: String) -> Dictionary:
	error=message
	return {}
