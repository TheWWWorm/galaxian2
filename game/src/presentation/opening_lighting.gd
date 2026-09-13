extends Node3D
## Godot light adapter for the recovered opening. Source colors/directions are
## preserved; Godot's PBR material response is not original shader parity.
const Lighting = preload("res://src/simulation/environment_lighting.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const ArrivalLocation = preload("res://src/simulation/arrival_location.gd")
const Definitions = preload("res://src/content/opening_sky_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var state := {}
var lights: Array[DirectionalLight3D] = []
var environment: WorldEnvironment

func build(bindings: RefCounted, catalogues: RefCounted, content_id: String, campaign_cursor: Variant, world_type: Variant, location_match: Variant) -> bool:
	clear()
	if not Definitions.parameters(bindings.opening_sky) or not Numbers.integer(campaign_cursor,0,0) or not Numbers.integer(world_type,3,3) or not location_match is bool or location_match:
		return reject("Opening lighting requires the verified fresh opening context")
	var loadout := Loadout.new()
	if not loadout.configure(bindings,catalogues,content_id): return reject(loadout.error)
	return _build_station(bindings,catalogues,loadout.snapshot())

func build_arrival(bindings: RefCounted, catalogues: RefCounted, cache: Variant) -> bool:
	clear()
	var location:=ArrivalLocation.new()
	var context:=location.resolve(bindings,catalogues,cache)
	if context.is_empty():return reject(location.error)
	return _build_station(bindings,catalogues,context)

func build_departure(bindings: RefCounted, catalogues: RefCounted, cache: Variant, equipment: RefCounted=null) -> bool:
	clear()
	var location:=ArrivalLocation.new()
	var context:=location.resolve_departure(bindings,catalogues,cache,equipment)
	if context.is_empty():return reject(location.error)
	return _build_station(bindings,catalogues,context)

func _build_station(bindings: RefCounted, catalogues: RefCounted, context: Dictionary) -> bool:
	var station: Dictionary = catalogues.tables.stations[context.station_id]
	var system: Dictionary = catalogues.tables.systems[context.system_id]
	var model := Lighting.new()
	var staged := model.for_station(bindings.environment_colors,context.station_id,station.get("planet_type"),system.get("sky_index"))
	if staged.is_empty(): return reject(model.error)
	environment=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	var ambient: Vector3 = staged.global_ambient
	var strength := maxf(ambient.x,maxf(ambient.y,ambient.z))
	environment.environment.ambient_light_energy=strength
	environment.environment.ambient_light_color=encoded_color(ambient/strength if strength>0 else Vector3.ZERO)
	add_child(environment)
	for row in staged.lights:
		var light := DirectionalLight3D.new()
		var energy: float = maxf(row.diffuse.x,maxf(row.diffuse.y,row.diffuse.z))
		light.light_color=encoded_color(row.diffuse/energy if energy>0 else Vector3.ZERO)
		light.light_energy=energy
		light.light_specular=1.0
		light.basis=Basis.looking_at(-row.direction_to_light,Vector3.UP)
		light.shadow_enabled=false
		add_child(light);lights.append(light)
	state=staged
	state.base_content_id=bindings.base_content_id;state.binding_id=bindings.binding_id
	state.station_id=context.station_id;state.system_id=context.system_id
	return true

func encoded_color(linear: Vector3) -> Color:
	return Color(linear.x,linear.y,linear.z).linear_to_srgb()

func clear() -> void:
	for child in get_children(): child.free()
	lights.clear();environment=null;state.clear();error=""

func reject(message: String) -> bool:
	clear();error=message
	return false
