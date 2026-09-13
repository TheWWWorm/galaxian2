extends RefCounted
## Resolve supported ordinary flight locations through their own catalogues.
const MiningFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const Definitions=preload("res://src/content/arrival_environment_definitions.gd")
const SkyDefinitions=preload("res://src/content/opening_sky_definitions.gd")
const Planets=preload("res://src/content/planet_resource_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
var error:=""

func resolve(bindings: RefCounted, catalogues: RefCounted, arrival_cache: Variant) -> Dictionary:
	error=""
	if bindings==null or catalogues==null:return reject("Rescue environment requires content and catalogues")
	var data: Dictionary=bindings.arrival_environment
	if not Definitions.parameters(data) or not SkyDefinitions.parameters(bindings.opening_sky) or not Planets.parameters(bindings.opening_sky.get("planet_resources",{})):
		return reject("This profile has no supported rescue environment")
	var loadout:=Loadout.new()
	if not loadout.configure(bindings,catalogues,bindings.base_content_id):return reject(loadout.error)
	var seed:=loadout.snapshot()
	if not Cache.matches(arrival_cache,seed,int(data.campaign_cursor)):return reject("Rescue location requires the matching restored player cache")
	return _resolve(bindings,catalogues,seed,int(data.campaign_cursor))

func resolve_departure(bindings: RefCounted, catalogues: RefCounted, departure_cache: Variant) -> Dictionary:
	error=""
	if bindings==null or catalogues==null or not departure_cache is Dictionary:return reject("Mining-flight environment is unavailable")
	var flight:=MiningFlight.flight(bindings,departure_cache.get("campaign_cursor"))
	if flight.is_empty():return reject("This departure has no supported mining-flight environment")
	if not Definitions.parameters(bindings.arrival_environment) or not SkyDefinitions.parameters(bindings.opening_sky) or not Planets.parameters(bindings.opening_sky.get("planet_resources",{})):return reject("First flight requires the shared ordinary environment")
	var loadout:=Loadout.new()
	if not loadout.configure_station(bindings,catalogues,bindings.base_content_id):return reject(loadout.error)
	var seed:=loadout.snapshot()
	if not Cache.matches(departure_cache,seed,int(flight.campaign_cursor)):return reject("Mining-flight location requires the replacement ship cache")
	return _resolve(bindings,catalogues,seed,int(flight.campaign_cursor))

func _resolve(bindings: RefCounted, catalogues: RefCounted, seed: Dictionary, cursor: int) -> Dictionary:
	var data: Dictionary=bindings.arrival_environment
	var system: Dictionary=catalogues.tables.systems[seed.system_id]
	var station: Dictionary=catalogues.tables.stations[seed.station_id]
	if seed.system_id==int(data.special_system_id) or not Numbers.integer(system.get("sky_index"),0,int(data.maximum_sky_index)):
		return reject("This flight uses an unsupported system background")
	if station.get("planet_type")!=int(data.supported_planet_type):return reject("This flight uses an unsupported planet layout")
	var index:=int(system.sky_index)
	var sky: Dictionary=bindings.opening_sky
	var result:=seed.duplicate(true)
	result.campaign_cursor=cursor;result.world_type=int(data.world_type)
	result.sky_index=index
	result.sky_parameters={"star_variants":int(sky.star_variants),"star_mesh_base":int(sky.star_mesh_base),
		"star_texture_base":int(sky.star_texture_base),"sky_mesh_id":int(data.sky_mesh_base)+index,"sky_texture_id":int(data.sky_texture_base)+index}
	result.current_planet_texture_id=int(sky.planet_resources.near_textures[int(station.planet_type)])
	return result

func reject(message: String) -> Dictionary:
	error=message
	return {}
