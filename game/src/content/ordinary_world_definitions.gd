extends RefCounted
## Shared native support for verified ordinary locations.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"ordinary_world_planet_guard","special_planets":{"station_ids":[120,126,130,132],"size_units":26000}}
const SPANS = {"ordinary_world_special_planet":[872426,80],"ordinary_world_station_equality":[853288,22],"ordinary_world_station_id":[851352,10],"ordinary_world_special_size":[843373,59]}

# Native composition.
# This is a native implementation support boundary, not imported progression.
# Catalogue rows and all resources are checked before constructing a location.
const SYSTEMS={
	11:{"system_id":11,"station_ids":[55,56,57],"planet_types":[4,15,6],"faction":0,"security":2,"gate_station_id":55,"sky_index":3},
	19:{"system_id":19,"station_ids":[95,96,97,98,99],"planet_types":[3,8,14,12,6],"faction":0,"security":3,"gate_station_id":95,"sky_index":6},
	14:{"system_id":14,"station_ids":[70,71,72,73,74],"planet_types":[13,7,5,9,16],"faction":0,"security":3,"gate_station_id":70,"sky_index":5},
}

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("ordinary_worlds")) and load("res://src/content/local_arrival_environment_definitions.gd").available(bindings)

static func location(data: Dictionary,station_id: Variant) -> Dictionary:
	if not station_id is int or not data.has("free_population"):return {}
	for id in SYSTEMS:
		if id==11 and not load("res://src/content/suttnar_visit_definitions.gd").parameters(data.get("suttnar_visit")):continue
		if id!=19 and not parameters(data.get("ordinary_worlds")):continue
		var world: Dictionary=SYSTEMS[id]
		var index: int=world.station_ids.find(station_id)
		if index<0:continue
		if VALUES.special_planets.station_ids.has(station_id):return {}
		var result:=world.duplicate(true)
		result.station_id=station_id;result.planet_type=int(world.planet_types[index])
		return result
	return {}

static func catalogue_location(bindings: RefCounted,catalogues: RefCounted,station_id: Variant) -> Dictionary:
	if bindings==null or catalogues==null or catalogues.content_id!=bindings.base_content_id:return {}
	var world:=location(bindings.mido_travel,station_id)
	if world.is_empty():return {}
	var systems: Array=catalogues.tables.systems;var stations: Array=catalogues.tables.stations
	if world.system_id>=systems.size():return {}
	var system: Dictionary=systems[world.system_id]
	var rules: Dictionary=bindings.mido_travel.free_population
	if Array(system.station_ids)!=world.station_ids or system.sky_index!=world.sky_index:return {}
	if system.fields[int(rules.security_field)]!=world.security or system.fields[int(rules.faction_field)]!=world.faction:return {}
	if system.fields[int(bindings.mido_travel.free_navigation.gate_station_field)]!=world.gate_station_id:return {}
	for index in world.station_ids.size():
		var id: int=world.station_ids[index]
		if id>=stations.size() or stations[id].system_id!=world.system_id or stations[id].planet_type!=world.planet_types[index]:return {}
	return world
