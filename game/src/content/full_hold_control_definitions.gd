extends RefCounted
## Verified second-trip target, holding and ordinary-flight context.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Pirate=preload("res://src/content/full_hold_pirate_definitions.gd")
const Guidance=preload("res://src/content/opening_npc_guidance_definitions.gd")
const Flight=preload("res://src/content/npc_flight_definitions.gd")
const Routes=preload("res://src/content/npc_route_definitions.gd")
const VALUES := {"scope":"full_hold_pirate_control","campaign_cursor":4,"actor_id":0,"actor_kind":8,"hull_catalogue_id":2,"player_ship_id":0,"player_target_count":1,"retains_generated_route":true,"holding_selects_player":true,"initial_model_draw_enabled":true,"initial_node_draw_requested":true,"held_node_draw_requested":false,"active_node_draw_requested":true,"activation_world_flag":false,"proximity_before_mode_dispatch":true,"target_activation_defers_flight":true,"alternate_player_position_for_proximity":true,"proximity_replaces_same_pass_steering_vector":true,"firing_range_uses_target_statistics":true}
const SPANS := {"npc_update":[610766,17180],"npc_constructor":[605172,2562],"membership":[59038,2050],"merge_targets":[536398,334],"assign_targets":[535982,246],"player_constructor":[549940,3862],"alternate_body_test":[558742,18],"alternate_body":[604878,14],"alternate_model":[905094,10],"model_position":[-724356,26],"model_constructor":[-725444,430],"model_request":[-722468,14],"model_submission":[-722442,28],"target_alive":[540880,16],"target_activity":[540924,14],"force_route":[535610,14]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, pirate: Dictionary, actors: Dictionary) -> String:
	if not data is Dictionary:return "Missing second-trip NPC control declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported second-trip NPC control declarations"
	var npc: Dictionary=actors.get("npc_initialization",{})
	if not Pirate.parameters(pirate) or not Guidance.parameters(npc.get("guidance")) or not Flight.parameters(npc.get("flight")) or not Routes.parameters(npc.get("routes")):return "Second-trip control lacks verified combat, guidance, flight or route context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Second-trip control lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid second-trip control provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid second-trip control extent: "+key
	return ""
