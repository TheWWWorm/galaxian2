extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Authored training dialogue and the acknowledged return transition.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Training=preload("res://src/content/combat_training_definitions.gd")
const Destruction=preload("res://src/content/combat_training_destruction_definitions.gd")
const SharedStory=preload("res://src/content/full_hold_story_definitions.gd")
const Briefing=preload("res://src/content/mining_briefing_definitions.gd")
const Objective=preload("res://src/content/mining_objective_definitions.gd")
const Voice=preload("res://src/content/radio_audio_definitions.gd")
const FirstFlight=preload("res://src/content/first_flight_definitions.gd")

const FirstReturn=preload("res://src/content/station_return_definitions.gd")
const VALUES := {"scope":"combat_training_story","campaign_cursor":7,"mission_kind":4,"station_id":78,"system_id":15,"briefing_events":[{"speaker_id":2,"text_id":1726,"voice_event_id":189},{"speaker_id":16,"text_id":1727,"voice_event_id":-1},{"speaker_id":16,"text_id":1728,"voice_event_id":-1}],"completion_events":[{"speaker_id":2,"text_id":1733,"voice_event_id":439},{"speaker_id":0,"text_id":1734,"voice_event_id":440},{"speaker_id":2,"text_id":1735,"voice_event_id":441},{"speaker_id":0,"text_id":1736,"voice_event_id":442},{"speaker_id":2,"text_id":1737,"voice_event_id":443}],"radio_events":[{"speaker_id":2,"text_id":1731,"voice_event_id":543,"condition":16,"values":[0]},{"speaker_id":0,"text_id":1732,"voice_event_id":544,"condition":6,"values":[0]}],"radio_timing":{"display_delay_ms":2000,"base_duration_ms":1500,"per_line_ms":2000},"radio_actor_ids":[0,1,2,3],"radio_excludes_scenery":true,"radio_requires_active":true,"radio_requires_not_friendly":true,"radio_requires_positive_hull":false,"defeat_condition":{"kind":18,"begin":0,"end":3,"actor_mode":4},"cursor_after_acknowledgement":8,"next_kind":11,"reward":0,"bonus":0,"unprotect_installed_equipment":true,"unprotect_cargo_equipment":true,"price_reset_index":"slot_position","price_minimum_value_index":15,"price_maximum_value_index":17,"price_midpoint_rounding":"truncate_toward_zero"}
const SPANS := {"mode0_counts":[1554602,32],"mode0_events":[1555970,24],"mode1_counts":[1555258,32],"mode1_events":[1546650,40],"briefing_voice":[1560362,8],"completion_voices":[1562362,40],"radio_voices":[1563194,16],"radio_dispatch":[104514,4],"radio_declaration":[83574,176],"active_condition_dispatch":[686370,4],"active_condition":[685457,82],"dependency_dispatch":[686330,4],"dependency_condition":[685352,23],"scenery_getter":[535540,28],"active_getter":[540924,14],"friendly_getter":[535680,14],"next_dispatch":[871434,4],"next_mission_and_equipment":[860799,240],"installed_getter":[730042,10],"cargo_getter":[730052,10],"protection_setter":[-84714,10],"price_getter":[-84640,10],"price_setter":[-84576,10],"departure_equipment_gate":[437109,243],"item_table_load":[-228846,15],"item_constructor":[-84910,22],"item_price_initialization":[-84866,140],"ordinary_entry_dispatch":[138774,13],"ordinary_story_dispatch":[152039,247],"ordinary_story_flag":[121726,10],"special_side_mission_gate":[137141,73],"ordinary_story_tail":[230121,22],"early_campaign_predicate":[858140,16],"entry_selection_0":[143263,24],"entry_selection_1":[143646,24],"entry_selection_2":[144596,24],"entry_selection_3":[147008,24],"entry_selection_4":[149098,24],"entry_selection_5":[150245,31],"entry_selection_6":[150276,24],"entry_selection_7":[150300,20],"entry_selection_8":[150320,20],"entry_selection_9":[150340,20],"entry_selection_10":[150360,22],"entry_selection_11":[150382,22],"entry_selection_12":[150404,26]}

const RETURN_VALUES := {"scope":"combat_training_station_return","station_id":78,"system_id":15,"departing_cursor":7,"campaign_cursor":8,"source_state":5,"mission_kind":11,"minimum_delivered_cargo":0,"clear_cargo_after_acknowledgement":false,"events":[{"speaker_id":2,"text_id":1738,"voice_event_id":444},{"speaker_id":0,"text_id":1739,"voice_event_id":445},{"speaker_id":2,"text_id":1740,"voice_event_id":446},{"speaker_id":0,"text_id":1741,"voice_event_id":447},{"speaker_id":2,"text_id":1742,"voice_event_id":448},{"speaker_id":0,"text_id":1743,"voice_event_id":449},{"speaker_id":2,"text_id":1744,"voice_event_id":450},{"speaker_id":0,"text_id":1745,"voice_event_id":451},{"speaker_id":2,"text_id":1746,"voice_event_id":452}],"cursor_after_acknowledgement":9,"next_mission_kind":11,"next_mission_parameter":0,"restart_station_after_acknowledgement":true}
const RETURN_SPANS := {"cargo_getter":[730052,10],"station_return_count":[1555290,4],"station_return_events":[1546690,72],"station_return_voices":[1562402,72],"station_next_dispatch":[871438,4],"station_next_factory":[861044,38],"station_restart_after_ack":[429803,160],"cargo_compaction":[-83178,244],"cargo_combined_order":[-82054,71]}

const NAVIGATION_VALUES := {"scope":"combat_training_navigation","owner":"player","position_sample":"preceding_root","clear_on_completion_acknowledgement":true,"marker_texture_id":10063,"in_view_image_id":1264,"in_view_region":75,"outside_image_id":1263,"outside_region":76,"distance_coordinate_scale":0.5,"distance_squared_scale":0.000244140625,"distance_result_scale":8,"kilometer_threshold":1000,"progress_notice":{"source_id":23,"text_ids":[532],"separator":"","rgb":[255,255,255]}}
const NAVIGATION_SPANS := {"navigation_world_binding":[-41918,24],"navigation_player_binding":[559872,14],"navigation_position_sample":[571243,52],"navigation_player_advance":[581940,104],"navigation_world_getter":[106016,14],"navigation_hud_binding":[662461,12],"navigation_images":[659717,54],"navigation_draw":[663003,299],"navigation_distance":[678014,822],"navigation_coordinate_scale":[1544586,4],"navigation_squared_scale":[1587742,4],"navigation_root_wrapper":[-192316,10],"navigation_root":[1248266,48],"navigation_ack_default":[355857,42],"navigation_ack_clear":[352952,110],"navigation_world_clear":[81700,82],"navigation_notice_dispatch":[-111842,4],"navigation_notice":[-113584,20]}

const MAC_ALTERNATE := {"mode0_counts":[1529586,32],"mode0_events":[1530962,32],"mode1_counts":[1530242,32],"mode1_events":[1521634,40],"briefing_voice":[1535426,8],"completion_voices":[1537426,40],"radio_voices":[1538258,16],"radio_dispatch":[104514,4],"radio_declaration":[83574,176],"active_condition_dispatch":[686918,4],"active_condition":[686005,82],"dependency_dispatch":[686878,4],"dependency_condition":[685900,23],"scenery_getter":[536076,28],"active_getter":[541460,14],"friendly_getter":[536216,14],"next_dispatch":[872066,4],"next_mission_and_equipment":[861431,240],"installed_getter":[730666,10],"cargo_getter":[730676,10],"protection_setter":[-84714,10],"price_getter":[-84640,10],"price_setter":[-84576,10],"departure_equipment_gate":[437543,242],"item_table_load":[-229852,15],"item_constructor":[-84910,22],"item_price_initialization":[-84866,140],"ordinary_entry_dispatch":[138774,13],"ordinary_story_dispatch":[152039,247],"ordinary_story_flag":[121726,10],"special_side_mission_gate":[137141,73],"ordinary_story_tail":[230135,22],"early_campaign_predicate":[858772,16],"entry_selection_0":[143263,24],"entry_selection_1":[143646,24],"entry_selection_2":[144596,24],"entry_selection_3":[147008,24],"entry_selection_4":[149098,24],"entry_selection_5":[150245,31],"entry_selection_6":[150276,24],"entry_selection_7":[150300,20],"entry_selection_8":[150320,20],"entry_selection_9":[150340,20],"entry_selection_10":[150360,22],"entry_selection_11":[150382,22],"entry_selection_12":[150404,26],"station_return_count":[1530274,4],"station_return_events":[1521674,72],"station_return_voices":[1537466,72],"station_next_dispatch":[872070,4],"station_next_factory":[861676,38],"station_restart_after_ack":[430231,160],"cargo_compaction":[-83178,244],"cargo_combined_order":[-82054,71],"navigation_world_binding":[-41918,24],"navigation_player_binding":[560408,14],"navigation_position_sample":[571779,52],"navigation_player_advance":[582476,104],"navigation_world_getter":[106016,14],"navigation_hud_binding":[663009,12],"navigation_images":[660265,54],"navigation_draw":[663551,299],"navigation_distance":[678562,822],"navigation_coordinate_scale":[1519570,4],"navigation_squared_scale":[1562806,4],"navigation_root_wrapper":[-192808,10],"navigation_root":[1241090,48],"navigation_ack_default":[355571,42],"navigation_ack_clear":[352666,110],"navigation_world_clear":[81700,82],"navigation_notice_dispatch":[-112262,4],"navigation_notice":[-114004,20]}
const MAC_VALUES := {"scope":"combat_training_story","campaign_cursor":7,"mission_kind":4,"station_id":78,"system_id":15,"briefing_events":[{"speaker_id":2,"text_id":1737,"voice_event_id":189},{"speaker_id":16,"text_id":1738,"voice_event_id":-1},{"speaker_id":16,"text_id":1739,"voice_event_id":-1},{"speaker_id":16,"text_id":1742,"voice_event_id":-1}],"completion_events":[{"speaker_id":2,"text_id":1747,"voice_event_id":439},{"speaker_id":0,"text_id":1748,"voice_event_id":440},{"speaker_id":2,"text_id":1749,"voice_event_id":441},{"speaker_id":0,"text_id":1750,"voice_event_id":442},{"speaker_id":2,"text_id":1751,"voice_event_id":443}],"radio_events":[{"speaker_id":2,"text_id":1745,"voice_event_id":543,"condition":16,"values":[0]},{"speaker_id":0,"text_id":1746,"voice_event_id":544,"condition":6,"values":[0]}],"radio_timing":{"display_delay_ms":2000,"base_duration_ms":1500,"per_line_ms":2000},"radio_actor_ids":[0,1,2,3],"radio_excludes_scenery":true,"radio_requires_active":true,"radio_requires_not_friendly":true,"radio_requires_positive_hull":false,"defeat_condition":{"kind":18,"begin":0,"end":3,"actor_mode":4},"cursor_after_acknowledgement":8,"next_kind":11,"reward":0,"bonus":0,"unprotect_installed_equipment":true,"unprotect_cargo_equipment":true,"price_reset_index":"slot_position","price_minimum_value_index":15,"price_maximum_value_index":17,"price_midpoint_rounding":"truncate_toward_zero"}
const MAC_RETURN_VALUES := {"scope":"combat_training_station_return","station_id":78,"system_id":15,"departing_cursor":7,"campaign_cursor":8,"source_state":5,"mission_kind":11,"minimum_delivered_cargo":0,"clear_cargo_after_acknowledgement":false,"events":[{"speaker_id":2,"text_id":1752,"voice_event_id":444},{"speaker_id":0,"text_id":1753,"voice_event_id":445},{"speaker_id":2,"text_id":1754,"voice_event_id":446},{"speaker_id":0,"text_id":1755,"voice_event_id":447},{"speaker_id":2,"text_id":1756,"voice_event_id":448},{"speaker_id":0,"text_id":1757,"voice_event_id":449},{"speaker_id":2,"text_id":1758,"voice_event_id":450},{"speaker_id":0,"text_id":1759,"voice_event_id":451},{"speaker_id":2,"text_id":1760,"voice_event_id":452}],"cursor_after_acknowledgement":9,"next_mission_kind":11,"next_mission_parameter":0,"restart_station_after_acknowledgement":true}

static func parameters(data: Variant) -> bool:
	return _parameters(data,VALUES,RETURN_VALUES) or _parameters(data,MAC_VALUES,MAC_RETURN_VALUES)

static func _parameters(data: Variant,expected: Dictionary,return_values: Dictionary) -> bool:
	if not data is Dictionary or data.size()!=expected.size()+1+int(data.has("station_return"))+int(data.has("navigation")) or not data.get("provenance") is Dictionary:return false
	if data.has("station_return") and not Equal.equal_value(data.station_return,return_values):return false
	if data.has("navigation") and not Equal.equal_value(data.navigation,NAVIGATION_VALUES):return false
	for key in expected:
		if not Equal.equal_value(data.get(key),expected[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, training: Dictionary, destruction: Dictionary, briefing: Dictionary, objective: Dictionary, dialogue: Dictionary, shared_story: Dictionary) -> String:
	if not data is Dictionary:return "Missing training story declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported training story declarations"
	if not Training.parameters(training) or not Destruction.parameters(destruction) or not Briefing.parameters(briefing) or not Objective.parameters(objective) or not SharedStory.parameters(shared_story):return "Training story lacks its encounter and shared dialogue context"
	if dialogue.get("campaign_cursor")!=0 or not Equal.equal_value(dialogue.get("timing"),VALUES.radio_timing) or not Voice.parameters(dialogue.get("voice")):return "Training radio lacks its source timing and voice context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Training story lacks its source anchor"
	var spans:=SPANS.duplicate()
	if data.has("station_return"):spans.merge(RETURN_SPANS)
	if data.has("navigation"):spans.merge(NAVIGATION_SPANS)
	var alternate: Dictionary={}
	for key in spans:
		alternate[key]=MAC_ALTERNATE[key]
	var layouts: Array=[]
	if _parameters(data,VALUES,RETURN_VALUES):layouts.append(spans)
	if _parameters(data,MAC_VALUES,MAC_RETURN_VALUES):layouts.append(alternate)
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid training story extents"

static func radio(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.combat_training_story):return {}
	var shared: Dictionary=bindings.opening_dialogue
	if not Voice.parameters(shared.get("voice")):return {}
	var data: Dictionary=bindings.combat_training_story
	var voice: Dictionary=shared.voice.duplicate(true)
	voice.event_ids=data.radio_events.map(func(row):return int(row.voice_event_id))
	voice.text_ids=data.radio_events.map(func(row):return int(row.text_id))
	return {"campaign_cursor":7,"events":data.radio_events.duplicate(true),"timing":data.radio_timing.duplicate(true),"voice":voice}

static func briefing(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.combat_training_story) or not Briefing.parameters(bindings.mining_briefing):return {}
	var result: Dictionary=bindings.mining_briefing.duplicate(true)
	result.campaign_cursor=7;result.mission_kind=4
	result.events=bindings.combat_training_story.briefing_events.duplicate(true)
	result.key_token="#KEY_PRIMARY"
	return result

static func flight(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.combat_training_story) or not FirstFlight.parameters(bindings.first_flight) or not Training.parameters(bindings.combat_training):return {}
	var result: Dictionary=bindings.first_flight.duplicate(true)
	result.campaign_cursor=7;result.mission_kind=4;result.actor_count=4
	return result

static func objective(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.combat_training_story) or not Objective.parameters(bindings.mining_objective):return {}
	var data: Dictionary=bindings.combat_training_story
	var result: Dictionary=bindings.mining_objective.duplicate(true)
	for key in ["campaign_cursor","mission_kind","station_id","cursor_after_acknowledgement","next_kind"]:result[key]=int(data[key])
	result.required_cargo=0;result.events=data.completion_events.duplicate(true)
	result.defeat_condition=data.defeat_condition.duplicate(true)
	return result

static func station_return(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.combat_training_story) or not bindings.combat_training_story.has("station_return") or not FirstReturn.parameters(bindings.station_return):return {}
	var result: Dictionary=bindings.station_return.duplicate(true)
	result.merge(bindings.combat_training_story.station_return.duplicate(true),true)
	return result

static func station_return_parameters(rules: Dictionary) -> bool:
	return _station_return_parameters(rules,RETURN_VALUES,FirstReturn.VALUES) or _station_return_parameters(rules,MAC_RETURN_VALUES,FirstReturn.MAC_VALUES)

static func _station_return_parameters(rules: Dictionary,expected: Dictionary,first_values: Dictionary) -> bool:
	for key in expected:
		if not Equal.equal_value(rules.get(key),expected[key]):return false
	var original:=rules.duplicate(true)
	for key in expected:
		if first_values.has(key):original[key]=first_values[key]
		else:original.erase(key)
	return FirstReturn.parameters(original)

static func navigation(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.combat_training_story):return {}
	return bindings.combat_training_story.get("navigation",{}).duplicate(true)
