extends RefCounted
## Shared native support for verified ordinary locations.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const PostSahi=preload("res://src/content/post_sahi_definitions.gd")
const Thynome=preload("res://src/content/thynome_expedition_definitions.gd")
const VALUES = {"scope":"ordinary_world_planet_guard","special_planets":{"station_ids":[120,126,130,132],"size_units":26000}}
const SPANS = {"ordinary_world_special_planet":[872426,80],"ordinary_world_station_equality":[853288,22],"ordinary_world_station_id":[851352,10],"ordinary_world_special_size":[843373,59]}

# Native composition.
# This is a native implementation support boundary, not imported progression.
# Catalogue rows and all resources are checked before constructing a location.
const SYSTEMS={
	1:{"system_id":1,"station_ids":[5,6,7,8,9],"planet_types":[3,10,14,13,17],"faction":0,"security":1,"gate_station_id":5,"sky_index":2},
	2:{"system_id":2,"station_ids":[30,31,32,33],"planet_types":[1,8,13,9],"station_models":[6,4,6,4],"system_fields":[1,1,2,24,40,73,30,9],"system_arrays":[[8,11,21],[30,31,32,33],[0,8,9,17],[0,1,2]],"faction":2,"security":1,"gate_station_id":30,"sky_index":9},
	8:{"system_id":8,"station_ids":[40,41,42,43,44],"planet_types":[16,2,13,19,10],"faction":0,"security":2,"gate_station_id":40,"sky_index":1},
	6:{"system_id":6,"station_ids":[10],"planet_types":[9],"faction":0,"security":3,"gate_station_id":10,"sky_index":0},
	7:{"system_id":7,"station_ids":[35,36,37,38,39],"planet_types":[6,16,11,9,18],"faction":0,"security":1,"gate_station_id":35,"sky_index":7},
	9:{"system_id":9,"station_ids":[45,46,47,48,49],"planet_types":[3,12,17,0,14],"station_models":[3,6,7,8,1],"system_fields":[2,1,2,39,29,63,45,7],"system_arrays":[[10,10,10],[45,46,47,48,49],[2,11,17,19,26],[0,1,2]],"faction":2,"security":2,"gate_station_id":45,"sky_index":7},
	11:{"system_id":11,"station_ids":[55,56,57],"planet_types":[4,15,6],"faction":0,"security":2,"gate_station_id":55,"sky_index":3},
	19:{"system_id":19,"station_ids":[95,96,97,98,99],"planet_types":[3,8,14,12,6],"faction":0,"security":3,"gate_station_id":95,"sky_index":6},
	18:{"system_id":18,"station_ids":[90,91,92,93,94],"planet_types":[1,4,14,17,5],"station_models":[7,4,2,2,5],"system_fields":[1,1,0,43,85,81,90,1],"system_arrays":[[14,10,20],[90,91,92,93,94],[1,8],[0,1,2]],"faction":0,"security":1,"gate_station_id":90,"sky_index":1},
	14:{"system_id":14,"station_ids":[70,71,72,73,74],"planet_types":[13,7,5,9,16],"faction":0,"security":3,"gate_station_id":70,"sky_index":5},
}

const MAC_SPANS = {"ordinary_world_special_planet":[873058,80],"ordinary_world_station_equality":[853920,22],"ordinary_world_station_id":[851984,10],"ordinary_world_special_size":[844005,59]}

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("ordinary_worlds")) and load("res://src/content/local_arrival_environment_definitions.gd").available(bindings)

static func location(data: Dictionary,station_id: Variant) -> Dictionary:
	if not station_id is int or not data.has("free_population"):return {}
	for id in SYSTEMS:
		if id in [1,6,7,8] and not load("res://src/content/free_campaign_definitions.gd").chapter_available(data):continue
		if id==11 and not load("res://src/content/suttnar_visit_definitions.gd").parameters(data.get("suttnar_visit")):continue
		if id==9 and not PostSahi.parameters(data.get("post_sahi",{})):continue
		if id in [2,18] and not Thynome.coherent(data):continue
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
	if world.system_id in [1,8] and not load("res://src/content/persistent_contact_definitions.gd").available(bindings):return {}
	var systems: Array=catalogues.tables.systems;var stations: Array=catalogues.tables.stations
	if world.system_id>=systems.size():return {}
	var system: Dictionary=systems[world.system_id]
	var rules: Dictionary=bindings.mido_travel.free_population
	if Array(system.station_ids)!=world.station_ids or system.sky_index!=world.sky_index:return {}
	if world.has("system_fields"):
		if Array(system.fields)!=world.system_fields or system.arrays.size()!=world.system_arrays.size():return {}
		for index in world.system_arrays.size():
			if Array(system.arrays[index])!=world.system_arrays[index]:return {}
	if system.fields[int(rules.security_field)]!=world.security or system.fields[int(rules.faction_field)]!=world.faction:return {}
	if system.fields[int(bindings.mido_travel.free_navigation.gate_station_field)]!=world.gate_station_id:return {}
	for index in world.station_ids.size():
		var id: int=world.station_ids[index]
		if id>=stations.size() or stations[id].system_id!=world.system_id or stations[id].planet_type!=world.planet_types[index]:return {}
		if world.has("station_models") and stations[id].fields[2]!=world.station_models[index]:return {}
	return world
