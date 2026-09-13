extends RefCounted
## Detached second-trip construction. Live pirate behavior and mission dialogue
## require separate verified owners before this flight is offered to players.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const First=preload("res://src/content/first_flight_definitions.gd")
const Departure=preload("res://src/content/full_hold_departure_definitions.gd")
const NPC=preload("res://src/content/npc_construction_definitions.gd")
const Route=preload("res://src/content/npc_route_definitions.gd")
const World=preload("res://src/content/opening_world_initialization_definitions.gd")
const VALUES := {"scope":"full_hold_mining_flight_construction","campaign_cursor":4,"world_type":3,"mission_kind":154,"station_id":78,"system_id":15,"requires_ordinary_location":true,"requires_empty_companions":true,"requires_default_placement":true,"environment_reseed_before_yaw":true,"environment_object_resource_id":16994,"environment_object_position_bounds":[80000,40000,40000],"environment_object_position_offsets":[-40000,-20000,40000],"player_position":[10,10,10000],"yaw_units":1600,"angle_fraction":1.52587890625e-05,"angle_tau":6.2831854820251465,"yaw_zero_means_positive":true,"camera_axis_base":500,"camera_axis_bound":2000,"camera_z":9000,"camera_zero_means_negative":true,"actor_count":1,"weapon_item_sequence":[0,19],"weapon_effect_sequence":[14600,14605],"entry_release_ms":7001,"briefing_minimum_ms":5001,"briefing_requires_entry_release":true,"actor_kind":8,"hull_catalogue_id":2,"subtype":0,"actor_position":[0,0,-200000],"actor_mode":5,"actor_active":false,"actor_targeting_blocked":true,"retains_generated_cargo":true,"retains_generated_route":true,"weapon_effect_capacity":4,"weapon_effect_random_bound":2,"zero_means_flipped":true}
const SPANS := {"actor_dispatch":[315,256],"actor_position_z":[1575338,4],"ordinary_field_center":[-35306,796],"route_and_cargo":[605172,2070],"placement_virtual":[2399834,8],"world_order":[-44096,2458],"factory":[77944,3478],"inactive_mode":[-78898,44],"activity":[-78836,36],"activity_field":[540910,14],"hostile":[535624,28],"position_setter":[609228,176],"weapons":[54772,4266],"extra_story":[51826,1046]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func flight(bindings: RefCounted, cursor: Variant) -> Dictionary:
	if bindings==null or not cursor is int:return {}
	if cursor==2 and First.parameters(bindings.first_flight):return bindings.first_flight
	if cursor==4 and parameters(bindings.full_hold_flight):return bindings.full_hold_flight
	return {}

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, departure: Dictionary, first: Dictionary, actors: Dictionary) -> String:
	if not data is Dictionary:return "Missing second-flight construction declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported second-flight construction declarations"
	if not Departure.parameters(departure) or not First.parameters(first):return "Second flight lacks its departure or ordinary flight context"
	var initial: Dictionary=actors.get("npc_initialization",{})
	if not NPC.parameters(initial.get("construction")) or not Route.parameters(initial.get("routes")) or not World.parameters(initial.get("world_initialization")):return "Second flight lacks shared NPC construction"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Second flight lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid second-flight provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid second-flight extent: "+key
	return ""
