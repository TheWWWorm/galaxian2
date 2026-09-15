extends RefCounted
## Acknowledged contract and capture stations before ordinary travel unlocks.
## Shares inventory, career and cache readers with the other station records.
const Station=preload("res://src/simulation/station_entry.gd")
const Ordinary=preload("res://src/content/ordinary_flight_definitions.gd")
const World=preload("res://src/content/contract_world_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")

func restore(a: RefCounted,opening: RefCounted,bindings: RefCounted,cat: RefCounted,library: RefCounted,data: Dictionary) -> RefCounted:
	var saved: Dictionary=data.station;var cursor: int=saved.campaign_cursor
	if cursor not in [13,14,16] or saved.get("return_visit")!=true or saved.get("source_marked_item_ids")!=[] or not Numbers.integer(saved.get("flight_elapsed_ms"),0,2147483647):return a.reject("The campaign checkpoint lost its acknowledged return")
	if not a._keys(data.career,a.CAREER_KEYS) or not a._required(data.career,a.CAREER_KEYS.filter(func(key):return key!="last_result")):return a.reject("The campaign checkpoint has incomplete career data")
	var equipment: RefCounted=opening.inventory(a,bindings,cat,data.inventory,cursor)
	if equipment==null:return null
	var locations: RefCounted=a._locations(bindings,cat,library,data.get("locations"))
	if locations==null:return null
	var contracts: RefCounted=a._career(bindings,cat,data.career,equipment,locations,cursor)
	if contracts==null:return null
	if data.career.result_serial>0 and not data.career.has("last_result"):return a.reject("The campaign checkpoint lost its last acknowledged result")
	var owned: Dictionary=equipment.snapshot();var career: Dictionary=contracts.snapshot()
	# The first lounge adds its initial debris statistic to ContractSession.
	# StationEntry acquires that field on its first poll/departure, so retain the
	# original station representation while comparing its equivalent zero value.
	var station_progress: Dictionary=saved.get("progress",{}).duplicate(true)
	if cursor==13 and not station_progress.has("debris_destroyed"):
		station_progress.debris_destroyed=int(bindings.early_contracts.junk_lifecycle.initial_debris_destroyed)
	for key in ["loadout","cargo","progress","completed_side_missions"]:
		var expected: Variant=owned[key] if key in ["loadout","cargo"] else career[key]
		var actual: Variant=station_progress if key=="progress" else saved.get(key)
		if actual!=expected:return a.reject("The campaign station differs from its retained "+key)
	if saved.get("cargo_cache_stale",false)!=false or not a._player_cache(bindings,cat,saved.get("player_cache"),owned.loadout,cursor):return a.reject("The campaign station lost its current cargo or player cache")
	var station:=Station.new()
	station._state=saved.duplicate(true);station._state.language=library.active_language
	station._rules=bindings.station_entry.duplicate(true);station._progress_rules=bindings.opening_handoff.duplicate(true)
	station._equipment=equipment;station._contracts=contracts
	var events:=[]
	if cursor==16:
		var rules: Dictionary=bindings.mido_travel.alioth_arrival
		if saved.get("convoy_arrival")!=true or saved.get("alioth_conversation_acknowledged")!=true or owned.loadout.station_id!=int(rules.station_id):return a.reject("The Alioth checkpoint skipped its capture conversation")
		var mission:={"kind":int(rules.next_kind),"station_id":int(rules.next_station_id),"reward":0,"bonus":0,"source_parameter":0}
		if saved.mission!=mission:return a.reject("The Alioth checkpoint changed its pending story")
		station._local_rules=rules.duplicate(true);events=rules.events
	else:
		if not Travel.navigation_mission(bindings.mido_travel,cursor,saved.mission) or not World.response_flags(bindings,saved.get("station_response_flags",{})):return a.reject("The campaign checkpoint changed its story or station responses")
		if saved.get("local_visit_acknowledged")!=true:return a.reject("The campaign checkpoint has an unacknowledged station visit")
		if cursor==14 and saved.get("contract_conversation_acknowledged")!=true:return a.reject("The convoy checkpoint skipped its earned story conversation")
		if saved.get("contract_station",false):
			station._return_rules=World.docking(bindings,int(owned.loadout.station_id),13 if saved.get("contract_conversation",false) else cursor)
		else:
			station._return_rules=Ordinary.station_return(bindings,12)
			if owned.loadout.station_id!=int(station._return_rules.get("station_id",-1)) or saved.get("delivery_acknowledged")!=true:return a.reject("The first lounge checkpoint changed its acknowledged arrival")
			events=station._return_rules.events
		if station._return_rules.is_empty():return a.reject("The campaign checkpoint has no supported docking rules")
		if cursor==14 and saved.get("contract_conversation",false):
			station._local_rules=bindings.mido_travel.contract_completion.duplicate(true)
			events=station._local_rules.events
	if events.is_empty():
		if saved.line_index!=0:return a.reject("The saved station retained an unknown conversation")
	else:
		station._lines=station._read_lines(bindings,library,events)
		if station._lines.is_empty():return a.reject(station.error)
		if saved.line_index!=station._lines.size()-1:return a.reject("The campaign conversation was not acknowledged through its final line")
	var departure: Dictionary=station.prepare_departure(bindings,cat) if cursor==16 else station.prepare_contract_departure(bindings,cat)
	if departure.is_empty():return a.reject(station.error)
	a.restored_locations=locations
	return station
