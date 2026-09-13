extends RefCounted
## Native preparation of material/light colors. Keep each light's ambient term
## separate: source shader variants consume these terms differently.
const Surface = preload("res://src/content/surface_material_definitions.gd")
var error := ""
var state := {}

func build(surface: Dictionary, environment: Dictionary) -> bool:
	error="";state={}
	if not Surface.parameters(surface):return fail("Source surface material parameters are unavailable")
	var ambient: Variant = environment.get("global_ambient")
	var rim: Variant = environment.get("rim_color")
	var lights: Variant = environment.get("lights")
	if not valid_rgb(ambient) or not valid_rgb(rim) or not lights is Array or lights.size()<1 or lights.size()>2:return fail("Unsupported material light state")
	var prepared := []
	for light in lights:
		if not light is Dictionary:return fail("Invalid material light")
		var direction: Variant = light.get("direction_to_light")
		if not direction is Vector3 or not direction.is_finite() or absf(direction.length_squared()-1.0)>0.0001:return fail("Material light direction must be normalized")
		for key in ["ambient", "diffuse", "specular"]:
			if not valid_rgb(light.get(key)):return fail("Material light color is unavailable: "+key)
		prepared.append({"direction_to_light":direction,
			"ambient":(ambient+light.ambient)*rgb(surface.ambient_rgb),
			"diffuse":light.diffuse*rgb(surface.diffuse_rgb),
			"specular":light.specular*rgb(surface.specular_rgb)})
	state={"lights":prepared,"specular_power":float(surface.specular_power),"rim_color":rim}
	return true

func valid_rgb(value: Variant) -> bool:
	return value is Vector3 and value.is_finite() and value.x>=0 and value.y>=0 and value.z>=0 and value.x<=48 and value.y<=48 and value.z<=48

func rgb(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func fail(message: String) -> bool:
	error=message;state={}
	return false
