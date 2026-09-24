extends RefCounted
const FlightStages=preload("res://src/content/flight_stages.gd")
## Resolve supported ordinary flight locations through their own catalogues.
const MiningFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const Definitions=preload("res://src/content/arrival_environment_definitions.gd")
const SkyDefinitions=preload("res://src/content/opening_sky_definitions.gd")
const Planets=preload("res://src/content/planet_resource_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Training=preload("res://src/content/combat_training_story_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Lounge=preload("res://src/content/lounge_presentation_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const Sahi=preload("res://src/content/sahi_encounter_definitions.gd")
var error:=""

func resolve_lounge(bindings: RefCounted,catalogues: RefCounted,station_id: int,cursor: int) -> Dictionary:
	error=""
	if not Lounge.available(bindings) or catalogues==null or catalogues.content_id!=bindings.base_content_id:return reject("The lounge requires matching location declarations")
	if station_id<0 or station_id>=catalogues.tables.stations.size():return reject("Unknown lounge station")
	var station: Dictionary=catalogues.tables.stations[station_id]
	var ordinary: bool=load("res://src/content/local_arrival_environment_definitions.gd").location_supported(bindings,catalogues,station_id,cursor)
	if not ordinary and (not Travel.location_supported(bindings.mido_travel,station_id,int(station.system_id),int(station.planet_type)) or cursor not in [13,14,15]):return reject("This lounge location is not yet supported")
	var context:=_resolve(bindings,catalogues,{"station_id":station_id,"system_id":int(station.system_id)},cursor)
	if not context.is_empty():context.world_type=int(bindings.early_contracts.lounge_presentation.world_type)
	return context

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

func resolve_departure(bindings: RefCounted, catalogues: RefCounted, departure_cache: Variant, equipment: RefCounted=null) -> Dictionary:
	error=""
	if bindings==null or catalogues==null or not departure_cache is Dictionary:return reject("Mining-flight environment is unavailable")
	if departure_cache.get("campaign_cursor")==7:return resolve_combat_training(bindings,catalogues,equipment,departure_cache)
	if departure_cache.get("campaign_cursor") in FlightStages.LOCAL+FlightStages.POST_SAHI:return resolve_local_travel(bindings,catalogues,equipment,departure_cache)
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
	var local_travel:=(not Travel.player_entry(bindings.mido_travel,int(seed.station_id),cursor).is_empty() or (cursor==16 and not Cache.alioth_entry(bindings.mido_travel).is_empty())) and Travel.location_supported(bindings.mido_travel,int(seed.station_id),int(seed.system_id),int(station.get("planet_type",-1)))
	var sahi_entry:=Cache.post_sahi_entry(bindings.mido_travel,cursor,int(seed.get("ship_id",-1))) if cursor==26 else Cache.sahi_entry(bindings.mido_travel,int(seed.get("ship_id",-1)),cursor)
	if cursor in [24,26,28] and not sahi_entry.is_empty() and seed.station_id==sahi_entry.station_id and seed.system_id==sahi_entry.system_id:local_travel=Numbers.integer(station.get("planet_type"),0,bindings.opening_sky.planet_resources.near_textures.size()-1)
	if FreeFlight.Campaign.supported(bindings.mido_travel,cursor) and FreeFlight.available(bindings) and not FreeFlight.player_entry(bindings.mido_travel,int(seed.station_id),int(seed.get("ship_id",-1)),cursor).is_empty():local_travel=Numbers.integer(station.get("planet_type"),0,bindings.opening_sky.planet_resources.near_textures.size()-1)
	if load("res://src/content/local_arrival_environment_definitions.gd").location_supported(bindings,catalogues,int(seed.station_id),cursor):local_travel=true
	if station.get("planet_type")!=int(data.supported_planet_type) and not local_travel:return reject("This flight uses an unsupported planet layout")
	var index:=int(system.sky_index)
	var sky: Dictionary=bindings.opening_sky
	var result:=seed.duplicate(true)
	result.campaign_cursor=cursor;result.world_type=int(data.world_type)
	result.sky_index=index
	result.sky_parameters={"star_variants":int(sky.star_variants),"star_mesh_base":int(sky.star_mesh_base),
		"star_texture_base":int(sky.star_texture_base),"sky_mesh_id":int(data.sky_mesh_base)+index,"sky_texture_id":int(data.sky_texture_base)+index}
	result.current_planet_texture_id=int(sky.planet_resources.near_textures[int(station.planet_type)])
	return result

func resolve_combat_training(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, player_cache: Dictionary) -> Dictionary:
	error=""
	if bindings==null or catalogues==null or not equipment is Equipment or Training.flight(bindings).is_empty():return reject("Training requires its equipped ordinary location")
	if not equipment.requirements().satisfied:return reject("Training equipment is incomplete")
	var seed: Dictionary=equipment.snapshot().loadout
	if catalogues.content_id!=bindings.base_content_id or seed.get("base_content_id")!=bindings.base_content_id or seed.get("binding_id")!=bindings.binding_id or not Cache.matches(player_cache,seed,7):return reject("Training location belongs to another equipped player")
	if not Definitions.parameters(bindings.arrival_environment) or not SkyDefinitions.parameters(bindings.opening_sky) or not Planets.parameters(bindings.opening_sky.get("planet_resources",{})):return reject("Training requires its shared ordinary environment")
	for key in ["station_id","system_id"]:
		if seed.get(key)!=int(bindings.combat_training_story[key]):return reject("Training location changed")
	return _resolve(bindings,catalogues,seed,7)

func resolve_local_travel(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, player_cache: Dictionary) -> Dictionary:
	error=""
	if bindings==null or catalogues==null or not equipment is Equipment:return reject("Local travel requires its retained equipped player")
	if player_cache.get("campaign_cursor") in FlightStages.POST_SAHI:return resolve_post_sahi(bindings,catalogues,equipment,player_cache)
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false):return reject("Local travel requires the drill exchange")
	var seed: Dictionary=owned.loadout
	var cursor: Variant=player_cache.get("campaign_cursor")
	var ordinary: bool=FreeFlight.Campaign.supported(bindings.mido_travel,cursor) and FreeFlight.available(bindings) and not FreeFlight.player_entry(bindings.mido_travel,int(seed.station_id),int(seed.ship_id),cursor).is_empty()
	var entry: Dictionary=Cache.sahi_entry(bindings.mido_travel,int(seed.ship_id),cursor) if cursor is int and cursor in [24,28] else {}
	var sahi: bool=not entry.is_empty() and entry.station_id==seed.station_id and entry.system_id==seed.system_id
	if not cursor is int or (Travel.player_entry(bindings.mido_travel,int(seed.station_id),cursor).is_empty() and not (cursor==16 and seed.station_id==98 and not Cache.alioth_entry(bindings.mido_travel).is_empty()) and not ordinary and not sahi):return reject("This local location has no supported player entry")
	if catalogues.content_id!=bindings.base_content_id or seed.base_content_id!=bindings.base_content_id or seed.binding_id!=bindings.binding_id or not Cache.matches(player_cache,seed,cursor):return reject("Local travel cache belongs to another equipped location")
	if not Definitions.parameters(bindings.arrival_environment) or not SkyDefinitions.parameters(bindings.opening_sky) or not Planets.parameters(bindings.opening_sky.get("planet_resources",{})):return reject("Local travel requires the shared ordinary environment")
	return _resolve(bindings,catalogues,seed,cursor)

## The Void is not a catalogue row. Resolve its explicit source identity before
## any ordinary station/system indexing; its retained return remains Sahi9/48.
func resolve_post_sahi(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,player_cache: Dictionary) -> Dictionary:
	error=""
	if bindings==null or catalogues==null or not equipment is Equipment:return reject("Post-Sahi location requires retained equipped content")
	var owned: Dictionary=equipment.snapshot();var seed: Dictionary=owned.get("loadout",{})
	var cursor: Variant=player_cache.get("campaign_cursor")
	if not cursor is int or cursor not in FlightStages.POST_SAHI:return reject("Unsupported post-Sahi location")
	var entry:=Cache.post_sahi_entry(bindings.mido_travel,cursor,int(seed.get("ship_id",-1)))
	if entry.is_empty() or not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false):return reject("Post-Sahi location lacks its retained equipment transitions")
	if catalogues.content_id!=bindings.base_content_id or seed.get("base_content_id")!=bindings.base_content_id or seed.get("binding_id")!=bindings.binding_id or not Cache.matches(player_cache,seed,cursor):return reject("Post-Sahi cache belongs to another equipped location")
	if seed.station_id!=entry.station_id or seed.system_id!=entry.system_id:return reject("Post-Sahi cache selected another location")
	if cursor==26:return _resolve(bindings,catalogues,seed,cursor)
	var result:=seed.duplicate(true)
	result.merge({"campaign_cursor":cursor,"world_type":int(bindings.first_flight.world_type),"void_location":true,
		"sky_index":-1,"sky_parameters":bindings.mido_travel.post_sahi.void.sky.duplicate(true),"current_planet_texture_id":-1,
		"return_station_id":91 if cursor==29 else int(bindings.mido_travel.post_sahi.void.return_station_id),"return_system_id":18 if cursor==29 else int(bindings.mido_travel.post_sahi.void.return_system_id)},true)
	return result

func reject(message: String) -> Dictionary:
	error=message
	return {}
