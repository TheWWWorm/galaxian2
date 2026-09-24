extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Construction at the first mining departure; later travel has separate context.
const Values=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Departure=preload("res://src/content/station_departure_definitions.gd")
const EnvironmentDefinitions=preload("res://src/content/arrival_environment_definitions.gd")
const World=preload("res://src/content/arrival_world_initialization_definitions.gd")
const VALUES := {"scope":"first_mining_flight_construction","campaign_cursor":2,"world_type":3,"mission_kind":154,"station_id":78,"system_id":15,"requires_ordinary_location":true,"requires_empty_companions":true,"requires_default_placement":true,"environment_reseed_before_yaw":true,"environment_object_resource_id":16994,"environment_object_position_bounds":[80000,40000,40000],"environment_object_position_offsets":[-40000,-20000,40000],"player_position":[10,10,10000],"yaw_units":1600,"angle_fraction":1.52587890625e-05,"angle_tau":6.2831854820251465,"yaw_zero_means_positive":true,"camera_axis_base":500,"camera_axis_bound":2000,"camera_z":9000,"camera_zero_means_negative":true,"actor_count":0,"weapon_item_sequence":[],"weapon_effect_sequence":[],"entry_release_ms":7001,"briefing_minimum_ms":5001,"briefing_requires_entry_release":true}
const SPANS := {"world_player_stage":[-43105,47],"ordinary_position":[-42517,72],"position_setter":[562862,42],"yaw_selection":[-37697,51],"yaw_application":[-36983,63],"position_xy":[1557090,4],"position_z":[1572194,4],"angle_fraction":[1575014,4],"angle_tau":[1575058,4],"camera_random":[129177,233],"camera_z":[1575106,4],"camera_pose":[134731,240],"controller_flags":[121650,55],"controller_release":[151038,144],"briefing_time_gate":[375756,79],"briefing_controller_gate":[385218,20],"world_zero_start":[-46499,7],"world_zero_end":[-45884,10],"world_story_gate":[-42091,62],"story_actor_dispatch":[-112,124],"empty_actor_radio":[50503,35],"world_post_groups":[-42029,135],"empty_npc_membership":[59086,28],"empty_npc_result":[59632,14],"empty_hostile_count":[-41894,20],"no_npc_weapons":[55113,16],"equipment_population":[-32684,30],"extra_story_station":[51842,55],"extra_story_cursor":[52351,24],"equipment_escort":[52890,37],"attached_actor_gate":[53353,28],"companion_gate":[53816,24],"camera_constructor_arguments":[337943,28],"camera_initial_view":[903690,321],"opening_placement_reset":[143248,15],"environment_reseed_gate":[-38226,28],"early_wormhole_gate":[-37949,77],"early_wormhole_position":[-37872,122],"wormhole_constructor":[655150,155],"wormhole_body":[640998,171],"wormhole_position_body":[641364,147],"time_reseed":[1120906,61],"yaw_model_mode":[-725159,7],"yaw_model_setter":[-723518,114],"yaw_matrix_dispatch":[1243229,38],"yaw_matrix_table":[1245194,24],"yaw_matrix_mode0":[1243267,317],"direction_transform":[1241738,209],"world_counts":[-41762,40]}

const MAC_ALTERNATE := {"world_player_stage":[-43105,47],"ordinary_position":[-42517,72],"position_setter":[563398,42],"yaw_selection":[-37697,51],"yaw_application":[-36983,63],"position_xy":[1532090,4],"position_z":[1547258,4],"angle_fraction":[1550078,4],"angle_tau":[1550122,4],"camera_random":[129177,233],"camera_z":[1550170,4],"camera_pose":[134731,240],"controller_flags":[121650,55],"controller_release":[151038,144],"briefing_time_gate":[376268,79],"briefing_controller_gate":[385734,20],"world_zero_start":[-46499,7],"world_zero_end":[-45884,10],"world_story_gate":[-42091,62],"story_actor_dispatch":[-112,124],"empty_actor_radio":[50503,35],"world_post_groups":[-42029,135],"empty_npc_membership":[59086,28],"empty_npc_result":[59632,14],"empty_hostile_count":[-41894,20],"no_npc_weapons":[55113,16],"equipment_population":[-32684,30],"extra_story_station":[51842,55],"extra_story_cursor":[52351,24],"equipment_escort":[52890,37],"attached_actor_gate":[53353,28],"companion_gate":[53816,24],"camera_constructor_arguments":[337643,28],"camera_initial_view":[904322,321],"opening_placement_reset":[143248,15],"environment_reseed_gate":[-38226,28],"early_wormhole_gate":[-37949,77],"early_wormhole_position":[-37872,122],"wormhole_constructor":[655698,155],"wormhole_body":[641546,171],"wormhole_position_body":[641912,147],"time_reseed":[1120354,61],"yaw_model_mode":[-731055,7],"yaw_model_setter":[-729414,114],"yaw_matrix_dispatch":[1236085,37],"yaw_matrix_table":[1238050,24],"yaw_matrix_mode0":[1236122,317],"direction_transform":[1234546,227],"world_counts":[-41762,40]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Values.equal_value(data.get(key),VALUES[key]):return false
	return true

static func entry_conditions(data: Variant) -> bool:
	return data is Dictionary and data.size()==3 and data.get("companions_empty") is bool and data.companions_empty and data.get("location_match") is bool and not data.location_match and data.get("special_placement") is bool and not data.special_placement

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, departure: Dictionary, environment: Dictionary, world: Dictionary) -> String:
	if not data is Dictionary:return "Missing first-flight construction declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported first-flight construction declarations"
	if not Departure.parameters(departure) or not EnvironmentDefinitions.parameters(environment) or not World.parameters(world):return "First flight lacks its departure or ordinary environment context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "First flight lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid first-flight provenance"
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,[SPANS,MAC_ALTERNATE]) else "Invalid first flight extent"
