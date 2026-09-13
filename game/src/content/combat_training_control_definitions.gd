extends RefCounted
## Ordinary four-actor movement and target membership for combat training.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Training=preload("res://src/content/combat_training_definitions.gd")
const Guidance=preload("res://src/content/opening_npc_guidance_definitions.gd")
const Flight=preload("res://src/content/npc_flight_definitions.gd")
const Routes=preload("res://src/content/npc_route_definitions.gd")
const Hull=preload("res://src/content/npc_hull_definitions.gd")
const VALUES := {"scope":"combat_training_live_control","campaign_cursor":7,"actor_count":4,"player_ship_id":0,"actor_kinds":[8,8,8,3],"hull_catalogue_ids":[2,2,2,30],"target_memberships":[[-1,3],[-1,3],[-1,3],[-1,0,1,2]],"player_weapon_targets":[0,1,2,3],"player_target_id":-1,"random_selection_chance":30,"random_selection_attempts":5,"initial_target_index":0,"initial_desired_position":[0,0,0],"companion_boost_chance":0,"companion_hostile":false,"pirate_initial_hostile":false,"pirate_updated_hostile":true,"companion_mode":0,"companion_active":true,"initial_mode_defers_flight":true,"npc_statistics_targeting_blocked":false,"attached_companions":false,"engagement_half_extent":50000,"proximity_half_extent":25000,"target_activation_half_extent":50000,"initial_model_draw_enabled":true,"initial_node_draw_requested":true,"initial_engine_draw_enabled":true,"nonplayer_selection_checks_range":false,"completed_route_retains_position_once":true,"rank_base":20,"rank_multiplier":14,"cursor_multiplier":4,"difficulty_offset":-0.5,"percentage_scale":100.0}
const SPANS := {"npc_update":[610766,17180],"npc_constructor":[605172,2562],"membership":[59038,2050],"merge_targets":[536398,334],"assign_targets":[535982,246],"player_constructor":[549940,3862],"alternate_body_test":[558742,18],"alternate_body":[604878,14],"alternate_model":[905094,10],"model_position":[-724356,26],"model_constructor":[-725444,430],"model_request":[-722468,14],"model_submission":[-722442,28],"target_alive":[540880,16],"target_activity":[540924,14],"force_route":[535610,14],"friendly":[535652,28],"friendly_test":[535680,14],"boost_chance":[609740,12],"base_constructor":[-81548,948],"statistics_constructor":[534164,980],"attached_test":[-77806,14],"model_initializer":[-79336,272],"model_initializer_wrapper":[609154,14],"mode_dispatch":[627906,40],"npc_model_vtable":[2399706,8],"companion_boost":[1127,7]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, training: Dictionary, actors: Dictionary) -> String:
	if not data is Dictionary:return "Missing combat-training control declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported combat-training control declarations"
	var npc: Dictionary=actors.get("npc_initialization",{})
	if not Training.parameters(training) or not Guidance.parameters(npc.get("guidance")) or not Flight.parameters(npc.get("flight")) or not Routes.parameters(npc.get("routes")) or not Hull.parameters(npc.get("hull")):return "Combat-training control lacks verified construction, guidance, flight, routes or hull context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Combat-training control lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid combat-training control provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid combat-training control extent: "+key
	return ""
