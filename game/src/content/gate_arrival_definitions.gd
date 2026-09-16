extends RefCounted
## Original gate entry permissions, retained values and career increment.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"ordinary_gate_arrival","career":{"initial_jumpgates_used":0,"jump_increment":1,"counter_text_id":553},"departure":{"speed_units_per_ms":2.0,"damage_allowed":false,"collision_enabled":false,"boost_enabled":false,"primary_reset_category":0,"confirmation_resets_primary":true,"map_resets_primary":false},"arrival":{"audio_selector":1,"special_arrival":true,"clear_pending_course":true}}
const SPANS = {"gate_arrival_initial_counter":[880642,120],"gate_arrival_counter_set":[875422,12],"gate_arrival_counter_increment":[875434,12],"gate_arrival_counter_get":[875446,12],"gate_arrival_counter_label":[893511,39],"gate_arrival_load_counter":[-652839,12],"gate_arrival_commit":[382634,269],"gate_arrival_player_permission":[359888,31],"gate_arrival_damage_setter":[537626,14],"gate_arrival_damage_guard":[537770,90],"gate_arrival_shield_guard":[537886,112],"gate_arrival_player_reset":[360259,41],"gate_arrival_collision_setter":[559626,14],"gate_arrival_speed_reset":[558846,102],"gate_arrival_primary_reset":[600746,16],"gate_arrival_primary_category":[542090,82],"gate_arrival_confirmation_reset":[350737,32],"gate_arrival_map_accept":[351105,31],"gate_arrival_map_cleanup":[351443,46]}

# Native composition.
const Worlds=preload("res://src/content/ordinary_world_definitions.gd")

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("gate_arrival")) and Worlds.available(bindings) and load("res://src/content/gate_transit_definitions.gd").available(bindings)

static func route(data: Dictionary,from_station: Variant,to_station: Variant) -> Dictionary:
	if not parameters(data.get("gate_arrival")):return {}
	var origin:=Worlds.location(data,from_station);var destination:=Worlds.location(data,to_station)
	if origin.is_empty() or destination.is_empty() or origin.system_id==destination.system_id or origin.station_id!=origin.gate_station_id:return {}
	return {"from_station_id":origin.station_id,"from_system_id":origin.system_id,
		"station_id":destination.station_id,"system_id":destination.system_id}

static func packet(bindings: RefCounted,catalogues: RefCounted,request: Dictionary,cursor: int=18) -> Dictionary:
	if not available(bindings) or not load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,cursor) or request.size()!=4:return {}
	for key in ["base_content_id","binding_id"]:
		if request.get(key)!=bindings.get(key):return {}
	var trip:=route(bindings.mido_travel,request.get("from_station_id"),request.get("destination_station_id"))
	if trip.is_empty():return {}
	if catalogues==null or not catalogues.tables.systems[trip.from_system_id].linked_system_ids.has(trip.system_id):return {}
	for id in [trip.from_station_id,trip.station_id]:
		if Worlds.catalogue_location(bindings,catalogues,id).is_empty():return {}
	var result:=trip.duplicate()
	result.merge({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":cursor,"source_state":int(bindings.mido_travel.travel.source_state),
		"world_type":int(bindings.mido_travel.travel.world_type),"audio_selector":int(bindings.mido_travel.gate_arrival.arrival.audio_selector)})
	return result

static func packet_matches(bindings: RefCounted,catalogues: RefCounted,arrival: Dictionary) -> bool:
	var expected:=packet(bindings,catalogues,{"base_content_id":arrival.get("base_content_id"),"binding_id":arrival.get("binding_id"),
		"from_station_id":arrival.get("from_station_id"),"destination_station_id":arrival.get("station_id")},int(arrival.get("campaign_cursor",-1)))
	if expected.is_empty() or arrival!=expected:return false
	for key in expected:
		if typeof(arrival[key])!=typeof(expected[key]):return false
	return true

static func valid_statistics(statistics: Variant) -> bool:
	return statistics is Dictionary and statistics.size()==1 and load("res://src/content/opening_definitions.gd").integer(statistics.get("jumpgates_used"),0,2147483647)
