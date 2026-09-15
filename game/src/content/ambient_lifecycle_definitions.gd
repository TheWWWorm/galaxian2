extends RefCounted
## Original small-ship launch, route and departure rules. No mission-unlock permission.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Combat=preload("res://src/content/ambient_combat_definitions.gd")
const VALUES = {"scope":"early_mido_small_traffic_lifecycle","campaign_cursor":11,"station_id":79,"system_id":15,"actor_kind":3,"subtype":0,"initial_mode":4,"initial_active":false,"launch_check_after_ms":10000,"launches_per_check":1,"launch_mode":1,"launch_origin":[0,0,0],"launch_preserves_axes":true,"launch_regenerates_cargo":true,"launch_resets_route":true,"launch_preserves_selection_boost_clocks":true,"departure_after_route_ms":20000,"departure_mode":6,"departure_speed_multiplier":1.100000023841858,"park_above_speed":100.0,"departure_updates_statistics_pose":false,"departure_updates_bank":false,"parked_clock_limit_ms":60000}
const SPANS = {"park":[-77334,26],"parked_predicate":[-77838,16],"travel_predicate":[-79050,14],"relaunch":[630620,488],"restore_statistics":[535818,164],"reset_route":[722150,60],"periodic_check":[112696,186],"ordinary_timer_entry":[112550,21],"world_schedule":[117678,71],"actor_timers":[610806,75],"route_clock":[616728,87],"outbound":[619552,130],"mode_table":[627906,40],"multiplier":[1557770,4],"speed_limit":[1556926,4]}

const RECYCLING = {"patrol_check_after_ms":45000,"patrol_launch_all_inactive":true,"killed_small_ships_recycle":true,"freighters_recycle":false,"initial_world_clocks_ms":0,"launch_statistics_from_root":true}
const RECYCLING_SPANS = {"patrol_check":[112882,327],"patrol_iteration":[113730,22],"initial_clocks":[-45856,11],"initial_travel_flag":[-81071,7],"freighter_reset_dispatch":[2399978,8],"freighter_no_reset":[-76880,6],"launch_position":[609228,176]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+(2 if data.has("recycling") else 1) or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return not data.has("recycling") or Equal.equal_value(data.recycling,RECYCLING)

static func recycling_parameters(data: Variant) -> bool:
	return parameters(data) and data.has("recycling")

static func validate(data: Variant,source_bytes: int,arch: String,arrival: Dictionary,combat: Dictionary) -> String:
	if not data is Dictionary:return "Missing ambient lifecycle declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Combat.parameters(combat):return "Unsupported ambient lifecycle declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Ambient lifecycle lacks its source anchor"
	var spans:=SPANS.duplicate()
	if data.has("recycling"):spans.merge(RECYCLING_SPANS)
	if data.provenance.size()!=spans.size():return "Invalid ambient lifecycle provenance"
	for key in spans:
		var span: Variant=data.provenance.get(key);var rule: Array=spans[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid ambient lifecycle extent: "+key
	return ""

static func guidance(bindings: RefCounted,packet: Dictionary,rank: Variant,difficulty: Variant) -> Dictionary:
	if bindings==null or not parameters(bindings.ambient_lifecycle):return {}
	var population:=Combat.population(bindings,packet,rank,difficulty)
	if population.is_empty():return {}
	var result: Dictionary=bindings.combat_training_control.duplicate(true)
	result.merge(bindings.mido_travel.traffic_control,true)
	result.scope="early_mido_ambient_guidance";result.station_id=int(population.station_id)
	result.campaign_cursor=int(population.campaign_cursor);result.actor_count=population.actor_count
	if population.has("free_traffic"):
		result.free_traffic=population.free_traffic.duplicate(true);result.scope="augmenta_ordinary_guidance"
		result.player_ship_id=int(packet.player_ship_id)
	result.actor_kinds=[];result.hull_catalogue_ids=[];result.target_memberships=[]
	for actor in packet.actors:
		result.actor_kinds.append(int(actor.actor_kind));result.hull_catalogue_ids.append(int(actor.hull_catalogue_id))
		var targets:=[int(result.player_target_id)]
		if population.has("free_traffic"):
			for other in packet.actors:
				if other.actor_kind!=actor.actor_kind:targets.append(other.actor_id)
		result.target_memberships.append(targets)
	return result
