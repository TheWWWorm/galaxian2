extends RefCounted
## Shared ordinary world setup using imported contract and flight declarations.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const FirstFlight=preload("res://src/content/first_flight_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Return=preload("res://src/content/station_return_definitions.gd")
const VALUES = {"scope":"mido_contract_world_initialization","campaign_cursor":13,"impact_models":[{"item_id":0,"resource_id":14600},{"item_id":3,"resource_id":14601},{"item_id":7,"resource_id":14603},{"item_id":19,"resource_id":14605},{"item_id":22,"resource_id":14606},{"item_id":25,"resource_id":14606}]}
const SPANS = {"contract_world_impact_0":[1572842,4],"contract_world_impact_3":[1572854,4],"contract_world_impact_7":[1572870,4],"contract_world_impact_19":[1572918,4],"contract_world_impact_22":[1572930,4],"contract_world_impact_25":[1572942,4]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

# Native helpers.
static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.early_contracts.get("world_initialization")) and bindings.early_contracts.has("junk_lifecycle") and FirstFlight.parameters(bindings.first_flight) and Travel.navigation_available(bindings.mido_travel,13)

static func supports(bindings: RefCounted,cursor: Variant) -> bool:
	return available(bindings) and cursor is int and Travel.navigation_available(bindings.mido_travel,cursor)

static func ordinary_entry(bindings: RefCounted,entry: Dictionary) -> bool:
	return supports(bindings,entry.get("campaign_cursor")) and entry.get("scenery",{}).get("world_initialization",{}).has("contract_context")

static func flight(bindings: RefCounted,station_id: int,cursor:=13) -> Dictionary:
	if not supports(bindings,cursor) or Travel.navigation_stations(bindings.mido_travel,cursor,station_id).is_empty():return {}
	var result: Dictionary=bindings.first_flight.duplicate(true)
	result.scope="mido_ordinary_contract_flight";result.campaign_cursor=cursor;result.station_id=station_id
	# Population selection uses the retained side slot at this station. The
	# pending story objective remains a separate owner throughout the flight.
	result.erase("mission_kind");result.erase("actor_count")
	return result

static func impact_model(bindings: RefCounted,item_id: int) -> int:
	if not available(bindings):return -1
	for row in bindings.early_contracts.world_initialization.impact_models:
		if int(row.item_id)==item_id:return int(row.resource_id)
	return -1

static func response_flags(bindings: RefCounted,flags: Variant) -> bool:
	if not available(bindings) or not flags is Dictionary or flags.is_empty():return false
	for station in flags:
		if not station is int or not flags[station] is bool or Travel.navigation_stations(bindings.mido_travel,13,station).is_empty():return false
	return true

static func docking(bindings: RefCounted,station_id: int,cursor:=13) -> Dictionary:
	if flight(bindings,station_id,cursor).is_empty() or not Return.parameters(bindings.station_return):return {}
	return _docking_values(station_id,cursor)

static func _docking_values(station_id: int,cursor: int) -> Dictionary:
	var result:={"scope":"mido_contract_station","campaign_cursor":cursor,"station_id":station_id,
		"minimum_delivered_cargo":0,"local_visit":true,"contract_station":true}
	for key in ["system_id","source_state","contact_radius","cache_truncates"]:result[key]=Return.VALUES[key]
	return result

static func docking_parameters(data: Dictionary) -> bool:
	var station: Variant=data.get("station_id")
	return station is int and station in [75,76,77,78,79] and data.get("campaign_cursor") in [13,14] and Equal.equal_value(data,_docking_values(station,data.campaign_cursor))

static func combat_population(bindings: RefCounted,combat: Dictionary) -> bool:
	if not supports(bindings,combat.get("campaign_cursor")):return false
	var source: Dictionary=combat.get("contract_encounter",{})
	var context: Dictionary=source.get("context",{})
	var actors: Variant=combat.get("actors")
	if not actors is Array or source.get("actor_count")!=actors.size() or source.get("mission",{})!=context.get("mission"):return false
	for key in ["base_content_id","binding_id"]:
		if combat.get(key)!=bindings.get(key) or context.get(key)!=bindings.get(key):return false
	if context.get("campaign_cursor")!=combat.campaign_cursor or flight(bindings,int(context.get("station_id",-1)),combat.campaign_cursor).is_empty():return false
	var kind: Variant=source.get("kind")
	if kind!=context.mission.get("kind") or kind not in [4,7,12]:return false
	if (kind==4 and actors.size() not in [2,3,4]) or (kind==7 and actors.size() not in [17,19]) or (kind==12 and actors.size()!=4):return false
	var hulls: Dictionary=bindings.early_contracts.encounter_construction.hulls
	for id in actors.size():
		var actor: Variant=actors[id]
		if not actor is Dictionary or actor.get("actor_id")!=id:return false
		if kind==7:
			if actor.get("population_group")!="debris" or actor.get("actor_kind")!=-1 or actor.get("hull_catalogue_id")!=-1:return false
		else:
			var rival: bool=kind==12 and id==0
			var hull: Variant=actor.get("hull_catalogue_id")
			var faction: Variant=context.get("client_faction") if rival else 8
			if actor.get("population_group")!=("rival" if rival else "pirate") or actor.get("actor_kind")!=faction:return false
			if not hull is int or hull<0 or hull>=hulls.factions.size() or int(hulls.factions[hull])!=faction:return false
	return true

static func empty_population(bindings: RefCounted,world: Dictionary,rank: Variant,difficulty: Variant) -> Dictionary:
	if not available(bindings) or not rank is int or rank<0 or rank>=bindings.opening_handoff.rank_thresholds.size() or difficulty not in [0.5,1.0]:return {}
	for key in ["base_content_id","binding_id"]:
		if world.get(key)!=bindings.get(key):return {}
	var generated: Dictionary=world.get("npc_construction",{})
	var context: Dictionary=world.get("contract_context",{})
	var encounter: Dictionary=generated.get("contract_encounter",{})
	if not supports(bindings,world.get("campaign_cursor")) or context.get("campaign_cursor")!=world.campaign_cursor or context.get("station_id")!=world.get("station_id") or context.get("rank")!=rank or context.get("difficulty")!=difficulty:return {}
	if context.get("mission",{}).get("kind")!=0 or encounter.get("context")!=context or encounter.get("actor_count")!=0 or generated.get("actors")!=[] or world.get("weapon_effects")!=[] or world.get("random_state")!=generated.get("random_state"):return {}
	if flight(bindings,int(context.station_id),context.campaign_cursor).is_empty():return {}
	var result: Dictionary=bindings.combat_training_control.duplicate(true)
	result.merge({"scope":"mido_contract_empty_population","campaign_cursor":context.campaign_cursor,"station_id":int(context.station_id),
		"actor_count":0,"actor_kinds":[],"hull_catalogue_ids":[],"target_memberships":[],"player_weapon_targets":[],
		"supported_ranks":range(bindings.opening_handoff.rank_thresholds.size())},true)
	return result
