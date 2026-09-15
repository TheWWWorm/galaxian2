extends RefCounted
## Source population parameters; this is not a mission-unlock permission.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const VALUES = {"scope":"early_mido_ordinary_population","system_id":15,"actor_kind":3,"supported_difficulties":[0.5,1.0],"contexts":[{"station_id":78,"campaign_cursor":10,"mixed":false},{"station_id":79,"campaign_cursor":11,"mixed":true}],"requires_default_completed_mission":true,"mission_kind":-1,"mission_story":false,"requires_empty_companions":true,"station_response":false,"group_order":["patrol","travel","freighter"],"travel_count_bound":2,"freighter_count_bound":5,"extra_patrol_count_bound":2,"freighters_per_patrol":4,"travel_ship":{"subtype":0,"factory_origin":[0,0,0],"route_bounds":[400000,200000,100000],"route_offsets":[-200000,-100000,50000],"route_loop":false,"flight_mode":4,"travel_flag":true},"freighter":{"subtype":1,"hull_catalogue_id":15,"faction_draw_bound":100,"position_x_bound":60000,"position_x_offset":-80000,"position_sign_bound":2,"position_y_bound":40000,"position_y_offset":-20000,"position_z_bound":160000,"position_z_offset":-80000,"cargo_multiplier_bound":4,"cargo_multiplier_offset":2,"cargo_floor_bound":5,"cargo_floor_offset":8,"has_generated_patrol_route":false,"world_flag":true,"assembly":{"root_model_id":17049,"light_model_id":17055,"engine_model_id":17054,"container_model_id":17052,"container_lod_model_id":17053,"container_count_bound":4,"container_positions_z":[-2150.0,2150.0,4300.0],"lod_model_id":17050,"lod_distance":35000}}}
const SPANS = {"population_counts":[-30330,215],"empty_fallback":[-29088,121],"group_order":[-24575,244],"travel_ship":[-23123,248],"travel_route":[-77698,104],"travel_mode":[-77334,26],"travel_flag":[-79064,14],"freighter_choice_and_spawn":[-22069,300],"freighter_constructor":[78543,170],"freighter_cargo":[631998,210],"freighter_assembly":[-218774,635],"first_container_position":[1557778,4],"remaining_container_positions":[1557866,8]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant,source_bytes: int,arch: String,arrival: Dictionary,travel: Dictionary) -> String:
	if not data is Dictionary:return "Missing ambient population declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Travel.parameters(travel):return "Unsupported ambient population declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Ambient population lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid ambient population provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid ambient population extent: "+key
	return ""

static func maximum_actor_count(data: Dictionary,common: Dictionary) -> int:
	var maximum:=int(data.travel_count_bound)-1+int(data.freighter_count_bound)-1+int(data.extra_patrol_count_bound)-1+int(common.actor_count_bound)-1
	@warning_ignore("integer_division")
	maximum+=(int(data.freighter_count_bound)-1)/int(data.freighters_per_patrol)
	return maxi(maximum,int(common.empty_population_fallback))

static func contexts(bindings: RefCounted) -> Array:
	if bindings==null or not parameters(bindings.ambient_population):return []
	var result: Array=bindings.ambient_population.contexts.duplicate(true)
	var trip:=Travel.journey(bindings.mido_travel,12)
	if not trip.is_empty():result.append({"station_id":int(trip.from_station_id),"campaign_cursor":12,"mixed":true})
	if ContractWorld.available(bindings):
		for cursor in [13,14]:
			if not ContractWorld.supports(bindings,cursor):continue
			for station in bindings.mido_travel.contract_navigation.station_ids:
				result.append({"station_id":int(station),"campaign_cursor":cursor,"mixed":true})
	return result

static func assembly_matches(data: Dictionary,assembly: Variant) -> bool:
	if not parameters(data) or not assembly is Dictionary:return false
	var expected: Dictionary=data.freighter.assembly
	if assembly.size()!=expected.size()+1:return false
	for key in expected:
		if not Equal.equal_value(assembly.get(key),expected[key]):return false
	var count: Variant=assembly.get("container_count")
	return count is int and count>=0 and count<int(expected.container_count_bound)
