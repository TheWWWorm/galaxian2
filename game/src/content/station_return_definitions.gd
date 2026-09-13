extends RefCounted
## First mining return: source docking gates, retained cargo/vitals and dialogue.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/first_flight_definitions.gd")
const VALUES := {"scope":"first_mining_station_return","station_id":78,"system_id":15,"departing_cursor":2,"campaign_cursor":3,"source_state":5,"contact_radius":16000.0,"contact_before_motion":true,"volume_after_motion":true,"requires_station_target":true,"mission_kind":11,"restricted_mission_kind":154,"restricted_notice":21,"minimum_delivered_cargo":10,"cache_pools":["hull","armor","shield","gamma"],"cache_truncates":["shield","gamma"],"cargo_preserved_on_arrival":true,"clear_cargo_after_acknowledgement":true,"mode":1,"next_text_id":179,"final_text_id":180,"cursor_after_acknowledgement":4,"next_mission_kind":154,"next_mission_parameter":25,"reward_credits":0,"bonus_credits":0,"events":[{"speaker_id":2,"text_id":1711,"voice_event_id":411},{"speaker_id":0,"text_id":1712,"voice_event_id":412},{"speaker_id":2,"text_id":1713,"voice_event_id":413},{"speaker_id":0,"text_id":1714,"voice_event_id":414},{"speaker_id":2,"text_id":1715,"voice_event_id":415}]}
const SPANS := {"pre_motion_position_cache":[571243,52],"player_contact_stage":[576303,90],"station_contact_radius":[585133,67],"contact_radius_constant":[1557782,4],"flight_arrival_order":[368934,50],"mission_permission_and_notice":[383038,272],"station_contact_alternative":[384798,73],"station_transition":[384943,219],"station_world_entry":[414806,548],"station_mission_poll":[446081,55],"station_dialogue_select":[447318,69],"return_kind_dispatch":[875406,4],"return_station_condition":[873662,16],"return_station_match":[875132,33],"final_story_advance":[429803,47],"final_reward_and_retire":[431502,173],"story_cursor_increment":[859851,23],"next_story_dispatch":[871418,4],"next_mining_factory":[860566,82],"mode1_counts":[1555258,16],"mode1_return_events":[1546538,40],"player_active":[540924,14],"empty_mission":[400436,14],"actual_station_target":[562740,64],"pre_contact_flag":[598974,14],"current_position":[562384,14],"station_point_query":[107990,114],"exploration_cursor":[858058,26],"station_exclusion":[872234,192],"current_hull":[537554,12],"current_shield":[537302,14],"current_armor":[537354,12],"current_gamma":[537378,14],"cargo_list_setter":[730926,112],"voice_1711":[1562138,8],"voice_1712":[1562146,8],"voice_1713":[1562154,8],"voice_1714":[1562162,8],"voice_1715":[1562170,8]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary) -> String:
	if not data is Dictionary:return "Missing station return declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Flight.parameters(flight):return "Unsupported station return declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Station return lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid station return provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid station return extent: "+key
	return ""
