extends RefCounted
## Unwired source declarations; campaign navigation and portal state have shared owners.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Layouts=preload("res://src/content/declaration_layouts.gd")
const PostProbe=preload("res://src/content/post_probe_visit_definitions.gd")
const VALUES:={"scope":"ordinary_void_access","map_warning":{"first_cursor":32,"requires_nonnegative_source_system":true,"model_id":16994,"position_from_source_system_map_coordinates":true,"station_row_matches_source_system_and_station":true,"target_hint_first_cursor":33,"station_choice_uses_career_location_selection":true},"source":{"initial_system_id":18,"initial_station_id":91,"reroll":{"first_cursor":32,"last_cursor":44,"counter_unit":"qualifying_career_location_selection_call","skip_chosen_story_target_station":true,"skip_chosen_current_source_station":true,"threshold":11,"counter_after_reroll":0,"system_draw_exclusive_bound":22,"requires_career_system_access_bit":0,"excluded_system_ids":[10,15],"station_draw":"uniform_station_index_exclusive_bound","has_selected_story_target_equal_previous_source_guard":true,"selected_story_target_equals_old_source_retry_reachable_at_cursor32_33":false},"selection_at_or_after_cursor_disables_source":45,"disabled_system_id":-10,"disabled_station_id":-10},"ordinary_portal":{"active_while_cursor_below":43,"active_at_source_station_or_retained_void":true,"model_id":16994,"environment_slot":3,"entry_cursor":33,"selected_mission_kind_at_source_flight":-1,"selected_mission_story_at_source_flight":false,"story_list_mission_kind":8,"story_list_target_station_id":10,"contact_keeps_story_cursor":33,"contact_keeps_story_list_mission":true,"selected_void_system_id":-1,"selected_void_station_id":-1,"retained_void_system_id":-1,"retained_void_station_id":-1,"recorded_return_station":"actual_source_station","copies_live_player_pools":true,"retains_ammunition":true,"reload_flag":1,"requested_flight_state":2,"grants_cargo_or_reward_on_entry":false}}
const SPANS:={"map_warning_model":[810323,228],"map_station_marker":[816029,79],"map_target_hint":[821685,145],"map_location_selection":[818358,41],"career_location_selection":[857138,147],"selected_mission_sentinel":[857597,165],"kind8_selection":[858002,256],"wormhole_source_reroll":[858258,325],"ordinary_environment_gate":[-40062,99],"ordinary_portal_construction":[-37949,241],"factories_28_through_33":[862796,317],"living_portal_transaction":[379849,542],"bounded_random_index":[1120546,176],"flight_briefing_tick":[376268,79],"flight_briefing_start":[385724,536],"empty_mission_constructor":[400240,218]}
const MAC_SPANS:={"map_warning_model":[809691,228],"map_station_marker":[815397,79],"map_target_hint":[821053,145],"map_location_selection":[817726,41],"career_location_selection":[856506,147],"selected_mission_sentinel":[856965,165],"kind8_selection":[857370,256],"wormhole_source_reroll":[857626,325],"ordinary_environment_gate":[-40062,99],"ordinary_portal_construction":[-37949,241],"factories_28_through_33":[862164,317],"living_portal_transaction":[379337,542],"bounded_random_index":[1121098,176],"flight_briefing_tick":[375756,79],"flight_briefing_start":[385208,536],"empty_mission_constructor":[399724,218]}

static func parameters(data: Variant) -> bool:
	return data is Dictionary and Equal.equal_value(data,VALUES)

static func validate(data: Variant, proof: Variant, executable_bytes: int, architecture: String, arrival: Dictionary, visits: Variant) -> String:
	if not parameters(data):return "Unsupported Void access declarations"
	if architecture!="x86_64":return "Unsupported Void access source architecture"
	var layout: Dictionary
	if Equal.equal_value(visits,PostProbe.VALUES):
		layout=SPANS
	elif Equal.equal_value(visits,PostProbe.MAC_VALUES):
		layout=MAC_SPANS
	else:
		return "Disconnected cursor32/33 station declaration"
	var arrival_proof: Variant=arrival.get("provenance")
	if not arrival_proof is Dictionary:return "Void access source anchor is missing"
	var origin: Variant=arrival_proof.get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],executable_bytes):return "Void access source anchor is missing"
	return "" if Layouts.matches(proof,int(origin.offset),executable_bytes,[layout]) else "Disconnected Void access source declaration"
