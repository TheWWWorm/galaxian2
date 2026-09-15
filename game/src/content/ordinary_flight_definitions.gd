extends RefCounted
## Shared context selection above the individual mission declaration readers.
const Attack=preload("res://src/content/alioth_population_definitions.gd")
const AttackReturn=preload("res://src/content/alioth_return_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const Alioth=preload("res://src/content/alioth_arrival_definitions.gd")
const AmbientCombat=preload("res://src/content/ambient_combat_definitions.gd")
const Mining=preload("res://src/content/full_hold_flight_definitions.gd")
const Training=preload("res://src/content/combat_training_story_definitions.gd")
const MiningStory=preload("res://src/content/full_hold_story_definitions.gd")
const MiningReturn=preload("res://src/content/full_hold_return_definitions.gd")
const FirstReturn=preload("res://src/content/station_return_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")

static func select(bindings: RefCounted, cursor: Variant) -> Dictionary:
	if bindings==null or not cursor is int:return {}
	if cursor in [10,11,12]:
		var trip:=Travel.journey(bindings.mido_travel,cursor)
		return {} if trip.is_empty() else Travel.flight(bindings,int(trip.from_station_id),cursor)
	return Training.flight(bindings) if cursor==7 else Mining.flight(bindings,cursor)

static func for_departure(bindings: RefCounted, entry: Dictionary) -> Dictionary:
	var rules:=select(bindings,entry.get("campaign_cursor"))
	if FreeFlight.ordinary_entry(bindings,entry):rules=FreeFlight.flight(bindings,int(entry.get("location",{}).get("station_id",-1)))
	if entry.get("campaign_cursor")==16:rules=Attack.flight(bindings,int(entry.get("location",{}).get("station_id",-1)))
	if entry.get("campaign_cursor")==14 and not ContractWorld.ordinary_entry(bindings,entry):rules=Convoy.flight(bindings,int(entry.get("location",{}).get("station_id",-1)))
	if ContractWorld.ordinary_entry(bindings,entry):rules=ContractWorld.flight(bindings,int(entry.get("location",{}).get("station_id",-1)),entry.campaign_cursor)
	if entry.get("campaign_cursor") in [10,11,12]:rules=Travel.flight(bindings,int(entry.get("location",{}).get("station_id",-1)),entry.campaign_cursor)
	if rules.is_empty() or entry.get("location",{}).get("station_id")!=int(rules.station_id):return {}
	var packet: Variant=entry.get("departure")
	if not packet is Dictionary:return {}
	for key in ["loadout","mission","progress"]:
		if not packet.get(key) is Dictionary:return {}
	return rules

static func briefing(bindings: RefCounted,cursor: Variant,ordinary_world:=false) -> Dictionary:
	if cursor==18:
		if not FreeFlight.available(bindings):return {}
		var shared:=MiningStory.briefing(bindings,2)
		if shared.is_empty():return {}
		shared.campaign_cursor=18;shared.mission_kind=-1;shared.events=[]
		shared.entry_release_ms=int(bindings.mido_travel.free_flight.launch_clear_after_ms)+1
		return shared
	if cursor==16:
		if Attack.flight(bindings).is_empty():return {}
		var shared:=MiningStory.briefing(bindings,2)
		if shared.is_empty():return {}
		shared.campaign_cursor=16;shared.mission_kind=4
		shared.events=bindings.mido_travel.alioth_attack.briefing_events.duplicate(true)
		return shared
	if cursor==14 and not ordinary_world:
		if Convoy.flight(bindings,79).is_empty():return {}
		var shared:=MiningStory.briefing(bindings,2)
		if shared.is_empty():return {}
		shared.campaign_cursor=14;shared.mission_kind=4
		shared.events=bindings.mido_travel.convoy_capture.briefing_events.duplicate(true)
		return shared
	if cursor==13 or (cursor==14 and ordinary_world):
		if not ContractWorld.supports(bindings,cursor):return {}
		var shared:=MiningStory.briefing(bindings,2)
		if shared.is_empty():return {}
		shared.campaign_cursor=cursor;shared.events=bindings.mido_travel.entry.briefing_events.duplicate(true)
		shared.entry_release_ms=int(bindings.mido_travel.entry.entry_release_ms)
		return shared
	if cursor in [10,11,12]:
		var shared:=MiningStory.briefing(bindings,2)
		if shared.is_empty() or select(bindings,cursor).is_empty():return {}
		shared.campaign_cursor=cursor;shared.mission_kind=11
		var entry: Dictionary=Travel.journey(bindings.mido_travel,cursor) if cursor in [11,12] else bindings.mido_travel.entry
		shared.events=entry.briefing_events.duplicate(true)
		shared.entry_release_ms=int(entry.entry_release_ms)
		return shared
	return Training.briefing(bindings) if cursor==7 else MiningStory.briefing(bindings,cursor)

static func objective(bindings: RefCounted,cursor: Variant) -> Dictionary:
	if cursor==16:
		var shared:=MiningStory.objective(bindings,2)
		if shared.is_empty() or Attack.flight(bindings).is_empty():return {}
		shared.campaign_cursor=16;shared.mission_kind=4;shared.station_id=98
		shared.required_cargo=0;shared.events=bindings.mido_travel.alioth_attack.completion_events.duplicate(true)
		shared.alioth_attack=true;shared.cursor_after_acknowledgement=17;shared.next_kind=11
		return shared
	if cursor==14:
		var shared:=MiningStory.objective(bindings,2)
		if shared.is_empty() or Convoy.flight(bindings,79).is_empty():return {}
		shared.campaign_cursor=14;shared.mission_kind=4;shared.station_id=79
		shared.required_cargo=0;shared.events=[];shared.capture_controlled=true
		return shared
	if cursor in [10,11,12]:
		var shared:=MiningStory.objective(bindings,2)
		if shared.is_empty() or select(bindings,cursor).is_empty():return {}
		shared.campaign_cursor=cursor;shared.mission_kind=11;shared.station_id=int(Travel.journey(bindings.mido_travel,cursor).station_id)
		shared.required_cargo=0;shared.events=[];shared.local_visit=true
		return shared
	return Training.objective(bindings) if cursor==7 else MiningStory.objective(bindings,cursor)

static func docking(bindings: RefCounted,cursor: Variant) -> Dictionary:
	if cursor==17:
		if not AttackReturn.available(bindings) or not FirstReturn.parameters(bindings.station_return):return {}
		var result: Dictionary=bindings.station_return.duplicate(true)
		result.merge(alioth_return_overlay(),true)
		return result
	if cursor in [10,11,12]:return Travel.station_return(bindings,cursor)
	if cursor!=8:return MiningReturn.select(bindings,cursor)
	if bindings==null or not Training.parameters(bindings.combat_training_story) or not FirstReturn.parameters(bindings.station_return):return {}
	var complete:=Training.station_return(bindings)
	if not complete.is_empty():return complete
	var result: Dictionary=bindings.station_return.duplicate(true)
	result.departing_cursor=7;result.campaign_cursor=8;result.minimum_delivered_cargo=0
	return result

static func docking_parameters(rules: Dictionary) -> bool:
	if rules.get("alioth_return",false):
		var original:=rules.duplicate(true)
		var overlay:=alioth_return_overlay()
		for key in overlay:
			if rules.get(key)!=overlay[key]:return false
			if FirstReturn.VALUES.has(key):original[key]=FirstReturn.VALUES[key]
			else:original.erase(key)
		return FirstReturn.parameters(original)
	if ContractWorld.docking_parameters(rules):return true
	if FreeFlight.docking_parameters(rules):return true
	if Travel.station_return_parameters(rules):return true
	if FirstReturn.parameters(rules) or MiningReturn.parameters(rules):return true
	if Training.station_return_parameters(rules):return true
	if rules.get("departing_cursor")!=7 or rules.get("campaign_cursor")!=8 or rules.get("minimum_delivered_cargo")!=0:return false
	var original:=rules.duplicate(true)
	for key in ["departing_cursor","campaign_cursor","minimum_delivered_cargo"]:original[key]=FirstReturn.VALUES[key]
	return FirstReturn.parameters(original)

static func station_return(bindings: RefCounted,cursor: Variant) -> Dictionary:
	if cursor==17:return docking(bindings,cursor)
	if cursor in [10,11,12]:return Travel.station_return(bindings,cursor)
	return Training.station_return(bindings) if cursor==8 else MiningReturn.select(bindings,cursor)

static func station_conversation(bindings: RefCounted,cursor: Variant) -> Dictionary:
	if cursor==17:
		var result:=station_return(bindings,cursor)
		if not result.is_empty():result.portraits=bindings.mido_travel.alioth_arrival.presentation.portraits.duplicate(true)
		return result
	if cursor==13:
		if bindings==null or not bindings.mido_travel.has("contract_completion") or not FirstReturn.parameters(bindings.station_return):return {}
		var result: Dictionary=bindings.station_return.duplicate(true)
		result.events=bindings.mido_travel.contract_completion.events.duplicate(true)
		return result
	if cursor==15:
		if not Alioth.available(bindings) or not FirstReturn.parameters(bindings.station_return):return {}
		var result: Dictionary=bindings.station_return.duplicate(true)
		result.events=bindings.mido_travel.alioth_arrival.events.duplicate(true)
		result.portraits=bindings.mido_travel.alioth_arrival.presentation.portraits.duplicate(true)
		return result
	# A conversation following a station reload has no new docking transition.
	# Share navigation and voice preparation without extending docking permission.
	if cursor!=9:return station_return(bindings,cursor)
	if bindings==null or not Travel.parameters(bindings.mido_travel) or not FirstReturn.parameters(bindings.station_return):return {}
	var result: Dictionary=bindings.station_return.duplicate(true)
	result.events=bindings.mido_travel.conversations[0].events.duplicate(true)
	return result

static func combat_population(bindings: RefCounted, combat: Dictionary) -> bool:
	return Attack.combat_population(bindings,combat) or Convoy.combat_population(bindings,combat) or Travel.combat_population(bindings,combat) or AmbientCombat.live_population(bindings,combat) or ContractWorld.combat_population(bindings,combat)

static func alioth_return_overlay() -> Dictionary:
	var source: Dictionary=AttackReturn.VALUES
	return {"alioth_return":true,"departing_cursor":int(source.departing_cursor),"campaign_cursor":int(source.campaign_cursor),
		"station_id":int(source.station_id),"system_id":int(source.system_id),"minimum_delivered_cargo":0,"restricted_mission_kind":4,
		"clear_cargo_after_acknowledgement":false,"cursor_after_acknowledgement":int(source.next_cursor),
		"next_mission_kind":int(source.next_kind),"next_mission_parameter":int(source.source_parameter),
		"next_station_id":int(source.next_station_id),"events":source.events.duplicate(true)}
